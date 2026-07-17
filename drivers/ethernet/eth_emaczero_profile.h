/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 */

#ifndef ETH_EMACZERO_PROFILE_H
#define ETH_EMACZERO_PROFILE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#define EMACZERO_PERF_STATS_MAGIC 0x45505a53u
#define EMACZERO_PERF_STATS_VERSION 17u
#define EMACZERO_PERF_STATS_DMA_RESERVED 0x1000u

struct emaczero_perf_stats {
	uint32_t magic;
	uint32_t version;
	uint32_t cycles_per_sec;
	uint32_t rx_pool_size;
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
	uint32_t _reserved_v12;
	uint64_t dma_callbacks;
	uint64_t dma_errors;
	uint32_t dma_callback_gap_cycles_max;
	uint32_t dma_callback_gap_ge_1ms;
	uint32_t rx_refill_cycles_max;
	uint32_t rx_refill_cycles_ge_1ms;
	uint32_t rx_refill_queued_max;
	uint32_t _reserved_v10;
	uint64_t rx_bd_hw_completed;
	uint64_t rx_bd_refilled;
	uint64_t rx_bd_tail_updates;
	uint64_t rx_bd_no_free;
	uint64_t rx_irq_count;
	uint32_t rx_bd_available_current;
	uint32_t rx_bd_available_min;
	uint32_t rx_poll_completed_max;
	uint32_t rx_bd_errors;
	uint32_t _reserved_v11;
	uint64_t rx_worker_packets;
	uint64_t rx_invalid;
	uint64_t rx_alloc_pkt_fail;
	uint64_t rx_alloc_frag_fail;
	uint64_t rx_alloc_pkt_zc_fail;
	uint64_t rx_alloc_pkt_copy_fail;
	uint64_t rx_copy_write_fail;
	uint64_t rx_zero_copy_submit;
	uint64_t rx_copy_submit;
	uint64_t rx_net_recv_fail;
	uint64_t rx_released;
	uint64_t rx_refill_calls;
	uint64_t rx_refill_queued;
	uint64_t rx_refill_no_free;
	uint64_t rx_dma_config_calls;
	uint64_t rx_dma_reload_calls;
	uint64_t rx_dma_start_calls;
	uint64_t rx_dma_config_fail;
	uint64_t rx_dma_reload_fail;
	uint64_t rx_dma_start_fail;
	uint32_t rx_pool_inflight_current;
	uint32_t rx_pool_inflight_high;
	uint32_t rx_free_current;
	uint32_t rx_dma_fifo_current;
	uint32_t rx_ready_fifo_current;
	uint32_t rx_worker_current;
	uint32_t rx_stack_owned_current;
	uint32_t rx_owner_sum_current;
	uint32_t rx_owner_sum_bad;
	uint32_t rx_max_dma_inflight;
	uint32_t rx_max_stack_owned;
	uint32_t rx_min_free;
	uint64_t rx_dwell_samples;
	uint64_t rx_dwell_cycles_total;
	uint32_t rx_dwell_cycles_max;
	uint32_t rx_dwell_lt_1ms;
	uint32_t rx_dwell_1_5ms;
	uint32_t rx_dwell_5_20ms;
	uint32_t rx_dwell_20_100ms;
	uint32_t rx_dwell_ge_100ms;
	uint32_t net_udp_recv;
	uint32_t net_udp_drop;
	uint32_t net_ipv4_recv;
	uint32_t net_ipv4_drop;
	uint32_t net_processing_error;
	uint32_t net_pkt_filter_rx_drop;
	uint32_t net_pkt_filter_rx_ipv4_drop;
	uint32_t net_pkt_filter_rx_local_drop;
	uint32_t _reserved_v13;
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
	uint32_t net_ip_vhlerr;
	uint32_t net_ip_hblenerr;
	uint32_t net_ip_lblenerr;
	uint32_t net_ip_fragerr;
	uint32_t net_ip_chkerr;
	uint32_t net_ip_protoerr;
	uint32_t net_udp_chkerr;
	uint32_t net_icmp_recv;
	uint32_t net_icmp_sent;
	uint32_t net_icmp_drop;
	uint32_t net_icmp_typeerr;
	uint32_t rx_last_icmp_src;
	uint32_t rx_last_icmp_dst;
	uint32_t rx_last_icmp_id;
	uint32_t rx_last_icmp_seq;
	uint32_t rx_pre_dst_me;
	uint32_t rx_pre_dst_broadcast;
	uint32_t rx_pre_dst_multicast;
	uint32_t rx_pre_dst_other;
	uint32_t rx_pre_type_ipv4;
	uint32_t rx_pre_type_arp;
	uint32_t rx_pre_type_other;
	uint32_t rx_pre_ipv4_bad;
	uint32_t rx_pre_ipv4_udp;
	uint32_t rx_pre_udp_bad_len;
	uint32_t rx_pre_udp_port_5001;
	uint32_t rx_last_sample_len;
	uint32_t rx_last_sample_status;
	uint32_t rx_last_sample_word0;
	uint32_t rx_last_sample_word1;
	uint32_t rx_last_sample_word2;
	uint32_t rx_last_sample_word3;
	uint32_t rx_last_sample_word4;
	uint32_t rx_last_sample_word5;
	uint32_t rx_last_sample_word6;
	uint32_t rx_last_sample_word7;
	uint32_t rx_bad_sample_seen;
	uint32_t rx_bad_sample_len;
	uint32_t rx_bad_sample_status;
	uint32_t rx_bad_sample_word0;
	uint32_t rx_bad_sample_word1;
	uint32_t rx_bad_sample_word2;
	uint32_t rx_bad_sample_word3;
	uint32_t rx_good_sample_seen;
	uint32_t rx_good_sample_len;
	uint32_t rx_good_sample_word0;
	uint32_t rx_good_sample_word1;
	uint32_t rx_good_sample_word2;
	uint32_t rx_good_sample_word3;
	uint64_t tx_send_calls;
	uint64_t tx_send_read_fail;
	uint64_t tx_setup_calls;
	uint64_t tx_setup_no_dma;
	uint64_t tx_setup_busy;
	uint64_t tx_dma_config_fail;
	uint64_t tx_dma_reload_fail;
	uint64_t tx_dma_start_fail;
	uint64_t tx_dma_start_ok;
	uint64_t tx_dma_completed;
	uint64_t tx_dma_error;
	uint32_t tx_last_len;
	uint32_t tx_last_ret;
	uint32_t tx_last_word0;
	uint32_t tx_last_word1;
	uint32_t tx_last_word2;
	uint32_t tx_last_word3;
	uint32_t tx_last_icmp_src;
	uint32_t tx_last_icmp_dst;
	uint32_t tx_last_icmp_id;
	uint32_t tx_last_icmp_seq;
	// Extended 64-byte capture rings — appended at end so existing field
	// offsets are stable and no_commit/read_emac_csr.py stays valid.
	// Magic words 'RXEB' / 'TXEB' precede each block so the host tooling can
	// locate them by scanning the perf-stats region (no offsetof needed).
	// rx_ext_* captures the buffer the driver hands to net_recv_data().
	// tx_ext_* captures the buffer the driver hands to the MM2S DMA.
	// Both are first-64-bytes snapshots updated on every frame.
	uint32_t rx_ext_magic;  // = 0x52584542 ("RXEB")
	uint32_t rx_ext_len;
	uint32_t rx_ext_word0;
	uint32_t rx_ext_word1;
	uint32_t rx_ext_word2;
	uint32_t rx_ext_word3;
	uint32_t rx_ext_word4;
	uint32_t rx_ext_word5;
	uint32_t rx_ext_word6;
	uint32_t rx_ext_word7;
	uint32_t rx_ext_word8;
	uint32_t rx_ext_word9;
	uint32_t rx_ext_word10;
	uint32_t rx_ext_word11;
	uint32_t rx_ext_word12;
	uint32_t rx_ext_word13;
	uint32_t rx_ext_word14;
	uint32_t rx_ext_word15;
	uint32_t tx_ext_magic;  // = 0x54584542 ("TXEB")
	uint32_t tx_ext_len;
	uint32_t tx_ext_word0;
	uint32_t tx_ext_word1;
	uint32_t tx_ext_word2;
	uint32_t tx_ext_word3;
	uint32_t tx_ext_word4;
	uint32_t tx_ext_word5;
	uint32_t tx_ext_word6;
	uint32_t tx_ext_word7;
	uint32_t tx_ext_word8;
	uint32_t tx_ext_word9;
	uint32_t tx_ext_word10;
	uint32_t tx_ext_word11;
	uint32_t tx_ext_word12;
	uint32_t tx_ext_word13;
	uint32_t tx_ext_word14;
	uint32_t tx_ext_word15;
};

