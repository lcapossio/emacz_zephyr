/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 */

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_ip.h>
#include <zephyr/net/net_stats.h>
#include <zephyr/net/socket.h>
#if defined(CONFIG_NET_ZPERF)
#include <zephyr/net/zperf.h>
#endif
#include <zephyr/sys/printk.h>
#include <zephyr/sys/sys_io.h>

#include <ethernet/arp.h>

#include "eth_emaczero.h"
#include "eth_emaczero_profile.h"
#include "provision.h"

#if defined(CONFIG_NET_STATISTICS)
extern struct net_stats net_stats;
#endif

#define UARTLITE_BASE 0x40600000u
#define UARTLITE_TX_FIFO 0x04u
#define UARTLITE_STATUS 0x08u
#define UARTLITE_CONTROL 0x0cu
#define UARTLITE_STATUS_TX_FULL BIT(3)
#define UARTLITE_CONTROL_RST_RX BIT(1)
#define UARTLITE_CONTROL_RST_TX BIT(0)

#define SCRATCH_MAGIC 0x5a455048u

#define EMACZERO_BASE 0x44a00000u
#define EMZ_REG_VERSION 0x00u
#define EMZ_REG_CTRL 0x04u
#define EMZ_REG_STATUS 0x08u
#define EMZ_REG_MAC_LO 0x0cu
#define EMZ_REG_MAC_HI 0x10u
#define EMZ_REG_RX_FRAME_CNT 0x30u
#define EMZ_REG_RX_BYTE_CNT 0x34u
#define EMZ_REG_RX_ERR_CNT 0x38u
#define EMZ_REG_RX_ERR_ALIGN 0x4cu
#define EMZ_REG_RX_ERR_OVERFLOW 0x50u
#define EMZ_REG_RX_ERR_OVERSIZE 0x54u
#define EMZ_REG_RX_BCAST 0x58u
#define EMZ_REG_RX_MCAST 0x5cu
#define EMZ_REG_RX_SIZE_1024_1518 0x74u
#define EMZ_REG_GATE_MAGIC 0x100u
#define EMZ_REG_GATE_GOOD_FRAMES 0x104u
#define EMZ_REG_GATE_DROPPED_BAD_FRAMES 0x108u
#define EMZ_REG_GATE_DROPPED_OVERFLOW_FRAMES 0x10cu
#define EMZ_REG_GATE_DRAIN_SAMPLES 0x110u
#define EMZ_REG_GATE_DRAIN_CYCLES_TOTAL 0x114u
#define EMZ_REG_GATE_DRAIN_CYCLES_MAX 0x118u
#define EMZ_REG_GATE_DRAIN_LT_50US 0x11cu
#define EMZ_REG_GATE_DRAIN_50_100US 0x120u
#define EMZ_REG_GATE_DRAIN_100_200US 0x124u
#define EMZ_REG_GATE_DRAIN_200_500US 0x128u
#define EMZ_REG_GATE_DRAIN_GE_500US 0x12cu
#define EMZ_REG_GATE_DRAIN_TREADY_LOW_CYCLES 0x130u
#define EMZ_REG_GATE_DRAIN_TREADY_LOW_CYCLES_MAX 0x134u
#define EMZ_REG_GATE_DRAIN_TREADY_LOW_SAMPLES 0x138u

#define ZPERF_PORT 5001u
#define UDP_SINK_PORT 5001u
#define UDP_SINK_BUFFER_SIZE 1536u
#define UDP_SINK_THREAD_STACK_SIZE 2048u
#define UDP_SINK_THREAD_PRIORITY -2
#define PROFILE_PORT 5002u
#define PROFILE_THREAD_STACK_SIZE 2048u
#define PROFILE_THREAD_PRIORITY 4
#define TX_BENCH_PORT 5003u
#define TX_BENCH_MAX_PAYLOAD 1472u
#define TX_BENCH_FRAME_MAX (14u + 20u + 8u + TX_BENCH_MAX_PAYLOAD)
#define TX_BENCH_BURST_COUNT 32u
#define TX_BENCH_DEFAULT_DURATION_MS 5000u
#define TX_BENCH_DEFAULT_PAYLOAD 1472u

volatile uint32_t emacz_scratch_heartbeat[2];
volatile uint32_t emacz_boot_marker;
#if !defined(CONFIG_ETH_EMACZERO_DMA_MEMORY_SIZE) || CONFIG_ETH_EMACZERO_DMA_MEMORY_SIZE == 0
volatile struct emaczero_perf_stats emaczero_perf_stats;
#endif

static void raw_uart_puts(const char *str)
{
#if defined(CONFIG_EMACZ_APP_RAW_UART)
	for (; *str != '\0'; str++) {
		uint32_t timeout = 1000000u;

		while ((sys_read32(UARTLITE_BASE + UARTLITE_STATUS) & UARTLITE_STATUS_TX_FULL) != 0u) {
			if (timeout-- == 0u) {
				return;
			}
		}
		sys_write32((uint8_t)*str, UARTLITE_BASE + UARTLITE_TX_FIFO);
	}
#else
	ARG_UNUSED(str);
#endif
}

static void raw_uart_hex32(uint32_t value)
{
#if defined(CONFIG_EMACZ_APP_RAW_UART)
	for (int shift = 28; shift >= 0; shift -= 4) {
		uint8_t nibble = (value >> shift) & 0xfu;

		while ((sys_read32(UARTLITE_BASE + UARTLITE_STATUS) & UARTLITE_STATUS_TX_FULL) != 0u) {
		}
		sys_write32(nibble < 10u ? '0' + nibble : 'A' + nibble - 10u,
			    UARTLITE_BASE + UARTLITE_TX_FIFO);
	}
#else
	ARG_UNUSED(value);
#endif
}

