/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 */

#ifndef EMACZ_PERF_STATS_H_
#define EMACZ_PERF_STATS_H_

#include <stdint.h>

#include <zephyr/toolchain.h>

#include "hostio.h"

#define EMACZ_PERF_STATS_MAGIC 0x45505a53u
/* scripts/read_perf_stats.py mirrors this layout; bump both together. */
#define EMACZ_PERF_STATS_VERSION 20u

/*
 * Counters the app can see from outside the driver: the MAC's own registers,
 * the network stack's statistics and the UDP sink. Written by the app only.
 */
struct emacz_perf_stats {
	uint32_t magic;
	uint32_t version;
	uint32_t cycles_per_sec;
	uint32_t rx_buffer_count;
	uint32_t uptime_ms;
	uint32_t cycle_delta_1s;
	uint32_t cycle_delta_30s;
	uint32_t mac_rx_frames;
	uint32_t mac_rx_bytes;
	uint32_t mac_rx_err;
	uint32_t mac_rx_err_align;
	uint32_t mac_rx_err_overflow;
	uint32_t mac_rx_err_oversize;
	uint32_t mac_rx_bcast;
	uint32_t mac_rx_mcast;
	uint32_t mac_rx_size_1024_1518;
	uint32_t mac_tx_frames;
	uint32_t mac_tx_bytes;
	uint32_t gate_magic;
	uint32_t gate_good_frames;
	uint32_t gate_dropped_bad_frames;
	uint32_t gate_dropped_overflow_frames;
	uint32_t gate_drain_samples;
	uint32_t gate_drain_cycles_total;
	uint32_t gate_drain_cycles_max;
	uint32_t gate_drain_lt_50us;
	uint32_t gate_drain_50_100us;
	uint32_t gate_drain_100_200us;
	uint32_t gate_drain_200_500us;
	uint32_t gate_drain_ge_500us;
	uint32_t gate_drain_tready_low_cycles;
	uint32_t gate_drain_tready_low_cycles_max;
	uint32_t gate_drain_tready_low_samples;
	/* Ethernet errors.rx: frames the MAC rejected plus frames the driver dropped */
	uint32_t eth_rx_errors;
	/* AXI DMA errors that halted S2MM / MM2S; each one starts a recovery */
	uint32_t eth_rx_dma_failed;
	uint32_t eth_tx_dma_failed;
	uint32_t net_ipv4_recv;
	uint32_t net_ipv4_drop;
	uint32_t net_udp_recv;
	uint32_t net_udp_drop;
	uint32_t net_udp_chkerr;
	uint32_t net_processing_error;
	uint32_t net_ip_vhlerr;
	uint32_t net_ip_hblenerr;
	uint32_t net_ip_lblenerr;
	uint32_t net_ip_fragerr;
	uint32_t net_ip_chkerr;
	uint32_t net_ip_protoerr;
	uint32_t net_icmp_recv;
	uint32_t net_icmp_sent;
	uint32_t net_icmp_drop;
	uint32_t net_icmp_typeerr;
	/*
	 * Seqlock over the sink_* block below: odd while the sink thread is
	 * mid-update. Readers that see it odd, or changed across their read,
	 * retry. 64-bit counters are two stores on RV32, so a read without it
	 * can be torn.
	 */
	uint32_t sink_seq;
	uint64_t sink_packets;
	uint64_t sink_bytes;
	uint64_t sink_recv_errors;
	uint64_t sink_eagain;
	uint64_t sink_recvfrom_calls;
	uint64_t sink_recvfrom_cycles_total;
	uint32_t sink_recvfrom_cycles_max;
	uint32_t sink_last_errno;
	uint32_t sink_first_cycle;
	uint32_t sink_last_cycle;
	uint32_t sink_last_len;
};

BUILD_ASSERT(sizeof(struct emacz_perf_stats) <= EMACZ_HOSTIO_SLOT_SIZE,
	     "perf stats must fit their slot of emz_hostio");

/* The live block; the name differs from the struct tag so both stay usable */
#define emacz_perf (*(volatile struct emacz_perf_stats *)EMACZ_PERF_STATS_ADDR)

#endif /* EMACZ_PERF_STATS_H_ */
