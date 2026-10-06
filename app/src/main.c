/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 */

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include <zephyr/devicetree.h>
#include <zephyr/kernel.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_ip.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/net/net_stats.h>
#include <zephyr/net/socket.h>
#if defined(CONFIG_NET_ZPERF)
#include <zephyr/net/zperf.h>
#endif
#include <zephyr/sys/printk.h>
#include <zephyr/sys/sys_io.h>

#include "perf_stats.h"
#include "provision.h"

#define UARTLITE_BASE 0x40600000u
#define UARTLITE_TX_FIFO 0x04u
#define UARTLITE_STATUS 0x08u
#define UARTLITE_CONTROL 0x0cu
#define UARTLITE_STATUS_TX_FULL BIT(3)
#define UARTLITE_CONTROL_RST_RX BIT(1)
#define UARTLITE_CONTROL_RST_TX BIT(0)

#define SCRATCH_MAGIC 0x5a455048u

/* The MAC's statistics registers, read directly; the driver owns the rest */
#define EMACZERO_BASE DT_REG_ADDR(DT_NODELABEL(emaczero0))
#define EMZ_REG_VERSION 0x00u
#define EMZ_REG_CTRL 0x04u
#define EMZ_REG_STATUS 0x08u
#define EMZ_REG_MAC_LO 0x0cu
#define EMZ_REG_MAC_HI 0x10u
#define EMZ_REG_TX_FRAME_CNT 0x28u
#define EMZ_REG_TX_BYTE_CNT 0x2cu
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
#define CONTROL_PORT 5002u
#define CONTROL_THREAD_STACK_SIZE 2048u
#define CONTROL_THREAD_PRIORITY 4
#define TX_BENCH_PORT 5003u
#define TX_BENCH_MAX_PAYLOAD 1472u
#define TX_BENCH_DEFAULT_DURATION_MS 5000u
/* Keeps the 32-bit cycle window below its wrap at 100 MHz (~42.9 s). */
#define TX_BENCH_MAX_DURATION_MS 30000u
/* Slowest pacing: one packet per second. */
#define TX_BENCH_MAX_DELAY_US 1000000u
#define TX_BENCH_DEFAULT_PAYLOAD 1472u

volatile uint32_t emacz_scratch_heartbeat[2];
volatile uint32_t emacz_boot_marker;

static uint32_t emz_read(uint32_t reg)
{
	return sys_read32(EMACZERO_BASE + reg);
}

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
		uint32_t timeout = 1000000u;

		while ((sys_read32(UARTLITE_BASE + UARTLITE_STATUS) & UARTLITE_STATUS_TX_FULL) != 0u) {
			if (timeout-- == 0u) {
				return;
			}
		}
		sys_write32(nibble < 10u ? '0' + nibble : 'A' + nibble - 10u,
			    UARTLITE_BASE + UARTLITE_TX_FIFO);
	}
#else
	ARG_UNUSED(value);
#endif
}

#if defined(CONFIG_NET_ZPERF)
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
	raw_uart_hex32(emz_read(reg));
	raw_uart_puts("\r\n");
}

static void read_net_stats(struct net_stats *stats, struct net_stats_eth *eth)
{
	memset(stats, 0, sizeof(*stats));
	memset(eth, 0, sizeof(*eth));
	(void)net_mgmt(NET_REQUEST_STATS_GET_ALL, NULL, stats, sizeof(*stats));
	(void)net_mgmt(NET_REQUEST_STATS_GET_ETHERNET, net_if_get_default(), eth, sizeof(*eth));
}

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

/*
 * The sink thread is the only writer of the sink_* block. It brackets every
 * update with sink_seq so that readers (the control thread, the JTAG host)
 * can tell a copy that straddled one.
 */
static inline void sink_stats_begin(void)
{
	emacz_perf.sink_seq++;
	compiler_barrier();
}

static inline void sink_stats_end(void)
{
	compiler_barrier();
	emacz_perf.sink_seq++;
}