#if defined(CONFIG_NET_ZPERF) || defined(CONFIG_ETH_EMACZERO_PROFILE)
static void raw_uart_hex64(uint64_t value)
{
	raw_uart_hex32((uint32_t)(value >> 32));
	raw_uart_hex32((uint32_t)value);
}
#endif

static void raw_uart_reg(const char *name, uint32_t reg)
{
	raw_uart_puts(name);
	raw_uart_puts("=0x");
	raw_uart_hex32(sys_read32(EMACZERO_BASE + reg));
	raw_uart_puts("\r\n");
}

#if defined(CONFIG_ETH_EMACZERO_PROFILE)
static uint8_t tx_bench_payload[TX_BENCH_MAX_PAYLOAD];
static uint8_t tx_bench_frame[TX_BENCH_FRAME_MAX];
static uint16_t tx_bench_ip_id;

static uint64_t u64_delta(uint64_t now, uint64_t before)
{
	return now >= before ? now - before : 0u;
}

static uint32_t u32_delta(uint32_t now, uint32_t before)
{
	return now >= before ? now - before : 0u;
}

static uint64_t u64_avg(uint64_t total, uint64_t count)
{
	return count == 0u ? 0u : total / count;
}

static void raw_uart_kv64(const char *name, uint64_t value)
{
	raw_uart_puts(name);
	raw_uart_puts("=0x");
	raw_uart_hex64(value);
	raw_uart_puts(" ");
}

static void raw_uart_kv32(const char *name, uint32_t value)
{
	raw_uart_puts(name);
	raw_uart_puts("=0x");
	raw_uart_hex32(value);
	raw_uart_puts(" ");
}

static size_t format_profile_snapshot(char *buf, size_t len)
{
	struct emaczero_profile_snapshot s;

	emaczero_profile_snapshot(&s);
	return (size_t)snprintk(buf, len,
				"mode=%u hz=%u mac_rx=%u mac_bytes=%u "
				"dma=%llu work=%llu zc=%llu copy=%llu "
				"drop_dma=%llu drop_pkt=%llu fail=%llu nofree=%llu "
				"dma_cyc=%llu build_cyc=%llu net_cyc=%llu "
				"life_cyc=%llu life_n=%llu max_inflight=%u "
				"max_stack=%u min_free=%u\r\n",
				s.mode, s.cycles_per_sec,
				sys_read32(EMACZERO_BASE + EMZ_REG_RX_FRAME_CNT),
				sys_read32(EMACZERO_BASE + EMZ_REG_RX_BYTE_CNT),
				s.dma_callbacks, s.rx_worker_packets,
				s.rx_zero_copy_submit, s.rx_copy_submit,
				s.dma_drop_after_dma, s.rx_drop_after_pkt,
				s.rx_net_recv_fail, s.rx_refill_no_free,
				s.dma_cb_cycles_total, s.rx_build_cycles_total,
				s.net_recv_cycles_total, s.buffer_lifetime_cycles_total,
				s.buffer_lifetime_samples, s.rx_max_dma_inflight,
				s.rx_max_stack_owned,
				s.rx_min_free == UINT32_MAX ? 0u : s.rx_min_free);
}

static size_t format_acceptance_snapshot(char *buf, size_t len)
{
	uint64_t alloc_fail = emaczero_perf_stats.rx_alloc_pkt_fail +
			      emaczero_perf_stats.rx_alloc_frag_fail +
			      emaczero_perf_stats.rx_alloc_pkt_zc_fail +
			      emaczero_perf_stats.rx_alloc_pkt_copy_fail;

	return (size_t)snprintk(
		buf, len,
		"magic=EZRX uptime=%u sink_p=%llu sink_b=%llu sink_err=%llu "
		"mac_rx=%u mac_err=%u gate_bad=%u gate_ovf=%u tready=%u "
		"dma=%llu dma_err=%llu bd_err=%u invalid=%llu alloc=%llu "
		"recv_fail=%llu nofree=%llu\r\n",
		emaczero_perf_stats.uptime_ms,
		emaczero_perf_stats.sink_packets, emaczero_perf_stats.sink_bytes,
		emaczero_perf_stats.sink_recv_errors,
		sys_read32(EMACZERO_BASE + EMZ_REG_RX_FRAME_CNT),
		sys_read32(EMACZERO_BASE + EMZ_REG_RX_ERR_CNT),
		sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DROPPED_BAD_FRAMES),
		sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DROPPED_OVERFLOW_FRAMES),
		sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DRAIN_TREADY_LOW_CYCLES),
		emaczero_perf_stats.dma_callbacks, emaczero_perf_stats.dma_errors,
		emaczero_perf_stats.rx_bd_errors, emaczero_perf_stats.rx_invalid,
		alloc_fail, emaczero_perf_stats.rx_net_recv_fail,
		emaczero_perf_stats.rx_refill_no_free);
}

static const char *parse_u32_arg(const char *cursor, uint32_t *value)
{
	char *end;
	unsigned long parsed;

	while (*cursor == ' ' || *cursor == '\t') {
		cursor++;
	}

	if (*cursor < '0' || *cursor > '9') {
		return NULL;
	}

	parsed = strtoul(cursor, &end, 0);
	if (end == cursor || parsed > UINT32_MAX) {
		return NULL;
	}

	*value = (uint32_t)parsed;
	return end;
}

