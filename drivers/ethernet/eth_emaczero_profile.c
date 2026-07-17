/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 */

#include <string.h>

#include <zephyr/kernel.h>

#include "eth_emaczero_profile.h"

#define EMZ_PROFILE_CONTROL_PORT 5002u
#define EMZ_ETH_TYPE_IPV4 0x0800u
#define EMZ_ETH_TYPE_ARP 0x0806u
#define EMZ_IP_PROTO_UDP 17u

struct emaczero_profile_state {
	struct k_spinlock lock;
	enum emaczero_profile_mode mode;
	struct emaczero_profile_snapshot stats;
};

static struct emaczero_profile_state emz_profile;

static void emz_profile_add_u64(uint64_t *value, uint64_t add)
{
	*value += add;
}

static void emz_profile_set_max_u32(uint32_t *value, uint32_t candidate)
{
	if (candidate > *value) {
		*value = candidate;
	}
}

static void emz_profile_set_min_u32(uint32_t *value, uint32_t candidate)
{
	if (candidate < *value) {
		*value = candidate;
	}
}

uint32_t emaczero_profile_elapsed(uint32_t start, uint32_t end)
{
	return end - start;
}

void emaczero_profile_snapshot(struct emaczero_profile_snapshot *snapshot)
{
	k_spinlock_key_t key;

	if (snapshot == NULL) {
		return;
	}

	key = k_spin_lock(&emz_profile.lock);
	*snapshot = emz_profile.stats;
	snapshot->mode = emz_profile.mode;
	snapshot->cycles_per_sec = sys_clock_hw_cycles_per_sec();
	k_spin_unlock(&emz_profile.lock, key);
}

void emaczero_profile_reset(void)
{
	k_spinlock_key_t key = k_spin_lock(&emz_profile.lock);
	enum emaczero_profile_mode mode = emz_profile.mode;

	memset(&emz_profile.stats, 0, sizeof(emz_profile.stats));
	emz_profile.stats.rx_min_free = UINT32_MAX;
	emz_profile.mode = mode;
	k_spin_unlock(&emz_profile.lock, key);
}

void emaczero_profile_set_mode(enum emaczero_profile_mode mode)
{
	k_spinlock_key_t key;

	if (mode > EMACZERO_PROFILE_MODE_DROP_AFTER_PKT) {
		mode = EMACZERO_PROFILE_MODE_NORMAL;
	}

	key = k_spin_lock(&emz_profile.lock);
	emz_profile.mode = mode;
	k_spin_unlock(&emz_profile.lock, key);
}

enum emaczero_profile_mode emaczero_profile_get_mode(void)
{
	enum emaczero_profile_mode mode;
	k_spinlock_key_t key = k_spin_lock(&emz_profile.lock);

	mode = emz_profile.mode;
	k_spin_unlock(&emz_profile.lock, key);
	return mode;
}

bool emaczero_profile_should_keep_control(const uint8_t *bytes, size_t len)
{
	uint16_t eth_type;
	uint8_t ihl;
	size_t udp;
	uint16_t dst_port;

	if (bytes == NULL || len < 14u) {
		return false;
	}

	eth_type = ((uint16_t)bytes[12] << 8) | bytes[13];
	if (eth_type == EMZ_ETH_TYPE_ARP) {
		return true;
	}

	if (eth_type != EMZ_ETH_TYPE_IPV4 || len < 34u) {
		return false;
	}

	ihl = (bytes[14] & 0x0fu) * 4u;
	if (ihl < 20u || len < 14u + ihl + 8u || bytes[23] != EMZ_IP_PROTO_UDP) {
		return false;
	}

	udp = 14u + ihl;
	dst_port = ((uint16_t)bytes[udp + 2u] << 8) | bytes[udp + 3u];
	return dst_port == EMZ_PROFILE_CONTROL_PORT;
}

void emaczero_profile_note_release(uint32_t lifetime_cycles)
{
	k_spinlock_key_t key = k_spin_lock(&emz_profile.lock);

	emz_profile.stats.rx_released++;
	emz_profile.stats.buffer_lifetime_samples++;
	emz_profile_add_u64(&emz_profile.stats.buffer_lifetime_cycles_total, lifetime_cycles);
	emz_profile_set_max_u32(&emz_profile.stats.buffer_lifetime_cycles_max, lifetime_cycles);
	k_spin_unlock(&emz_profile.lock, key);
}

