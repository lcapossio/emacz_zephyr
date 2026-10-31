/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 */

/* Subnet-independent emacZero discovery and IPv4 provisioning. */

#include <errno.h>
#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/net/ethernet.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_ip.h>
#include <zephyr/net/socket.h>
#include <zephyr/sys/byteorder.h>
#include <zephyr/sys/crc.h>

#include "hostio.h"
#include "provision.h"

/* Mailbox is uncached DDR (see DBusCached I/O predicate in the vex build).
 * A plain volatile pointer therefore observes host writes with no fence,
 * and vice-versa. Do NOT add cache maintenance here — the region is I/O by
 * construction; a stray flush against uncached memory is a nop on this CPU
 * but signals confusion about the mapping.
 */
BUILD_ASSERT(sizeof(struct emacz_jtag_mailbox) <= EMACZ_HOSTIO_SLOT_SIZE);
#define emacz_jtag_mailbox (*(volatile struct emacz_jtag_mailbox *)EMACZ_JTAG_MAILBOX_ADDR)

#define PROV_MAGIC 0x455a4346u /* "EZCF" */
#define PROV_VERSION 1u
#define PROV_PACKET_SIZE 36u
#define PROV_CRC_OFFSET 32u
#define PROV_THREAD_STACK_SIZE 2048u
#define PROV_THREAD_PRIORITY -3
#define PROV_MULTICAST_ADDR 0xefff4d5au /* 239.255.77.90 */
/* How often the JTAG mailbox is polled while no request arrives */
#define PROV_MAILBOX_POLL_MS 100

enum prov_op {
	PROV_DISCOVER = 1,
	PROV_OFFER = 2,
	PROV_CONFIG = 3,
	PROV_ACK = 4,
	PROV_NACK = 5,
};

enum prov_status {
	PROV_OK = 0,
	PROV_BAD_REQUEST = 1,
	PROV_BAD_TOKEN = 2,
	PROV_BAD_ADDRESS = 3,
	PROV_APPLY_FAILED = 4,
};

struct prov_message {
	uint8_t version;
	uint8_t op;
	uint8_t status;
	uint8_t prefix;
	uint32_t xid;
	uint8_t mac[NET_ETH_ADDR_LEN];
	struct in_addr ip;
	struct in_addr gateway;
	uint32_t token;
};

static struct net_if *prov_iface;
static struct in_addr prov_addr;
/* Whether prov_addr is actually attached to prov_iface. False when the
 * bootstrap add failed at startup, in which case there is nothing to remove
 * before installing the first host-supplied address.
 */
static bool prov_addr_installed;
static struct in_addr prov_gateway;
static uint8_t prov_prefix;
static uint32_t prov_token;
static uint32_t prov_xid;
static uint8_t prov_mac[NET_ETH_ADDR_LEN];
/* Replies go out on their own socket, bound to prov_addr: see open_reply_sock() */
static int prov_reply_sock = -1;
K_THREAD_STACK_DEFINE(prov_thread_stack, PROV_THREAD_STACK_SIZE);
static struct k_thread prov_thread;

static void prefix_to_mask(uint8_t prefix, struct in_addr *mask)
{
	uint32_t value = prefix == 0u ? 0u : UINT32_MAX << (32u - prefix);

	sys_put_be32(value, mask->s4_addr);
}

static bool addr_is_usable(const struct in_addr *addr, uint8_t prefix,
			   const struct in_addr *gateway)
{
	uint32_t ip = sys_get_be32(addr->s4_addr);
	uint32_t gw = sys_get_be32(gateway->s4_addr);
	uint32_t mask;
	uint32_t host;

	if (prefix == 0u || prefix > 30u || ip == 0u || ip == UINT32_MAX ||
	    (ip & 0xf0000000u) == 0xe0000000u || (ip & 0xff000000u) == 0x7f000000u) {
		return false;
	}

	mask = UINT32_MAX << (32u - prefix);
	host = ip & ~mask;
	if (host == 0u || host == ~mask) {
		return false;
	}

	if (gw != 0u && ((gw & mask) != (ip & mask) || gw == ip || gw == (ip & mask) ||
			 gw == ((ip & mask) | ~mask))) {
		return false;
	}

	return true;
}