#if defined(CONFIG_ETH_EMACZERO_DMA_MEMORY_SIZE) && CONFIG_ETH_EMACZERO_DMA_MEMORY_SIZE != 0
#define EMACZERO_PERF_STATS_ADDR \
	(CONFIG_ETH_EMACZERO_DMA_MEMORY_BASE + CONFIG_ETH_EMACZERO_DMA_MEMORY_SIZE - \
	 EMACZERO_PERF_STATS_DMA_RESERVED)
#define emaczero_perf_stats (*(volatile struct emaczero_perf_stats *)EMACZERO_PERF_STATS_ADDR)
#else
extern volatile struct emaczero_perf_stats emaczero_perf_stats;
#endif

enum emaczero_profile_mode {
	EMACZERO_PROFILE_MODE_NORMAL = 0,
	EMACZERO_PROFILE_MODE_DROP_AFTER_DMA = 1,
	EMACZERO_PROFILE_MODE_DROP_AFTER_PKT = 2,
};

enum emaczero_profile_counter_id {
	EMACZERO_PROFILE_COUNTER_DMA_CALLBACKS,
	EMACZERO_PROFILE_COUNTER_DMA_ERRORS,
	EMACZERO_PROFILE_COUNTER_DMA_DROP_AFTER_DMA,
	EMACZERO_PROFILE_COUNTER_RX_WORKER_PACKETS,
	EMACZERO_PROFILE_COUNTER_RX_INVALID,
	EMACZERO_PROFILE_COUNTER_RX_ALLOC_PKT_FAIL,
	EMACZERO_PROFILE_COUNTER_RX_ALLOC_FRAG_FAIL,
	EMACZERO_PROFILE_COUNTER_RX_COPY_FALLBACK,
	EMACZERO_PROFILE_COUNTER_RX_ZERO_COPY_SUBMIT,
	EMACZERO_PROFILE_COUNTER_RX_COPY_SUBMIT,
	EMACZERO_PROFILE_COUNTER_RX_DROP_AFTER_PKT,
	EMACZERO_PROFILE_COUNTER_RX_NET_RECV_FAIL,
	EMACZERO_PROFILE_COUNTER_RX_REFILL_CALLS,
	EMACZERO_PROFILE_COUNTER_RX_REFILL_QUEUED,
	EMACZERO_PROFILE_COUNTER_RX_REFILL_NO_FREE,
};