static void put_be16(uint8_t *dst, uint16_t value)
{
	dst[0] = (uint8_t)(value >> 8);
	dst[1] = (uint8_t)value;
}

static uint16_t ipv4_header_checksum(const uint8_t *hdr)
{
	uint32_t sum = 0u;

	for (size_t i = 0u; i < 20u; i += 2u) {
		sum += ((uint16_t)hdr[i] << 8) | hdr[i + 1u];
	}
	while ((sum >> 16) != 0u) {
		sum = (sum & 0xffffu) + (sum >> 16);
	}
	return (uint16_t)~sum;
}

struct arp_lookup_ctx {
	const struct in_addr *ip;
	uint8_t mac[NET_ETH_ADDR_LEN];
	bool found;
};

static void arp_lookup_cb(struct arp_entry *entry, void *user_data)
{
	struct arp_lookup_ctx *ctx = user_data;

	if (!ctx->found && net_ipv4_addr_cmp(&entry->ip, ctx->ip)) {
		memcpy(ctx->mac, entry->eth.addr, sizeof(ctx->mac));
		ctx->found = true;
	}
}

static size_t build_tx_bench_frame(const struct sockaddr_in *peer, uint32_t payload_len,
				   uint32_t dst_port)
{
	struct net_if *iface = net_if_get_default();
	const struct net_linkaddr *link_addr = net_if_get_link_addr(iface);
	struct arp_lookup_ctx arp = {.ip = &peer->sin_addr};
	struct in_addr local_ip;
	uint8_t *ip = &tx_bench_frame[14];
	uint8_t *udp = &tx_bench_frame[14 + 20];
	const uint8_t *dst_ip = (const uint8_t *)&peer->sin_addr.s_addr;
	uint16_t ip_len = (uint16_t)(20u + 8u + payload_len);
	uint16_t udp_len = (uint16_t)(8u + payload_len);
	uint16_t checksum;

	(void)net_arp_foreach(arp_lookup_cb, &arp);
	if (!arp.found || link_addr == NULL || link_addr->len != NET_ETH_ADDR_LEN ||
	    !emacz_provision_get_ipv4(&local_ip)) {
		return 0u;
	}

	memcpy(&tx_bench_frame[0], arp.mac, sizeof(arp.mac));
	memcpy(&tx_bench_frame[6], link_addr->addr, NET_ETH_ADDR_LEN);
	put_be16(&tx_bench_frame[12], 0x0800u);

	ip[0] = 0x45u;
	ip[1] = 0x00u;
	put_be16(&ip[2], ip_len);
	put_be16(&ip[4], tx_bench_ip_id++);
	put_be16(&ip[6], 0x0000u);
	ip[8] = 64u;
	ip[9] = 17u;
	put_be16(&ip[10], 0u);
	memcpy(&ip[12], local_ip.s4_addr, NET_IPV4_ADDR_SIZE);
	memcpy(&ip[16], dst_ip, 4u);
	checksum = ipv4_header_checksum(ip);
	put_be16(&ip[10], checksum);

	put_be16(&udp[0], PROFILE_PORT);
	put_be16(&udp[2], (uint16_t)dst_port);
	put_be16(&udp[4], udp_len);
	put_be16(&udp[6], 0u);
	memcpy(&udp[8], tx_bench_payload, payload_len);

	return 14u + ip_len;
}

static size_t run_tx_bench(int sock, const struct sockaddr_in *peer,
			   const char *args, char *reply, size_t reply_len)
{
	struct sockaddr_in dst = *peer;
	uint32_t duration_ms = TX_BENCH_DEFAULT_DURATION_MS;
	uint32_t payload_len = TX_BENCH_DEFAULT_PAYLOAD;
	uint32_t rate_mbps_x1000 = 0u;
	uint32_t port = TX_BENCH_PORT;
	size_t frame_len;
	uint32_t start_cycle;
	uint32_t elapsed_cycles;
	uint32_t elapsed_ms;
	uint32_t cycles_per_sec = sys_clock_hw_cycles_per_sec();
	uint32_t delay_us = 0u;
	uint64_t packets = 0u;
	uint64_t bytes = 0u;
	uint64_t errors = 0u;
	int last_ret = 0;
	int last_errno = 0;
	const char *cursor = args;

	ARG_UNUSED(sock);

	if (cursor != NULL) {
		const char *next;

		next = parse_u32_arg(cursor, &duration_ms);
		if (next != NULL) {
			cursor = next;
			next = parse_u32_arg(cursor, &payload_len);
		}
		if (next != NULL) {
			cursor = next;
			next = parse_u32_arg(cursor, &rate_mbps_x1000);
		}
		if (next != NULL) {
			cursor = next;
			(void)parse_u32_arg(cursor, &port);
		}
	}

	if (duration_ms == 0u) {
		duration_ms = TX_BENCH_DEFAULT_DURATION_MS;
	}
	if (payload_len == 0u || payload_len > TX_BENCH_MAX_PAYLOAD) {
		payload_len = TX_BENCH_DEFAULT_PAYLOAD;
	}
	if (port == 0u || port > UINT16_MAX) {
		port = TX_BENCH_PORT;
	}
	if (rate_mbps_x1000 != 0u) {
		uint64_t bits_per_packet = (uint64_t)payload_len * 8u;
		uint64_t bits_per_sec = (uint64_t)rate_mbps_x1000 * 1000u;

		delay_us = (uint32_t)((bits_per_packet * 1000000u) / bits_per_sec);
		if (delay_us == 0u) {
			delay_us = 1u;
		}
	}

	dst.sin_port = htons((uint16_t)port);
	frame_len = build_tx_bench_frame(&dst, payload_len, port);
	if (frame_len == 0u) {
		return (size_t)snprintk(reply, reply_len, "tx error=no_peer_arp\r\n");
	}

	start_cycle = k_cycle_get_32();
	while ((uint32_t)(k_cycle_get_32() - start_cycle) <
	       (uint32_t)(((uint64_t)duration_ms * cycles_per_sec) / 1000u)) {
		int ret = emaczero_profile_send_raw_frame_burst(tx_bench_frame, frame_len,
								TX_BENCH_BURST_COUNT);

		last_ret = ret;
		if (ret > 0) {
			packets += (uint32_t)ret;
			bytes += (uint64_t)(uint32_t)ret * payload_len;
		} else {
			errors++;
			last_errno = errno;
		}

		if (delay_us != 0u && ret > 0) {
			k_busy_wait(delay_us * (uint32_t)ret);
		}
	}

	elapsed_cycles = k_cycle_get_32() - start_cycle;
	elapsed_ms = (uint32_t)(((uint64_t)elapsed_cycles * 1000u) / cycles_per_sec);
	return (size_t)snprintk(reply, reply_len,
				"tx pkts=%llu bytes=%llu errors=%llu elapsed_ms=%u "
				"payload=%u rate_mbps_x1000=%u port=%u last_ret=%d "
				"errno=%d\r\n",
				packets, bytes, errors, elapsed_ms, payload_len,
				rate_mbps_x1000, port, last_ret, last_errno);
}