static void encode_message(uint8_t *buf, const struct prov_message *msg)
{
	memset(buf, 0, PROV_PACKET_SIZE);
	sys_put_be32(PROV_MAGIC, &buf[0]);
	buf[4] = msg->version;
	buf[5] = msg->op;
	buf[6] = msg->status;
	buf[7] = msg->prefix;
	sys_put_be32(msg->xid, &buf[8]);
	memcpy(&buf[12], msg->mac, NET_ETH_ADDR_LEN);
	memcpy(&buf[20], msg->ip.s4_addr, NET_IPV4_ADDR_SIZE);
	memcpy(&buf[24], msg->gateway.s4_addr, NET_IPV4_ADDR_SIZE);
	sys_put_be32(msg->token, &buf[28]);
	sys_put_be32(crc32_ieee(buf, PROV_CRC_OFFSET), &buf[PROV_CRC_OFFSET]);
}

static bool decode_message(const uint8_t *buf, size_t len, struct prov_message *msg)
{
	if (len != PROV_PACKET_SIZE || sys_get_be32(&buf[0]) != PROV_MAGIC ||
	    buf[4] != PROV_VERSION ||
	    sys_get_be32(&buf[PROV_CRC_OFFSET]) != crc32_ieee(buf, PROV_CRC_OFFSET)) {
		return false;
	}

	msg->version = buf[4];
	msg->op = buf[5];
	msg->status = buf[6];
	msg->prefix = buf[7];
	msg->xid = sys_get_be32(&buf[8]);
	memcpy(msg->mac, &buf[12], NET_ETH_ADDR_LEN);
	memcpy(msg->ip.s4_addr, &buf[20], NET_IPV4_ADDR_SIZE);
	memcpy(msg->gateway.s4_addr, &buf[24], NET_IPV4_ADDR_SIZE);
	msg->token = sys_get_be32(&buf[28]);
	return true;
}

/*
 * The stack picks a reply's source address by itself, and for a multicast
 * destination it never picks a link-local one: before the host configures
 * the board, that would send from 0.0.0.0. Bind the reply socket to
 * prov_addr instead, and connect it to the group so that it never receives.
 * The bound address changes with prov_addr, so apply_config() closes it.
 */
static int open_reply_sock(void)
{
	struct sockaddr_in local = {
		.sin_family = AF_INET,
		.sin_addr = prov_addr,
	};
	struct sockaddr_in group = {
		.sin_family = AF_INET,
		.sin_port = htons(EMACZ_PROVISION_PORT),
		.sin_addr.s_addr = htonl(PROV_MULTICAST_ADDR),
	};
	int sock;

	if (prov_reply_sock >= 0) {
		return prov_reply_sock;
	}

	sock = zsock_socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	if (sock < 0) {
		return -errno;
	}
	/* without an installed address, fall back to the stack's choice */
	if ((prov_addr_installed &&
	     zsock_bind(sock, (struct sockaddr *)&local, sizeof(local)) < 0) ||
	    zsock_connect(sock, (struct sockaddr *)&group, sizeof(group)) < 0) {
		int err = -errno;

		(void)zsock_close(sock);
		return err;
	}

	prov_reply_sock = sock;
	return sock;
}

static void close_reply_sock(void)
{
	if (prov_reply_sock >= 0) {
		(void)zsock_close(prov_reply_sock);
		prov_reply_sock = -1;
	}
}

static int send_response(uint8_t op, uint8_t status, uint32_t xid)
{
	uint8_t payload[PROV_PACKET_SIZE];
	struct prov_message response = {
		.version = PROV_VERSION,
		.op = op,
		.status = status,
		.prefix = prov_prefix,
		.xid = xid,
		.ip = prov_addr,
		.gateway = prov_gateway,
		.token = prov_token,
	};
	int sock = open_reply_sock();

	if (sock < 0) {
		return sock;
	}

	memcpy(response.mac, prov_mac, sizeof(response.mac));
	encode_message(payload, &response);
	if (zsock_send(sock, payload, sizeof(payload), 0) < 0) {
		return -errno;
	}
	return 0;
}

