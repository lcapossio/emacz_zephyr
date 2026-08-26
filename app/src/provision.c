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

#include "eth_emaczero.h"
#include "eth_emaczero_profile.h"
#include "provision.h"

/* Mailbox is uncached DDR (see DBusCached I/O predicate in the vex build).
 * A plain volatile pointer therefore observes host writes with no fence,
 * and vice-versa. Do NOT add cache maintenance here — the region is I/O by
 * construction; a stray flush against uncached memory is a nop on this CPU
 * but signals confusion about the mapping.
 */
#define emacz_jtag_mailbox \
	(*(volatile struct emacz_jtag_mailbox *)EMACZERO_JTAG_MAILBOX_ADDR)

#define PROV_MAGIC 0x455a4346u /* "EZCF" */
#define PROV_VERSION 1u
#define PROV_PACKET_SIZE 36u
#define PROV_CRC_OFFSET 32u
#define PROV_THREAD_STACK_SIZE 2048u
#define PROV_THREAD_PRIORITY -3
#define PROV_MULTICAST_ADDR 0xefff4d5au /* 239.255.77.90 */

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
static struct in_addr prov_gateway;
static uint8_t prov_prefix;
static uint32_t prov_token;
static uint32_t prov_xid;
static uint8_t prov_mac[NET_ETH_ADDR_LEN];
K_THREAD_STACK_DEFINE(prov_thread_stack, PROV_THREAD_STACK_SIZE);
static struct k_thread prov_thread;
K_MSGQ_DEFINE(prov_rx_queue, PROV_PACKET_SIZE, 8, 4);

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

static uint16_t ipv4_checksum(const uint8_t *data, size_t len)
{
	uint32_t sum = 0u;

	for (size_t i = 0; i < len; i += 2u) {
		sum += sys_get_be16(&data[i]);
	}
	while ((sum >> 16) != 0u) {
		sum = (sum & 0xffffu) + (sum >> 16);
	}
	return (uint16_t)~sum;
}

static int send_response(uint8_t op, uint8_t status, uint32_t xid)
{
	uint8_t frame[14u + 20u + 8u + PROV_PACKET_SIZE] = {0};
	uint8_t *ip = &frame[14];
	uint8_t *udp = &frame[34];
	uint8_t *payload = &frame[42];
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

	memcpy(response.mac, prov_mac, sizeof(response.mac));
	encode_message(payload, &response);

	frame[0] = 0x01u;
	frame[1] = 0x00u;
	frame[2] = 0x5eu;
	frame[3] = 0x7fu;
	frame[4] = 0x4du;
	frame[5] = 0x5au;
	memcpy(&frame[6], prov_mac, sizeof(prov_mac));
	sys_put_be16(0x0800u, &frame[12]);
	ip[0] = 0x45u;
	sys_put_be16((uint16_t)(20u + 8u + PROV_PACKET_SIZE), &ip[2]);
	sys_put_be16((uint16_t)xid, &ip[4]);
	ip[8] = 1u;
	ip[9] = IPPROTO_UDP;
	memcpy(&ip[12], prov_addr.s4_addr, NET_IPV4_ADDR_SIZE);
	sys_put_be32(PROV_MULTICAST_ADDR, &ip[16]);
	sys_put_be16(ipv4_checksum(ip, 20u), &ip[10]);
	sys_put_be16(EMACZ_PROVISION_PORT, &udp[0]);
	sys_put_be16(EMACZ_PROVISION_PORT, &udp[2]);
	sys_put_be16((uint16_t)(8u + PROV_PACKET_SIZE), &udp[4]);
	/* A zero UDP checksum is valid for IPv4 and avoids offload assumptions. */
	return emaczero_send_raw_frame(prov_iface, frame, sizeof(frame));
}