enum emaczero_profile_cycle_id {
	EMACZERO_PROFILE_CYCLES_DMA_CB,
	EMACZERO_PROFILE_CYCLES_RX_BUILD,
	EMACZERO_PROFILE_CYCLES_NET_RECV,
};

enum emaczero_profile_max_id {
	EMACZERO_PROFILE_MAX_RX_DMA_INFLIGHT,
	EMACZERO_PROFILE_MAX_RX_STACK_OWNED,
};

enum emaczero_profile_min_id {
	EMACZERO_PROFILE_MIN_RX_FREE,
};

struct emaczero_profile_snapshot {
	uint32_t mode;
	uint32_t cycles_per_sec;
	uint64_t dma_callbacks;
	uint64_t dma_errors;
	uint64_t dma_drop_after_dma;
	uint64_t rx_worker_packets;
	uint64_t rx_invalid;
	uint64_t rx_alloc_pkt_fail;
	uint64_t rx_alloc_frag_fail;
	uint64_t rx_copy_fallback;
	uint64_t rx_zero_copy_submit;
	uint64_t rx_copy_submit;
	uint64_t rx_drop_after_pkt;
	uint64_t rx_net_recv_fail;
	uint64_t rx_released;
	uint64_t rx_refill_calls;
	uint64_t rx_refill_queued;
	uint64_t rx_refill_no_free;
	uint32_t rx_max_dma_inflight;
	uint32_t rx_max_stack_owned;
	uint32_t rx_min_free;
	uint64_t dma_cb_cycles_total;
	uint32_t dma_cb_cycles_max;
	uint64_t rx_build_cycles_total;
	uint32_t rx_build_cycles_max;
	uint64_t net_recv_cycles_total;
	uint32_t net_recv_cycles_max;
	uint64_t buffer_lifetime_cycles_total;
	uint32_t buffer_lifetime_cycles_max;
	uint64_t buffer_lifetime_samples;
};