static int apply_config(const struct prov_message *request)
{
	struct in_addr mask;
	struct in_addr old_mask;
	struct in_addr old_addr = prov_addr;

	if (!addr_is_usable(&request->ip, request->prefix, &request->gateway)) {
		return -EINVAL;
	}

	if (prov_addr_installed && !net_if_ipv4_addr_rm(prov_iface, &old_addr)) {
		return -EIO;
	}
	prov_addr_installed = false;
	/* bound to the address just removed, or to none */
	close_reply_sock();

	if (net_if_ipv4_addr_add(prov_iface, &request->ip, NET_ADDR_MANUAL, 0) == NULL) {
		if (net_if_ipv4_addr_add(prov_iface, &old_addr, NET_ADDR_MANUAL, 0) != NULL) {
			prefix_to_mask(prov_prefix, &old_mask);
			(void)net_if_ipv4_set_netmask_by_addr(prov_iface, &old_addr, &old_mask);
			prov_addr_installed = true;
		}
		return -ENOMEM;
	}

	prefix_to_mask(request->prefix, &mask);
	if (!net_if_ipv4_set_netmask_by_addr(prov_iface, &request->ip, &mask)) {
		(void)net_if_ipv4_addr_rm(prov_iface, &request->ip);
		if (net_if_ipv4_addr_add(prov_iface, &old_addr, NET_ADDR_MANUAL, 0) != NULL) {
			prefix_to_mask(prov_prefix, &old_mask);
			(void)net_if_ipv4_set_netmask_by_addr(prov_iface, &old_addr, &old_mask);
			prov_addr_installed = true;
		}
		return -EIO;
	}

	net_if_ipv4_set_gw(prov_iface, &request->gateway);
	prov_addr_installed = true;
	prov_addr = request->ip;
	prov_gateway = request->gateway;
	prov_prefix = request->prefix;
	return 0;
}

static void poll_jtag_mailbox(void)
{
	static uint32_t last_applied_epoch;
	static bool armed;
	uint32_t magic = emacz_jtag_mailbox.magic;
	uint32_t epoch;
	struct prov_message request = {0};
	int ret;

	if (magic != EMACZ_JTAG_MAILBOX_MAGIC) {
		/* Host hasn't populated the block yet (or wrote a stale zero).
		 * Once armed, a magic drop-out clears armed so a fresh
		 * host writer restarts the epoch-diff logic cleanly.
		 */
		armed = false;
		return;
	}
	epoch = emacz_jtag_mailbox.epoch;
	if (!armed) {
		/* First poll after boot, or after a magic drop-out.
		 *
		 * Do not blanket-skip here. The host stages the mailbox over
		 * JTAG-AXI, and in the normal bring-up flow it can land before
		 * the CPU is released -- so an unconditional skip drops a live
		 * request while still writing ack_epoch, i.e. reports success
		 * for an address that was never applied.
		 *
		 * Discriminate on the mailbox's own ack field instead. Anything
		 * already serviced -- including contents persisted in DDR from a
		 * previous board run, which is what this guard exists for --
		 * carries ack_epoch == epoch. Everything else is pending work.
		 */
		armed = true;
		if (emacz_jtag_mailbox.ack_epoch == epoch) {
			last_applied_epoch = epoch;
			return;
		}
	} else if (epoch == last_applied_epoch) {
		return;
	}

	sys_put_be32(emacz_jtag_mailbox.ip, request.ip.s4_addr);
	sys_put_be32(emacz_jtag_mailbox.gateway, request.gateway.s4_addr);
	request.prefix = (uint8_t)emacz_jtag_mailbox.prefix;
	memcpy(request.mac, prov_mac, sizeof(request.mac));

	if (!addr_is_usable(&request.ip, request.prefix, &request.gateway)) {
		emacz_jtag_mailbox.status = -EINVAL;
		emacz_jtag_mailbox.ack_epoch = epoch;
		last_applied_epoch = epoch;
		return;
	}

	ret = apply_config(&request);
	emacz_jtag_mailbox.status = ret;
	emacz_jtag_mailbox.ack_epoch = epoch;
	last_applied_epoch = epoch;
}

static int open_request_sock(void)
{
	/* INADDR_ANY: requests arrive as 255.255.255.255 broadcasts */
	struct sockaddr_in addr = {
		.sin_family = AF_INET,
		.sin_port = htons(EMACZ_PROVISION_PORT),
		.sin_addr.s_addr = htonl(INADDR_ANY),
	};
	int sock = zsock_socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);

	if (sock < 0) {
		return -errno;
	}
	if (zsock_bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		int err = -errno;

		(void)zsock_close(sock);
		return err;
	}
	return sock;
}

static void handle_request(const struct prov_message *request)
{
	if (request->op == PROV_DISCOVER) {
		prov_xid = request->xid;
		prov_token =
			k_cycle_get_32() ^ request->xid ^ sys_get_be32(&prov_mac[2]) ^ 0x455a4346u;
		if (prov_token == 0u) {
			prov_token = 1u;
		}
		(void)send_response(PROV_OFFER, PROV_OK, request->xid);
		return;
	}

	if (request->op != PROV_CONFIG || memcmp(request->mac, prov_mac, sizeof(prov_mac)) != 0) {
		return;
	}
	if (request->xid != prov_xid || request->token == 0u || request->token != prov_token) {
		(void)send_response(PROV_NACK, PROV_BAD_TOKEN, request->xid);
		return;
	}
	if (!addr_is_usable(&request->ip, request->prefix, &request->gateway)) {
		(void)send_response(PROV_NACK, PROV_BAD_ADDRESS, request->xid);
		return;
	}

	if (apply_config(request) != 0) {
		(void)send_response(PROV_NACK, PROV_APPLY_FAILED, request->xid);
	} else {
		prov_token = 0u;
		(void)send_response(PROV_ACK, PROV_OK, request->xid);
	}
}