static void dump_profile_delta(void)
{
	static struct emaczero_profile_snapshot prev;
	static uint64_t prev_irq;
	struct emaczero_profile_snapshot now;
	uint64_t dma_count;
	uint64_t worker_count;
	uint64_t net_recv_count;
	uint64_t lifetime_count;
	uint64_t irq_now;
	uint64_t irq_count;

	emaczero_profile_snapshot(&now);
	irq_now = emaczero_perf_stats.rx_irq_count;
	irq_count = u64_delta(irq_now, prev_irq);
	prev_irq = irq_now;
	dma_count = u64_delta(now.dma_callbacks, prev.dma_callbacks);
	worker_count = u64_delta(now.rx_worker_packets, prev.rx_worker_packets);
	net_recv_count = u64_delta(now.rx_zero_copy_submit + now.rx_copy_submit +
				   now.rx_net_recv_fail,
				   prev.rx_zero_copy_submit + prev.rx_copy_submit +
				   prev.rx_net_recv_fail);
	lifetime_count = u64_delta(now.buffer_lifetime_samples, prev.buffer_lifetime_samples);

	raw_uart_puts("PROF ");
	raw_uart_kv32("mode", now.mode);
	raw_uart_kv64("irq", irq_count);
	raw_uart_kv64("dma", dma_count);
	raw_uart_kv64("work", worker_count);
	raw_uart_kv64("zc", u64_delta(now.rx_zero_copy_submit, prev.rx_zero_copy_submit));
	raw_uart_kv64("copy", u64_delta(now.rx_copy_submit, prev.rx_copy_submit));
	raw_uart_kv64("drop_dma", u64_delta(now.dma_drop_after_dma, prev.dma_drop_after_dma));
	raw_uart_kv64("drop_pkt", u64_delta(now.rx_drop_after_pkt, prev.rx_drop_after_pkt));
	raw_uart_kv64("fail", u64_delta(now.rx_net_recv_fail, prev.rx_net_recv_fail));
	raw_uart_kv64("nofree", u64_delta(now.rx_refill_no_free, prev.rx_refill_no_free));
	raw_uart_puts("\r\n");

	raw_uart_puts("PROFcyc ");
	raw_uart_kv64("dma_avg", u64_avg(u64_delta(now.dma_cb_cycles_total,
						   prev.dma_cb_cycles_total),
					 dma_count));
	raw_uart_kv32("dma_max", u32_delta(now.dma_cb_cycles_max, 0));
	raw_uart_kv64("build_avg", u64_avg(u64_delta(now.rx_build_cycles_total,
						     prev.rx_build_cycles_total),
					   worker_count));
	raw_uart_kv32("build_max", u32_delta(now.rx_build_cycles_max, 0));
	raw_uart_kv64("net_avg", u64_avg(u64_delta(now.net_recv_cycles_total,
						   prev.net_recv_cycles_total),
					 net_recv_count));
	raw_uart_kv32("net_max", u32_delta(now.net_recv_cycles_max, 0));
	raw_uart_kv64("life_avg", u64_avg(u64_delta(now.buffer_lifetime_cycles_total,
						    prev.buffer_lifetime_cycles_total),
					  lifetime_count));
	raw_uart_kv32("life_max", u32_delta(now.buffer_lifetime_cycles_max, 0));
	raw_uart_kv32("max_inflight", now.rx_max_dma_inflight);
	raw_uart_kv32("max_stack", now.rx_max_stack_owned);
	raw_uart_kv32("min_free", now.rx_min_free == UINT32_MAX ? 0u : now.rx_min_free);
	raw_uart_kv32("hz", now.cycles_per_sec);
	raw_uart_puts("\r\n");

	prev = now;
}