void emaczero_profile_counter(enum emaczero_profile_counter_id counter)
{
	k_spinlock_key_t key = k_spin_lock(&emz_profile.lock);

	switch (counter) {
	case EMACZERO_PROFILE_COUNTER_DMA_CALLBACKS:
		emz_profile.stats.dma_callbacks++;
		break;
	case EMACZERO_PROFILE_COUNTER_DMA_ERRORS:
		emz_profile.stats.dma_errors++;
		break;
	case EMACZERO_PROFILE_COUNTER_DMA_DROP_AFTER_DMA:
		emz_profile.stats.dma_drop_after_dma++;
		break;
	case EMACZERO_PROFILE_COUNTER_RX_WORKER_PACKETS:
		emz_profile.stats.rx_worker_packets++;
		break;
	case EMACZERO_PROFILE_COUNTER_RX_INVALID:
		emz_profile.stats.rx_invalid++;
		break;
	case EMACZERO_PROFILE_COUNTER_RX_ALLOC_PKT_FAIL:
		emz_profile.stats.rx_alloc_pkt_fail++;
		break;
	case EMACZERO_PROFILE_COUNTER_RX_ALLOC_FRAG_FAIL:
		emz_profile.stats.rx_alloc_frag_fail++;
		break;
	case EMACZERO_PROFILE_COUNTER_RX_COPY_FALLBACK:
		emz_profile.stats.rx_copy_fallback++;
		break;
	case EMACZERO_PROFILE_COUNTER_RX_ZERO_COPY_SUBMIT:
		emz_profile.stats.rx_zero_copy_submit++;
		break;
	case EMACZERO_PROFILE_COUNTER_RX_COPY_SUBMIT:
		emz_profile.stats.rx_copy_submit++;
		break;
	case EMACZERO_PROFILE_COUNTER_RX_DROP_AFTER_PKT:
		emz_profile.stats.rx_drop_after_pkt++;
		break;
	case EMACZERO_PROFILE_COUNTER_RX_NET_RECV_FAIL:
		emz_profile.stats.rx_net_recv_fail++;
		break;
	case EMACZERO_PROFILE_COUNTER_RX_REFILL_CALLS:
		emz_profile.stats.rx_refill_calls++;
		break;
	case EMACZERO_PROFILE_COUNTER_RX_REFILL_QUEUED:
		emz_profile.stats.rx_refill_queued++;
		break;
	case EMACZERO_PROFILE_COUNTER_RX_REFILL_NO_FREE:
		emz_profile.stats.rx_refill_no_free++;
		break;
	}

	k_spin_unlock(&emz_profile.lock, key);
}

void emaczero_profile_add_cycles(enum emaczero_profile_cycle_id counter, uint32_t cycles)
{
	k_spinlock_key_t key = k_spin_lock(&emz_profile.lock);

	switch (counter) {
	case EMACZERO_PROFILE_CYCLES_DMA_CB:
		emz_profile_add_u64(&emz_profile.stats.dma_cb_cycles_total, cycles);
		emz_profile_set_max_u32(&emz_profile.stats.dma_cb_cycles_max, cycles);
		break;
	case EMACZERO_PROFILE_CYCLES_RX_BUILD:
		emz_profile_add_u64(&emz_profile.stats.rx_build_cycles_total, cycles);
		emz_profile_set_max_u32(&emz_profile.stats.rx_build_cycles_max, cycles);
		break;
	case EMACZERO_PROFILE_CYCLES_NET_RECV:
		emz_profile_add_u64(&emz_profile.stats.net_recv_cycles_total, cycles);
		emz_profile_set_max_u32(&emz_profile.stats.net_recv_cycles_max, cycles);
		break;
	}

	k_spin_unlock(&emz_profile.lock, key);
}

void emaczero_profile_max(enum emaczero_profile_max_id counter, uint32_t value)
{
	k_spinlock_key_t key = k_spin_lock(&emz_profile.lock);

	switch (counter) {
	case EMACZERO_PROFILE_MAX_RX_DMA_INFLIGHT:
		emz_profile_set_max_u32(&emz_profile.stats.rx_max_dma_inflight, value);
		break;
	case EMACZERO_PROFILE_MAX_RX_STACK_OWNED:
		emz_profile_set_max_u32(&emz_profile.stats.rx_max_stack_owned, value);
		break;
	}

	k_spin_unlock(&emz_profile.lock, key);
}

void emaczero_profile_min(enum emaczero_profile_min_id counter, uint32_t value)
{
	k_spinlock_key_t key = k_spin_lock(&emz_profile.lock);

	switch (counter) {
	case EMACZERO_PROFILE_MIN_RX_FREE:
		emz_profile_set_min_u32(&emz_profile.stats.rx_min_free, value);
		break;
	}

	k_spin_unlock(&emz_profile.lock, key);
}