static int apply_config(const struct prov_message *request)
{
	struct in_addr mask;
	struct in_addr old_mask;
	struct in_addr old_addr = prov_addr;

	if (!addr_is_usable(&request->ip, request->prefix, &request->gateway)) {
		return -EINVAL;
	}

	if (!net_if_ipv4_addr_rm(prov_iface, &old_addr)) {
		return -EIO;
	}

	if (net_if_ipv4_addr_add(prov_iface, &request->ip, NET_ADDR_MANUAL, 0) == NULL) {
		(void)net_if_ipv4_addr_add(prov_iface, &old_addr, NET_ADDR_MANUAL, 0);
		prefix_to_mask(prov_prefix, &old_mask);
		(void)net_if_ipv4_set_netmask_by_addr(prov_iface, &old_addr, &old_mask);
		return -ENOMEM;
	}

	prefix_to_mask(request->prefix, &mask);
	if (!net_if_ipv4_set_netmask_by_addr(prov_iface, &request->ip, &mask)) {
		(void)net_if_ipv4_addr_rm(prov_iface, &request->ip);
		(void)net_if_ipv4_addr_add(prov_iface, &old_addr, NET_ADDR_MANUAL, 0);
		prefix_to_mask(prov_prefix, &old_mask);
		(void)net_if_ipv4_set_netmask_by_addr(prov_iface, &old_addr, &old_mask);
		return -EIO;
	}

	net_if_ipv4_set_gw(prov_iface, &request->gateway);
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
		/* First time we see valid magic: latch the current epoch so
		 * we do not re-apply the value already in effect on cold boot
		 * (e.g. persistent DDR contents from a prior board run).
		 */
		last_applied_epoch = epoch;
		emacz_jtag_mailbox.ack_epoch = epoch;
		emacz_jtag_mailbox.status = 0;
		armed = true;
		return;
	}
	if (epoch == last_applied_epoch) {
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

static void provision_thread_fn(void *arg1, void *arg2, void *arg3)
{
	ARG_UNUSED(arg1);
	ARG_UNUSED(arg2);
	ARG_UNUSED(arg3);

	while (true) {
		uint8_t buf[PROV_PACKET_SIZE];
		struct prov_message request;
		int rc = k_msgq_get(&prov_rx_queue, buf, K_MSEC(100));

		if (rc == -EAGAIN) {
			/* Idle tick: fold in the JTAG mailbox so bring-up
			 * doesn't need any network reachability to change IP.
			 */
			poll_jtag_mailbox();
			continue;
		}
		if (rc != 0) {
			continue;
		}
		if (!decode_message(buf, sizeof(buf), &request)) {
			continue;
		}

		if (request.op == PROV_DISCOVER) {
			prov_xid = request.xid;
			prov_token = k_cycle_get_32() ^ request.xid ^ sys_get_be32(&prov_mac[2]) ^
				     0x455a4346u;
			if (prov_token == 0u) {
				prov_token = 1u;
			}
			(void)send_response(PROV_OFFER, PROV_OK, request.xid);
			continue;
		}

		if (request.op != PROV_CONFIG ||
		    memcmp(request.mac, prov_mac, sizeof(prov_mac)) != 0) {
			continue;
		}
		if (request.xid != prov_xid || request.token == 0u || request.token != prov_token) {
			(void)send_response(PROV_NACK, PROV_BAD_TOKEN, request.xid);
			continue;
		}
		if (!addr_is_usable(&request.ip, request.prefix, &request.gateway)) {
			(void)send_response(PROV_NACK, PROV_BAD_ADDRESS, request.xid);
			continue;
		}

		if (apply_config(&request) != 0) {
			(void)send_response(PROV_NACK, PROV_APPLY_FAILED, request.xid);
		} else {
			prov_token = 0u;
			(void)send_response(PROV_ACK, PROV_OK, request.xid);
		}
	}
}

bool emacz_provision_ingress(const uint8_t *payload, size_t len)
{
	if (payload == NULL || len != PROV_PACKET_SIZE) {
		return false;
	}

	/* k_msgq_put(K_NO_WAIT) is ISR-safe. A full queue means duplicate host
	 * retries are already pending, so consume the frame without stalling RX.
	 */
	(void)k_msgq_put(&prov_rx_queue, payload, K_NO_WAIT);
	return true;
}

int emacz_provision_start(struct net_if *iface)
{
	const struct net_linkaddr *link_addr;
	struct in_addr mask;
	int ret;

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

	if (net_if_ipv4_addr_add(iface, &prov_addr, NET_ADDR_MANUAL, 0) == NULL) {
		return -ENOMEM;
	}
	prefix_to_mask(prov_prefix, &mask);
	if (!net_if_ipv4_set_netmask_by_addr(iface, &prov_addr, &mask)) {
		return -EIO;
	}

	ret = net_if_up(iface);
	if (ret != 0 && ret != -EALREADY) {
		return ret;
	}

	k_thread_create(&prov_thread, prov_thread_stack, K_THREAD_STACK_SIZEOF(prov_thread_stack),
			provision_thread_fn, NULL, NULL, NULL, PROV_THREAD_PRIORITY, 0, K_NO_WAIT);
	k_thread_name_set(&prov_thread, "emacz_provision");
	return 0;
}

bool emacz_provision_get_ipv4(struct in_addr *addr)
{
	if (addr == NULL || prov_iface == NULL) {
		return false;
	}
	*addr = prov_addr;
	return true;
}