K_THREAD_STACK_DEFINE(profile_thread_stack, PROFILE_THREAD_STACK_SIZE);
static struct k_thread profile_thread;

static void profile_control_thread(void *arg1, void *arg2, void *arg3)
{
	int sock;
	struct sockaddr_in addr = {
		.sin_family = AF_INET,
		.sin_port = htons(PROFILE_PORT),
		.sin_addr.s_addr = htonl(INADDR_ANY),
	};

	ARG_UNUSED(arg1);
	ARG_UNUSED(arg2);
	ARG_UNUSED(arg3);

	sock = zsock_socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	if (sock < 0) {
		raw_uart_puts("PROFILE socket failed\r\n");
		return;
	}

	if (zsock_bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		raw_uart_puts("PROFILE bind failed\r\n");
		(void)zsock_close(sock);
		return;
	}

	raw_uart_puts("PROFILE udp port 5002\r\n");
	while (true) {
		char request[96];
		char cmd;
		struct sockaddr_in peer;
		socklen_t peer_len = sizeof(peer);
		ssize_t got = zsock_recvfrom(sock, request, sizeof(request) - 1u, 0,
					     (struct sockaddr *)&peer, &peer_len);

		if (got <= 0) {
			continue;
		}

		request[got] = '\0';
		cmd = request[0];
		if (cmd >= '0' && cmd <= '2') {
			emaczero_profile_set_mode((enum emaczero_profile_mode)(cmd - '0'));
		} else if (cmd == 'r' || cmd == 'R') {
			emaczero_profile_reset();
		} else if (cmd == 's' || cmd == 'S') {
			char reply[512];
			size_t len = format_profile_snapshot(reply, sizeof(reply));
			ssize_t sent;

			sent = zsock_sendto(sock, reply, len, 0, (struct sockaddr *)&peer,
					    peer_len);
			raw_uart_puts("PROFILE send ret=0x");
			raw_uart_hex32((uint32_t)sent);
			raw_uart_puts(" errno=0x");
			raw_uart_hex32((uint32_t)errno);
			raw_uart_puts("\r\n");
			continue;
		} else if (cmd == 'a' || cmd == 'A') {
			char reply[384];
			size_t len = format_acceptance_snapshot(reply, sizeof(reply));

			(void)zsock_sendto(sock, reply, len, 0, (struct sockaddr *)&peer,
					   peer_len);
			continue;
		} else if (cmd == 't' || cmd == 'T') {
			char reply[160];
			size_t len = run_tx_bench(sock, &peer, &request[1], reply,
						  sizeof(reply));
			ssize_t sent = zsock_sendto(sock, reply, len, 0,
						    (struct sockaddr *)&peer,
						    peer_len);

			raw_uart_puts("PROFILE txbench reply ret=0x");
			raw_uart_hex32((uint32_t)sent);
			raw_uart_puts(" errno=0x");
			raw_uart_hex32((uint32_t)errno);
			raw_uart_puts("\r\n");
			continue;
		}
		cmd = (char)('0' + emaczero_profile_get_mode());
		raw_uart_puts("PROFILE cmd reply ret=0x");
		raw_uart_hex32((uint32_t)zsock_sendto(sock, &cmd, sizeof(cmd), 0,
						      (struct sockaddr *)&peer,
						      peer_len));
		raw_uart_puts(" errno=0x");
		raw_uart_hex32((uint32_t)errno);
		raw_uart_puts("\r\n");
	}
}

static void start_profile_control(void)
{
	k_thread_create(&profile_thread, profile_thread_stack,
			K_THREAD_STACK_SIZEOF(profile_thread_stack), profile_control_thread,
			NULL, NULL, NULL, PROFILE_THREAD_PRIORITY, 0, K_NO_WAIT);
	k_thread_name_set(&profile_thread, "emacz_prof_ctl");
}
#else
static void start_profile_control(void)
{
}
#endif

#if defined(CONFIG_NET_ZPERF)
static void zperf_status_cb(enum zperf_status status, struct zperf_results *result,
			    void *user_data)
{
	ARG_UNUSED(user_data);

	if (status == ZPERF_SESSION_STARTED) {
		raw_uart_puts("ZPERF started\r\n");
		return;
	}

	if (status == ZPERF_SESSION_ERROR) {
		raw_uart_puts("ZPERF error\r\n");
		return;
	}

	if (status != ZPERF_SESSION_FINISHED || result == NULL) {
		return;
	}

	raw_uart_puts("ZPERF done rx_pkts=0x");
	raw_uart_hex32(result->nb_packets_rcvd);
	raw_uart_puts(" lost=0x");
	raw_uart_hex32(result->nb_packets_lost);
	raw_uart_puts(" bytes=0x");
	raw_uart_hex64(result->total_len);
	raw_uart_puts(" usec=0x");
	raw_uart_hex64(result->time_in_us);
	raw_uart_puts("\r\n");
}

static void start_zperf_server(void)
{
	struct zperf_download_params params = {
		.port = ZPERF_PORT,
	};
	struct sockaddr_in *addr = (struct sockaddr_in *)&params.addr;
	int ret;

	addr->sin_family = AF_INET;
	addr->sin_port = htons(ZPERF_PORT);
	ret = zperf_udp_download(&params, zperf_status_cb, NULL);

	raw_uart_puts("MBV zperf udp port 5001 ret=0x");
	raw_uart_hex32((uint32_t)ret);
	raw_uart_puts("\r\n");
}
#else
K_THREAD_STACK_DEFINE(udp_sink_thread_stack, UDP_SINK_THREAD_STACK_SIZE);
static struct k_thread udp_sink_thread;
static uint8_t udp_sink_buf[UDP_SINK_BUFFER_SIZE];