static void provision_thread_fn(void *arg1, void *arg2, void *arg3)
{
	int sock = -1;

	ARG_UNUSED(arg1);
	ARG_UNUSED(arg2);
	ARG_UNUSED(arg3);

	while (true) {
		/* one byte more than a message, so an oversized one shows */
		uint8_t buf[PROV_PACKET_SIZE + 1u];
		struct prov_message request;
		struct zsock_pollfd pfd;
		ssize_t len;

		/* Poll the JTAG mailbox every iteration, not just on the idle
		 * tick. It is the fallback path for when the network is
		 * unusable, so it must not be starved by the very traffic that
		 * would make someone reach for it: a steady stream of broadcast
		 * datagrams to port 5004 keeps the socket readable indefinitely.
		 */
		poll_jtag_mailbox();

		if (sock < 0) {
			/* keep retrying: the mailbox above must stay serviced */
			sock = open_request_sock();
			if (sock < 0) {
				k_msleep(PROV_MAILBOX_POLL_MS);
				continue;
			}
		}

		pfd.fd = sock;
		pfd.events = ZSOCK_POLLIN;
		if (zsock_poll(&pfd, 1, PROV_MAILBOX_POLL_MS) <= 0 ||
		    (pfd.revents & ZSOCK_POLLIN) == 0) {
			continue;
		}

		len = zsock_recv(sock, buf, sizeof(buf), ZSOCK_MSG_DONTWAIT);
		if (len < 0 || !decode_message(buf, (size_t)len, &request)) {
			continue;
		}
		handle_request(&request);
	}
}

int emacz_provision_start(struct net_if *iface)
{
	const struct net_linkaddr *link_addr;
	struct in_addr mask;
	int ret = 0;
	int up;

	if (iface == NULL) {
		return -EINVAL;
	}
	link_addr = net_if_get_link_addr(iface);
	if (link_addr == NULL || link_addr->len != NET_ETH_ADDR_LEN) {
		return -EINVAL;
	}

	prov_iface = iface;
	memcpy(prov_mac, link_addr->addr, sizeof(prov_mac));
	prov_addr.s4_addr[0] = 169u;
	prov_addr.s4_addr[1] = 254u;
	prov_addr.s4_addr[2] = (uint8_t)(prov_mac[4] ^ 0x80u);
	prov_addr.s4_addr[3] = prov_mac[5];
	if (prov_addr.s4_addr[2] == 0u || prov_addr.s4_addr[2] == 255u) {
		prov_addr.s4_addr[2] = 1u;
	}
	if (prov_addr.s4_addr[3] == 0u || prov_addr.s4_addr[3] == 255u) {
		prov_addr.s4_addr[3] = 1u;
	}
	memset(&prov_gateway, 0, sizeof(prov_gateway));
	prov_prefix = 16u;

	/* Bring up the link-local bootstrap, but do not abort on failure.
	 *
	 * The provisioning thread also carries the JTAG mailbox poller, which
	 * is the only way to reach a board whose network side is unusable --
	 * exactly the situation these failures describe. Returning early left
	 * no listener, no mailbox poll, and no retry: a PHY that has no
	 * carrier yet at boot bricked provisioning for the whole run.
	 *
	 * Report the first error to the caller for logging, then start the
	 * thread regardless.
	 */
	if (net_if_ipv4_addr_add(iface, &prov_addr, NET_ADDR_MANUAL, 0) == NULL) {
		ret = -ENOMEM;
	} else {
		prov_addr_installed = true;
		prefix_to_mask(prov_prefix, &mask);
		if (!net_if_ipv4_set_netmask_by_addr(iface, &prov_addr, &mask)) {
			ret = -EIO;
		}
	}

	up = net_if_up(iface);
	if (up != 0 && up != -EALREADY && ret == 0) {
		ret = up;
	}

	k_thread_create(&prov_thread, prov_thread_stack, K_THREAD_STACK_SIZEOF(prov_thread_stack),
			provision_thread_fn, NULL, NULL, NULL, PROV_THREAD_PRIORITY, 0, K_NO_WAIT);
	k_thread_name_set(&prov_thread, "emacz_provision");
	return ret;
}