static void sink_account_packet(uint32_t payload_len)
{
	uint32_t now = k_cycle_get_32();

	sink_stats_begin();
	if (emacz_perf.sink_packets == 0u) {
		emacz_perf.sink_first_cycle = now;
	}
	emacz_perf.sink_packets++;
	emacz_perf.sink_bytes += (uint64_t)payload_len;
	emacz_perf.sink_last_len = payload_len;
	emacz_perf.sink_last_cycle = now;
	sink_stats_end();
}

static void sink_account_error(uint32_t err)
{
	sink_stats_begin();
	emacz_perf.sink_recv_errors++;
	emacz_perf.sink_last_errno = err;
	if (err == EAGAIN || err == EWOULDBLOCK) {
		emacz_perf.sink_eagain++;
	}
	sink_stats_end();
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
		sink_account_error((uint32_t)errno);
		return;
	}

	if (zsock_bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		sink_account_error((uint32_t)errno);
		(void)zsock_close(sock);
		return;
	}

	while (true) {
		uint32_t recv_start = k_cycle_get_32();
		ssize_t got = zsock_recvfrom(sock, udp_sink_buf, sizeof(udp_sink_buf), 0,
					     NULL, NULL);
		uint32_t recv_cycles = k_cycle_get_32() - recv_start;

		sink_stats_begin();
		emacz_perf.sink_recvfrom_calls++;
		emacz_perf.sink_recvfrom_cycles_total += recv_cycles;
		if (recv_cycles > emacz_perf.sink_recvfrom_cycles_max) {
			emacz_perf.sink_recvfrom_cycles_max = recv_cycles;
		}
		sink_stats_end();

		if (got < 0) {
			sink_account_error((uint32_t)errno);
			continue;
		}
		sink_account_packet((uint32_t)got);
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

/* Consistent copy of the sink counters the control replies use */
struct sink_snapshot {
	uint64_t packets;
	uint64_t bytes;
	uint64_t errors;
};

static void read_sink(struct sink_snapshot *out)
{
	uint32_t seq;

	do {
		seq = emacz_perf.sink_seq;
		compiler_barrier();
		out->packets = emacz_perf.sink_packets;
		out->bytes = emacz_perf.sink_bytes;
		out->errors = emacz_perf.sink_recv_errors;
		compiler_barrier();
	} while ((seq & 1u) != 0u || seq != emacz_perf.sink_seq);
}

static size_t format_status(char *buf, size_t len)
{
	struct sink_snapshot sink;

	read_sink(&sink);
	return (size_t)snprintk(buf, len,
				"hz=%u uptime=%u mac_rx=%u mac_rx_bytes=%u mac_tx=%u "
				"mac_tx_bytes=%u sink_p=%llu\r\n",
				sys_clock_hw_cycles_per_sec(), (uint32_t)k_uptime_get(),
				emz_read(EMZ_REG_RX_FRAME_CNT), emz_read(EMZ_REG_RX_BYTE_CNT),
				emz_read(EMZ_REG_TX_FRAME_CNT), emz_read(EMZ_REG_TX_BYTE_CNT),
				sink.packets);
}

/*
 * Acceptance snapshot for scripts/run_arty_stress.py. sink_err through
 * dma_err are error counters that must not move during a clean run;
 * ip_drop and udp_drop also count the host's unrelated broadcast traffic.
 */
static size_t format_acceptance(char *buf, size_t len)
{
	struct sink_snapshot sink;
	struct net_stats stats;
	struct net_stats_eth eth;

	read_net_stats(&stats, &eth);
	read_sink(&sink);
	return (size_t)snprintk(
		buf, len,
		"magic=EZRX uptime=%u mac_rx=%u sink_p=%llu sink_b=%llu sink_err=%llu "
		"mac_err=%u gate_bad=%u gate_ovf=%u tready=%u eth_err=%u dma_err=%u "
		"ip_drop=%u udp_drop=%u\r\n",
		(uint32_t)k_uptime_get(), emz_read(EMZ_REG_RX_FRAME_CNT), sink.packets,
		sink.bytes, sink.errors, emz_read(EMZ_REG_RX_ERR_CNT),
		emz_read(EMZ_REG_GATE_DROPPED_BAD_FRAMES),
		emz_read(EMZ_REG_GATE_DROPPED_OVERFLOW_FRAMES),
		emz_read(EMZ_REG_GATE_DRAIN_TREADY_LOW_CYCLES), (uint32_t)eth.errors.rx,
		(uint32_t)(eth.error_details.rx_dma_failed + eth.error_details.tx_dma_failed),
		(uint32_t)stats.ipv4.drop, (uint32_t)stats.udp.drop);
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

static uint8_t tx_bench_payload[TX_BENCH_MAX_PAYLOAD];

/*
 * "t [duration_ms [payload [rate_mbps_x1000 [port]]]]": send UDP datagrams
 * from the control socket to the requester for duration_ms, through the
 * network stack and the driver like any application traffic.
 */
static size_t run_tx_bench(int sock, const struct sockaddr_in *peer, const char *args,
			   char *reply, size_t reply_len)
{
	struct sockaddr_in dst = *peer;
	uint32_t duration_ms = TX_BENCH_DEFAULT_DURATION_MS;
	uint32_t payload_len = TX_BENCH_DEFAULT_PAYLOAD;
	uint32_t rate_mbps_x1000 = 0u;
	uint32_t port = TX_BENCH_PORT;
	uint32_t cycles_per_sec = sys_clock_hw_cycles_per_sec();
	uint32_t delay_us = 0u;
	uint32_t start_cycle;
	uint32_t duration_cycles;
	uint32_t elapsed_cycles;
	uint64_t packets = 0u;
	uint64_t bytes = 0u;
	uint64_t errors = 0u;
	int last_ret = 0;
	int last_errno = 0;
	const char *next = parse_u32_arg(args, &duration_ms);

	if (next != NULL) {
		next = parse_u32_arg(next, &payload_len);
	}
	if (next != NULL) {
		next = parse_u32_arg(next, &rate_mbps_x1000);
	}
	if (next != NULL) {
		(void)parse_u32_arg(next, &port);
	}

	if (duration_ms == 0u) {
		duration_ms = TX_BENCH_DEFAULT_DURATION_MS;
	} else if (duration_ms > TX_BENCH_MAX_DURATION_MS) {
		duration_ms = TX_BENCH_MAX_DURATION_MS;
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
		uint64_t delay = (bits_per_packet * 1000000u) / bits_per_sec;

		delay_us = (uint32_t)CLAMP(delay, 1u, (uint64_t)TX_BENCH_MAX_DELAY_US);
	}

	dst.sin_port = htons((uint16_t)port);
	duration_cycles = (uint32_t)(((uint64_t)duration_ms * cycles_per_sec) / 1000u);
	start_cycle = k_cycle_get_32();
	while ((uint32_t)(k_cycle_get_32() - start_cycle) < duration_cycles) {
		ssize_t ret = zsock_sendto(sock, tx_bench_payload, payload_len, 0,
					   (struct sockaddr *)&dst, sizeof(dst));

		last_ret = (int)ret;
		if (ret < 0) {
			errors++;
			last_errno = errno;
			/* out of packets: let the stack and driver drain */
			k_yield();
			continue;
		}
		packets++;
		bytes += (uint64_t)ret;
		if (delay_us != 0u) {
			k_busy_wait(delay_us);
		}
	}

	elapsed_cycles = k_cycle_get_32() - start_cycle;
	return (size_t)snprintk(reply, reply_len,
				"tx pkts=%llu bytes=%llu errors=%llu elapsed_ms=%u "
				"payload=%u rate_mbps_x1000=%u port=%u last_ret=%d "
				"errno=%d\r\n",
				packets, bytes, errors,
				(uint32_t)(((uint64_t)elapsed_cycles * 1000u) / cycles_per_sec),
				payload_len, rate_mbps_x1000, port, last_ret, last_errno);
}

K_THREAD_STACK_DEFINE(control_thread_stack, CONTROL_THREAD_STACK_SIZE);
static struct k_thread control_thread;

/*
 * UDP control port: 's' status line, 'a' acceptance snapshot, 't' TX
 * benchmark. Anything else gets "?" back, which still proves the board
 * answers.
 */
static void control_thread_fn(void *arg1, void *arg2, void *arg3)
{
	struct sockaddr_in addr = {
		.sin_family = AF_INET,
		.sin_port = htons(CONTROL_PORT),
		.sin_addr.s_addr = htonl(INADDR_ANY),
	};
	int sock;

	ARG_UNUSED(arg1);
	ARG_UNUSED(arg2);
	ARG_UNUSED(arg3);

	sock = zsock_socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	if (sock < 0) {
		raw_uart_puts("CONTROL socket failed\r\n");
		return;
	}

	if (zsock_bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		raw_uart_puts("CONTROL bind failed\r\n");
		(void)zsock_close(sock);
		return;
	}

	raw_uart_puts("CONTROL udp port 5002\r\n");
	while (true) {
		char request[96];
		char reply[256];
		size_t len;
		struct sockaddr_in peer;
		socklen_t peer_len = sizeof(peer);
		ssize_t got = zsock_recvfrom(sock, request, sizeof(request) - 1u, 0,
					     (struct sockaddr *)&peer, &peer_len);

		if (got <= 0 || peer.sin_family != AF_INET) {
			continue;
		}

		request[got] = '\0';
		switch (request[0]) {
		case 's':
		case 'S':
			len = format_status(reply, sizeof(reply));
			break;
		case 'a':
		case 'A':
			len = format_acceptance(reply, sizeof(reply));
			break;
		case 't':
		case 'T':
			len = run_tx_bench(sock, &peer, &request[1], reply, sizeof(reply));
			break;
		default:
			len = (size_t)snprintk(reply, sizeof(reply), "?");
			break;
		}
		(void)zsock_sendto(sock, reply, len, 0, (struct sockaddr *)&peer, peer_len);
	}
}

static void start_control(void)
{
	k_thread_create(&control_thread, control_thread_stack,
			K_THREAD_STACK_SIZEOF(control_thread_stack), control_thread_fn, NULL,
			NULL, NULL, CONTROL_THREAD_PRIORITY, 0, K_NO_WAIT);
	k_thread_name_set(&control_thread, "emacz_control");
}

static void init_perf_stats(void)
{
	memset((void *)&emacz_perf, 0, sizeof(emacz_perf));
	for (uint32_t i = 0u; i < sizeof(tx_bench_payload); i++) {
		tx_bench_payload[i] = (uint8_t)(i ^ 0xa5u);
	}
	emacz_perf.magic = EMACZ_PERF_STATS_MAGIC;
	emacz_perf.version = EMACZ_PERF_STATS_VERSION;
	emacz_perf.cycles_per_sec = sys_clock_hw_cycles_per_sec();
	emacz_perf.rx_buffer_count = CONFIG_ETH_EMACZERO_RX_BUFFER_COUNT;
}

static void update_perf_stats(void)
{
	struct net_stats stats;
	struct net_stats_eth eth;

	emacz_perf.mac_rx_frames = emz_read(EMZ_REG_RX_FRAME_CNT);
	emacz_perf.mac_rx_bytes = emz_read(EMZ_REG_RX_BYTE_CNT);
	emacz_perf.mac_rx_err = emz_read(EMZ_REG_RX_ERR_CNT);
	emacz_perf.mac_rx_err_align = emz_read(EMZ_REG_RX_ERR_ALIGN);
	emacz_perf.mac_rx_err_overflow = emz_read(EMZ_REG_RX_ERR_OVERFLOW);
	emacz_perf.mac_rx_err_oversize = emz_read(EMZ_REG_RX_ERR_OVERSIZE);
	emacz_perf.mac_rx_bcast = emz_read(EMZ_REG_RX_BCAST);
	emacz_perf.mac_rx_mcast = emz_read(EMZ_REG_RX_MCAST);
	emacz_perf.mac_rx_size_1024_1518 = emz_read(EMZ_REG_RX_SIZE_1024_1518);
	emacz_perf.mac_tx_frames = emz_read(EMZ_REG_TX_FRAME_CNT);
	emacz_perf.mac_tx_bytes = emz_read(EMZ_REG_TX_BYTE_CNT);
	emacz_perf.gate_magic = emz_read(EMZ_REG_GATE_MAGIC);
	emacz_perf.gate_good_frames = emz_read(EMZ_REG_GATE_GOOD_FRAMES);
	emacz_perf.gate_dropped_bad_frames = emz_read(EMZ_REG_GATE_DROPPED_BAD_FRAMES);
	emacz_perf.gate_dropped_overflow_frames = emz_read(EMZ_REG_GATE_DROPPED_OVERFLOW_FRAMES);
	emacz_perf.gate_drain_samples = emz_read(EMZ_REG_GATE_DRAIN_SAMPLES);
	emacz_perf.gate_drain_cycles_total = emz_read(EMZ_REG_GATE_DRAIN_CYCLES_TOTAL);
	emacz_perf.gate_drain_cycles_max = emz_read(EMZ_REG_GATE_DRAIN_CYCLES_MAX);
	emacz_perf.gate_drain_lt_50us = emz_read(EMZ_REG_GATE_DRAIN_LT_50US);
	emacz_perf.gate_drain_50_100us = emz_read(EMZ_REG_GATE_DRAIN_50_100US);
	emacz_perf.gate_drain_100_200us = emz_read(EMZ_REG_GATE_DRAIN_100_200US);
	emacz_perf.gate_drain_200_500us = emz_read(EMZ_REG_GATE_DRAIN_200_500US);
	emacz_perf.gate_drain_ge_500us = emz_read(EMZ_REG_GATE_DRAIN_GE_500US);
	emacz_perf.gate_drain_tready_low_cycles = emz_read(EMZ_REG_GATE_DRAIN_TREADY_LOW_CYCLES);
	emacz_perf.gate_drain_tready_low_cycles_max =
		emz_read(EMZ_REG_GATE_DRAIN_TREADY_LOW_CYCLES_MAX);
	emacz_perf.gate_drain_tready_low_samples = emz_read(EMZ_REG_GATE_DRAIN_TREADY_LOW_SAMPLES);

	read_net_stats(&stats, &eth);
	emacz_perf.eth_rx_errors = eth.errors.rx;
	emacz_perf.eth_rx_dma_failed = eth.error_details.rx_dma_failed;
	emacz_perf.eth_tx_dma_failed = eth.error_details.tx_dma_failed;
	emacz_perf.net_ipv4_recv = stats.ipv4.recv;
	emacz_perf.net_ipv4_drop = stats.ipv4.drop;
	emacz_perf.net_udp_recv = stats.udp.recv;
	emacz_perf.net_udp_drop = stats.udp.drop;
	emacz_perf.net_udp_chkerr = stats.udp.chkerr;
	emacz_perf.net_processing_error = stats.processing_error;
	emacz_perf.net_ip_vhlerr = stats.ip_errors.vhlerr;
	emacz_perf.net_ip_hblenerr = stats.ip_errors.hblenerr;
	emacz_perf.net_ip_lblenerr = stats.ip_errors.lblenerr;
	emacz_perf.net_ip_fragerr = stats.ip_errors.fragerr;
	emacz_perf.net_ip_chkerr = stats.ip_errors.chkerr;
	emacz_perf.net_ip_protoerr = stats.ip_errors.protoerr;
	emacz_perf.net_icmp_recv = stats.icmp.recv;
	emacz_perf.net_icmp_sent = stats.icmp.sent;
	emacz_perf.net_icmp_drop = stats.icmp.drop;
	emacz_perf.net_icmp_typeerr = stats.icmp.typeerr;
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

	init_perf_stats();
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
		start_udp_sink();
#endif
		start_control();
	}

	while (true) {
		uint32_t now_cycle;
		int64_t now_uptime;

		emacz_scratch_heartbeat[1] = count++;
		k_sleep(K_SECONDS(1));
		now_cycle = k_cycle_get_32();
		now_uptime = k_uptime_get();
		emacz_perf.uptime_ms = (uint32_t)now_uptime;
		update_perf_stats();
		if ((now_uptime - last_uptime) >= 1000) {
			emacz_perf.cycle_delta_1s = now_cycle - last_cycle;
			last_cycle = now_cycle;
			last_uptime = now_uptime;
		}
		if (now_uptime >= 30000) {
			emacz_perf.cycle_delta_30s = now_cycle - start_cycle;
		}
	}
}