static uint16_t read_be16(const uint8_t *data)
{
	return ((uint16_t)data[0] << 8) | data[1];
}

static bool udp_sink_intercept(const uint8_t *frame, size_t len, void *user_data)
{
	const uint8_t *mac = user_data;
	size_t ip_header_len;
	size_t udp_offset;
	uint16_t ip_total_len;
	uint16_t udp_len;
	uint32_t now;

	if (len < 42u || mac == NULL || read_be16(frame + 12u) != 0x0800u ||
	    (frame[14] >> 4) != 4u ||
	    (frame[14] & 0x0fu) < 5u || frame[23] != IPPROTO_UDP) {
		return false;
	}

	ip_header_len = (size_t)(frame[14] & 0x0fu) * 4u;
	ip_total_len = read_be16(frame + 16u);
	udp_offset = 14u + ip_header_len;
	if (ip_total_len < ip_header_len + 8u || 14u + ip_total_len > len ||
	    (read_be16(frame + 20u) & 0x3fffu) != 0u || udp_offset + 8u > len) {
		return false;
	}

	udp_len = read_be16(frame + udp_offset + 4u);
	if (udp_len < 8u || udp_len > ip_total_len - ip_header_len ||
	    udp_offset + udp_len > len) {
		return false;
	}
	if (read_be16(frame + udp_offset + 2u) == EMACZ_PROVISION_PORT &&
	    (memcmp(frame, "\xff\xff\xff\xff\xff\xff", 6u) == 0 ||
	     memcmp(frame, mac, 6u) == 0)) {
		return emacz_provision_ingress(frame + udp_offset + 8u, udp_len - 8u);
	}

	if (read_be16(frame + udp_offset + 2u) != UDP_SINK_PORT ||
	    memcmp(frame, mac, 6u) != 0) {
		return false;
	}

	now = k_cycle_get_32();
	if (emaczero_perf_stats.sink_packets == 0u) {
		emaczero_perf_stats.sink_first_cycle = now;
	}
	emaczero_perf_stats.sink_packets++;
	emaczero_perf_stats.sink_bytes += (uint64_t)(udp_len - 8u);
	emaczero_perf_stats.sink_last_len = (uint32_t)(udp_len - 8u);
	emaczero_perf_stats.sink_last_cycle = now;
	return true;
}

static void udp_sink_thread_fn(void *arg1, void *arg2, void *arg3)
{
	struct sockaddr_in addr = {
		.sin_family = AF_INET,
		.sin_port = htons(UDP_SINK_PORT),
		.sin_addr.s_addr = htonl(INADDR_ANY),
	};
	int sock;

	ARG_UNUSED(arg1);
	ARG_UNUSED(arg2);
	ARG_UNUSED(arg3);

	sock = zsock_socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	if (sock < 0) {
		emaczero_perf_stats.sink_recv_errors++;
		emaczero_perf_stats.sink_last_errno = (uint32_t)errno;
		return;
	}

	if (zsock_bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		emaczero_perf_stats.sink_recv_errors++;
		emaczero_perf_stats.sink_last_errno = (uint32_t)errno;
		(void)zsock_close(sock);
		return;
	}

	while (true) {
		uint32_t recv_start = k_cycle_get_32();
		ssize_t got = zsock_recvfrom(sock, udp_sink_buf, sizeof(udp_sink_buf), 0,
					     NULL, NULL);
		uint32_t recv_cycles = k_cycle_get_32() - recv_start;

		emaczero_perf_stats.sink_recvfrom_calls++;
		emaczero_perf_stats.sink_recvfrom_cycles_total += recv_cycles;
		if (recv_cycles > emaczero_perf_stats.sink_recvfrom_cycles_max) {
			emaczero_perf_stats.sink_recvfrom_cycles_max = recv_cycles;
		}

		if (got < 0) {
			uint32_t err = (uint32_t)errno;

			emaczero_perf_stats.sink_recv_errors++;
			emaczero_perf_stats.sink_last_errno = err;
			if (err == EAGAIN || err == EWOULDBLOCK) {
				emaczero_perf_stats.sink_eagain++;
			}
			continue;
		}

		if (emaczero_perf_stats.sink_packets == 0u) {
			emaczero_perf_stats.sink_first_cycle = k_cycle_get_32();
		}
		emaczero_perf_stats.sink_packets++;
		emaczero_perf_stats.sink_bytes += (uint64_t)got;
		emaczero_perf_stats.sink_last_len = (uint32_t)got;
		emaczero_perf_stats.sink_last_cycle = k_cycle_get_32();
	}
}

static void start_udp_sink(void)
{
	k_thread_create(&udp_sink_thread, udp_sink_thread_stack,
			K_THREAD_STACK_SIZEOF(udp_sink_thread_stack), udp_sink_thread_fn,
			NULL, NULL, NULL, UDP_SINK_THREAD_PRIORITY, 0, K_NO_WAIT);
	k_thread_name_set(&udp_sink_thread, "udp_sink");
	raw_uart_puts("MBV udp sink port 5001\r\n");
}
#endif