#if defined(CONFIG_ETH_EMACZERO_PROFILE)
void emaczero_profile_snapshot(struct emaczero_profile_snapshot *snapshot);
void emaczero_profile_reset(void);
void emaczero_profile_set_mode(enum emaczero_profile_mode mode);
enum emaczero_profile_mode emaczero_profile_get_mode(void);
uint32_t emaczero_profile_elapsed(uint32_t start, uint32_t end);
void emaczero_profile_counter(enum emaczero_profile_counter_id counter);
void emaczero_profile_add_cycles(enum emaczero_profile_cycle_id counter, uint32_t cycles);
void emaczero_profile_max(enum emaczero_profile_max_id counter, uint32_t value);
void emaczero_profile_min(enum emaczero_profile_min_id counter, uint32_t value);
bool emaczero_profile_should_keep_control(const uint8_t *bytes, size_t len);
void emaczero_profile_note_release(uint32_t lifetime_cycles);
int emaczero_profile_send_raw_frame(const uint8_t *frame, size_t len);
int emaczero_profile_send_raw_frame_burst(const uint8_t *frame, size_t len, uint32_t count);
#else
static inline void emaczero_profile_snapshot(struct emaczero_profile_snapshot *snapshot)
{
	(void)snapshot;
}

static inline void emaczero_profile_reset(void)
{
}

static inline void emaczero_profile_set_mode(enum emaczero_profile_mode mode)
{
	(void)mode;
}

static inline enum emaczero_profile_mode emaczero_profile_get_mode(void)
{
	return EMACZERO_PROFILE_MODE_NORMAL;
}

static inline uint32_t emaczero_profile_elapsed(uint32_t start, uint32_t end)
{
	return end - start;
}

static inline void emaczero_profile_counter(enum emaczero_profile_counter_id counter)
{
	(void)counter;
}

static inline void emaczero_profile_add_cycles(enum emaczero_profile_cycle_id counter,
					       uint32_t cycles)
{
	(void)counter;
	(void)cycles;
}

static inline void emaczero_profile_max(enum emaczero_profile_max_id counter, uint32_t value)
{
	(void)counter;
	(void)value;
}

static inline void emaczero_profile_min(enum emaczero_profile_min_id counter, uint32_t value)
{
	(void)counter;
	(void)value;
}

static inline bool emaczero_profile_should_keep_control(const uint8_t *bytes, size_t len)
{
	(void)bytes;
	(void)len;
	return false;
}

static inline void emaczero_profile_note_release(uint32_t lifetime_cycles)
{
	(void)lifetime_cycles;
}

static inline int emaczero_profile_send_raw_frame(const uint8_t *frame, size_t len)
{
	(void)frame;
	(void)len;
	return -1;
}

static inline int emaczero_profile_send_raw_frame_burst(const uint8_t *frame, size_t len,
							uint32_t count)
{
	(void)frame;
	(void)len;
	(void)count;
	return -1;
}
#endif

#endif