static void init_perf_stats_metadata(void)
{
	memset((void *)&emaczero_perf_stats, 0, sizeof(emaczero_perf_stats));
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
	for (uint32_t i = 0u; i < sizeof(tx_bench_payload); i++) {
		tx_bench_payload[i] = (uint8_t)(i ^ 0xa5u);
	}
#endif
	emaczero_perf_stats.magic = EMACZERO_PERF_STATS_MAGIC;
	emaczero_perf_stats.version = EMACZERO_PERF_STATS_VERSION;
	emaczero_perf_stats.cycles_per_sec = sys_clock_hw_cycles_per_sec();
#if defined(CONFIG_ETH_EMACZERO_R7_INSTRUMENTATION)
	/* r7 sol instrumentation magic + hz — set here after the memset so the
	 * driver-side accumulators (which fire once packet flow starts) land in a
	 * region the host tool can locate by scanning for the "PRF2" magic.
	 */
	emaczero_perf_stats.r7_magic = 0x50524632u;
	emaczero_perf_stats.r7_hz = sys_clock_hw_cycles_per_sec();
#endif
	emaczero_perf_stats.rx_pool_size = CONFIG_ETH_EMACZERO_RX_BUFFER_COUNT;
	emaczero_perf_stats.rx_min_free = UINT32_MAX;
	// Four-point-trace sentinels — host tooling scans for these so the byte
	// offset of the surrounding rx_ext_* / tx_ext_* fields doesn't have to
	// be known. Written here (in main) so init order doesn't zero them.
	emaczero_perf_stats.rx_ext_magic = 0x52584542u; /* "RXEB" */
	emaczero_perf_stats.tx_ext_magic = 0x54584542u; /* "TXEB" */
}

int main(void)
{
	struct net_if *iface;
	uint32_t count = 0;
	uint32_t start_cycle;
	uint32_t last_cycle;
	int64_t last_uptime;

	/* bard0 vex bring-up: writable boot progress marker in .bss (read via
	 * JTAG-AXI at the emacz_boot_marker symbol address).
	 */
	emacz_boot_marker = 0xB0071111u;

	init_perf_stats_metadata();
	emacz_boot_marker = 0xB0072222u;
	start_cycle = k_cycle_get_32();
	emacz_boot_marker = 0xB0073333u;
	last_cycle = start_cycle;
	last_uptime = k_uptime_get();
	emacz_boot_marker = 0xB0074444u;
	emacz_scratch_heartbeat[0] = SCRATCH_MAGIC;
	sys_write32(UARTLITE_CONTROL_RST_RX | UARTLITE_CONTROL_RST_TX,
		    UARTLITE_BASE + UARTLITE_CONTROL);
	raw_uart_puts("MBV Zephyr emacZero main\r\n");

	raw_uart_reg("EMZ VER", EMZ_REG_VERSION);
	raw_uart_reg("EMZ CTRL", EMZ_REG_CTRL);
	raw_uart_reg("EMZ STAT", EMZ_REG_STATUS);
	raw_uart_reg("EMZ MACLO", EMZ_REG_MAC_LO);
	raw_uart_reg("EMZ MACHI", EMZ_REG_MAC_HI);

	iface = net_if_get_default();
	if (iface == NULL) {
		raw_uart_puts("MBV no default iface\r\n");
	} else {
		int ret;
		static uint8_t sink_mac[6];
		const struct net_linkaddr *link_addr;

		raw_uart_puts("MBV default iface ok\r\n");
		ret = emacz_provision_start(iface);
		raw_uart_puts("MBV provision start ret=0x");
		raw_uart_hex32((uint32_t)ret);
		raw_uart_puts("\r\n");
		raw_uart_puts("MBV iface up=0x");
		raw_uart_hex32(net_if_is_up(iface) ? 1u : 0u);
		raw_uart_puts(" admin=0x");
		raw_uart_hex32(net_if_is_admin_up(iface) ? 1u : 0u);
		raw_uart_puts(" carrier=0x");
		raw_uart_hex32(net_if_is_carrier_ok(iface) ? 1u : 0u);
		raw_uart_puts("\r\n");
#if defined(CONFIG_NET_ZPERF)
		start_zperf_server();
#else
		link_addr = net_if_get_link_addr(iface);
		if (link_addr != NULL && link_addr->len == sizeof(sink_mac)) {
			memcpy(sink_mac, link_addr->addr, sizeof(sink_mac));
			ret = emaczero_set_rx_interceptor(iface, udp_sink_intercept, sink_mac);
			raw_uart_puts("MBV UDP fast endpoint ret=0x");
			raw_uart_hex32((uint32_t)ret);
			raw_uart_puts("\r\n");
		}
		start_udp_sink();
#endif
		start_profile_control();
	}

	while (true) {
		uint32_t now_cycle;
		int64_t now_uptime;

		emacz_scratch_heartbeat[1] = count++;
		k_sleep(K_SECONDS(1));
		now_cycle = k_cycle_get_32();
		now_uptime = k_uptime_get();
		emaczero_perf_stats.uptime_ms = (uint32_t)now_uptime;
		emaczero_perf_stats.mac_rx_frames =
			sys_read32(EMACZERO_BASE + EMZ_REG_RX_FRAME_CNT);
		emaczero_perf_stats.mac_rx_bytes =
			sys_read32(EMACZERO_BASE + EMZ_REG_RX_BYTE_CNT);
		emaczero_perf_stats.mac_rx_err =
			sys_read32(EMACZERO_BASE + EMZ_REG_RX_ERR_CNT);
		emaczero_perf_stats.mac_rx_err_align =
			sys_read32(EMACZERO_BASE + EMZ_REG_RX_ERR_ALIGN);
		emaczero_perf_stats.mac_rx_err_overflow =
			sys_read32(EMACZERO_BASE + EMZ_REG_RX_ERR_OVERFLOW);
		emaczero_perf_stats.mac_rx_err_oversize =
			sys_read32(EMACZERO_BASE + EMZ_REG_RX_ERR_OVERSIZE);
		emaczero_perf_stats.mac_rx_bcast =
			sys_read32(EMACZERO_BASE + EMZ_REG_RX_BCAST);
		emaczero_perf_stats.mac_rx_mcast =
			sys_read32(EMACZERO_BASE + EMZ_REG_RX_MCAST);
		emaczero_perf_stats.mac_rx_size_1024_1518 =
			sys_read32(EMACZERO_BASE + EMZ_REG_RX_SIZE_1024_1518);
		emaczero_perf_stats.gate_magic =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_MAGIC);
		emaczero_perf_stats.gate_good_frames =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_GOOD_FRAMES);
		emaczero_perf_stats.gate_dropped_bad_frames =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DROPPED_BAD_FRAMES);
		emaczero_perf_stats.gate_dropped_overflow_frames =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DROPPED_OVERFLOW_FRAMES);
		emaczero_perf_stats.gate_drain_samples =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DRAIN_SAMPLES);
		emaczero_perf_stats.gate_drain_cycles_total =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DRAIN_CYCLES_TOTAL);
		emaczero_perf_stats.gate_drain_cycles_max =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DRAIN_CYCLES_MAX);
		emaczero_perf_stats.gate_drain_lt_50us =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DRAIN_LT_50US);
		emaczero_perf_stats.gate_drain_50_100us =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DRAIN_50_100US);
		emaczero_perf_stats.gate_drain_100_200us =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DRAIN_100_200US);
		emaczero_perf_stats.gate_drain_200_500us =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DRAIN_200_500US);
		emaczero_perf_stats.gate_drain_ge_500us =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DRAIN_GE_500US);
		emaczero_perf_stats.gate_drain_tready_low_cycles =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DRAIN_TREADY_LOW_CYCLES);
		emaczero_perf_stats.gate_drain_tready_low_cycles_max =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DRAIN_TREADY_LOW_CYCLES_MAX);
		emaczero_perf_stats.gate_drain_tready_low_samples =
			sys_read32(EMACZERO_BASE + EMZ_REG_GATE_DRAIN_TREADY_LOW_SAMPLES);
#if defined(CONFIG_NET_STATISTICS)
		emaczero_perf_stats.net_ip_vhlerr = net_stats.ip_errors.vhlerr;
		emaczero_perf_stats.net_ip_hblenerr = net_stats.ip_errors.hblenerr;
		emaczero_perf_stats.net_ip_lblenerr = net_stats.ip_errors.lblenerr;
		emaczero_perf_stats.net_ip_fragerr = net_stats.ip_errors.fragerr;
		emaczero_perf_stats.net_ip_chkerr = net_stats.ip_errors.chkerr;
		emaczero_perf_stats.net_ip_protoerr = net_stats.ip_errors.protoerr;
#if defined(CONFIG_NET_STATISTICS_UDP)
		emaczero_perf_stats.net_udp_recv = net_stats.udp.recv;
		emaczero_perf_stats.net_udp_drop = net_stats.udp.drop;
		emaczero_perf_stats.net_udp_chkerr = net_stats.udp.chkerr;
#endif
#if defined(CONFIG_NET_STATISTICS_ICMP)
		emaczero_perf_stats.net_icmp_recv = net_stats.icmp.recv;
		emaczero_perf_stats.net_icmp_sent = net_stats.icmp.sent;
		emaczero_perf_stats.net_icmp_drop = net_stats.icmp.drop;
		emaczero_perf_stats.net_icmp_typeerr = net_stats.icmp.typeerr;
#endif
#if defined(CONFIG_NET_STATISTICS_IPV4)
		emaczero_perf_stats.net_ipv4_recv = net_stats.ipv4.recv;
		emaczero_perf_stats.net_ipv4_drop = net_stats.ipv4.drop;
#endif
		emaczero_perf_stats.net_processing_error = net_stats.processing_error;
#if defined(CONFIG_NET_STATISTICS_PKT_FILTER)
		emaczero_perf_stats.net_pkt_filter_rx_drop = net_stats.pkt_filter.rx.drop;
#if defined(CONFIG_NET_PKT_FILTER_IPV4_HOOK)
		emaczero_perf_stats.net_pkt_filter_rx_ipv4_drop =
			net_stats.pkt_filter.rx.ipv4_drop;
#endif
#if defined(CONFIG_NET_PKT_FILTER_LOCAL_IN_HOOK)
		emaczero_perf_stats.net_pkt_filter_rx_local_drop =
			net_stats.pkt_filter.rx.local_drop;
#endif
#endif
#endif
		if ((now_uptime - last_uptime) >= 1000) {
			emaczero_perf_stats.cycle_delta_1s = now_cycle - last_cycle;
			last_cycle = now_cycle;
			last_uptime = now_uptime;
		}
		if (now_uptime >= 30000) {
			emaczero_perf_stats.cycle_delta_30s = now_cycle - start_cycle;
		}
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
		raw_uart_puts("MBV emacZero alive ");
		raw_uart_hex32(count);
		raw_uart_puts("\r\n");
		raw_uart_reg("RXF", EMZ_REG_RX_FRAME_CNT);
		raw_uart_reg("RXB", EMZ_REG_RX_BYTE_CNT);
		dump_profile_delta();
#endif
	}
}
