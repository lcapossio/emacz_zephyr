/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 */

#define DT_DRV_COMPAT bard0_emaczero

#include <errno.h>
#include <string.h>

#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/dma.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/net/ethernet.h>
#include <zephyr/net_buf.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_pkt.h>
#include <zephyr/sys/barrier.h>
#include <zephyr/sys/sys_io.h>
#include <zephyr/sys/util.h>
#include <ethernet/eth_stats.h>

#include "eth_emaczero.h"
#include "eth_emaczero_profile.h"

LOG_MODULE_REGISTER(eth_emaczero, CONFIG_ETHERNET_LOG_LEVEL);

#define EMZ_REG_VERSION      0x00u
#define EMZ_REG_CTRL         0x04u
#define EMZ_REG_STATUS       0x08u
#define EMZ_REG_MAC_LO       0x0cu
#define EMZ_REG_MAC_HI       0x10u
#define EMZ_REG_IRQ_EN       0x20u
#define EMZ_REG_IRQ_STATUS   0x24u
#define EMZ_REG_TX_FRAME_CNT 0x28u
#define EMZ_REG_TX_BYTE_CNT  0x2cu
#define EMZ_REG_RX_FRAME_CNT 0x30u
#define EMZ_REG_RX_BYTE_CNT  0x34u
#define EMZ_REG_RX_ERR_CNT   0x38u
#define EMZ_REG_RX_ERR_ALIGN 0x4cu
#define EMZ_REG_RX_BCAST     0x58u
#define EMZ_REG_RX_MCAST     0x5cu

#define EMZ_VERSION_VALUE 0x0001454du

#define EMZ_CTRL_TX_EN        BIT(0)
#define EMZ_CTRL_RX_EN        BIT(1)
#define EMZ_CTRL_PROMISC      BIT(2)
#define EMZ_CTRL_SPEED_SHIFT  3
#define EMZ_CTRL_SPEED_MASK   (0x3u << EMZ_CTRL_SPEED_SHIFT)
#define EMZ_CTRL_FULL_DUPLEX  BIT(5)

#define EMZ_SPEED_1G   0x0u
#define EMZ_SPEED_100M 0x1u
#define EMZ_SPEED_10M  0x2u

#define EMZ_IRQ_ALL (BIT(0) | BIT(1) | BIT(2))

#define EMZ_DMA_TX_CHANNEL 0u
#define EMZ_DMA_RX_CHANNEL 1u
#define EMZ_DMA_LINKED_CHANNEL_NO_CSUM_OFFLOAD 0u
#define EMZ_DMA_BUFFER_COUNT_TX 32u
/* One slot stays unused so a full ring is distinguishable from an empty one. */
#define EMZ_TX_SLOTS (EMZ_DMA_BUFFER_COUNT_TX - 1u)
/* Longest a sender waits for a TX slot: a full ring at 10 Mbit/s drains in
 * about 40 ms.
 */
#define EMZ_TX_SLOT_TIMEOUT K_MSEC(100)
#define EMZ_DMA_BUFFER_COUNT_RX CONFIG_ETH_EMACZERO_RX_BUFFER_COUNT
#define EMZ_DMA_CACHE_LINE_SIZE 16u
/* D-cache aperture shared by both CPU shells: MicroBlaze V via
 * C_DCACHE_*ADDR in build_arty_a7_mbv.py, VexRiscv via the I/O predicate
 * patched in gen_vexriscv.py. DMA buffers live in the DDR window at
 * CONFIG_ETH_EMACZERO_DMA_MEMORY_BASE and the AXI DMA places its SG
 * descriptors through its memory-region property, both outside this range.
 * Cache maintenance on addresses outside the aperture is dead overhead
 * (~285 CBOs/frame for a 1514-byte payload).
 */
#define EMZ_DMA_DCACHE_BASE 0x90000000u
#define EMZ_DMA_DCACHE_HIGH 0x97FFFFFFu

#if CONFIG_ETH_EMACZERO_DMA_MEMORY_BASE != 0
/* The DMA window also holds the perf-stats block and the JTAG mailbox, which
 * are shared with the JTAG-AXI bridge and get no cache maintenance at all.
 * Their coherency rests entirely on this window being uncached.
 */
BUILD_ASSERT((uint64_t)CONFIG_ETH_EMACZERO_DMA_MEMORY_BASE > EMZ_DMA_DCACHE_HIGH ||
		     (uint64_t)CONFIG_ETH_EMACZERO_DMA_MEMORY_BASE +
				     CONFIG_ETH_EMACZERO_DMA_MEMORY_SIZE <=
			     EMZ_DMA_DCACHE_BASE,
	     "emacZero DMA memory window overlaps the CPU D-cache aperture");
#endif

/* Sol r7 instrumentation regions. Slot indices are wire-format for host tools;
 * do not reorder without bumping EMACZERO_PERF_STATS_VERSION and updating readers.
 */
enum emz_r7_region {
	EMZ_R7_ISR_TOTAL = 0,      /* ISR entry -> ISR exit (whole poll incl. cache/CSR) */
	EMZ_R7_LOCK_CONSUME = 1,   /* spin_lock..spin_unlock in emz_rx_direct_poll body */
	EMZ_R7_READY_ENQUEUE = 2,  /* atomic_inc + k_fifo_put(rx_ready_fifo) */
	EMZ_R7_RELEASE_REFILL = 3, /* emz_release_rx_buffer entry -> refill returns */
	EMZ_R7_LOCK_POST = 4,      /* spin_lock..spin_unlock in emz_rx_direct_post_one */
	EMZ_R7_TAIL_CSR = 5,       /* barrier + TAILDESC write in emz_rx_direct_update_tail */
	EMZ_R7_RX_THREAD_BUILD = 6,/* rx_thread: net_pkt build -> net_recv_data() return */
	EMZ_R7_SLOT_COUNT = 8,
};
#define EMZ_R7_MAGIC 0x50524632u  /* "PRF2" LE */
#define EMZ_DMA_RX_MAX_INFLIGHT CONFIG_ETH_EMACZERO_RX_DMA_POST_COUNT
#define EMZ_RX_MAX_STACK_OWNED_ZEROCOPY CONFIG_ETH_EMACZERO_RX_MAX_STACK_OWNED_ZEROCOPY
#define EMZ_RX_COPY_FALLBACK_COUNT CONFIG_ETH_EMACZERO_RX_COPY_FALLBACK_COUNT
#define EMZ_RX_THREAD_STACK_SIZE 2048u
#define EMZ_RX_THREAD_PRIORITY -1
#define EMZ_ETH_BUFFER_SIZE NET_ETH_MAX_FRAME_SIZE
#define EMZ_ETH_TYPE_IPV4 0x0800u
#define EMZ_ETH_TYPE_ARP 0x0806u
#define EMZ_IP_PROTO_ICMP 1u
#define EMZ_IP_PROTO_UDP 17u

#define EMZ_AXI_DMA_REG_MM2S_DMACR 0x00u
#define EMZ_AXI_DMA_REG_MM2S_DMASR 0x04u
#define EMZ_AXI_DMA_REG_MM2S_CURDESC 0x08u
#define EMZ_AXI_DMA_REG_MM2S_TAILDESC 0x10u
#define EMZ_AXI_DMA_REG_S2MM_DMACR 0x30u
#define EMZ_AXI_DMA_REG_S2MM_DMASR 0x34u
#define EMZ_AXI_DMA_REG_S2MM_CURDESC 0x38u
#define EMZ_AXI_DMA_REG_S2MM_TAILDESC 0x40u

#define EMZ_AXI_DMA_DMACR_IRQTHRESH_SHIFT 16
#define EMZ_AXI_DMA_DMACR_IRQDELAY_SHIFT 24
#define EMZ_AXI_DMA_DMACR_ERR_IRQEN BIT(14)
#define EMZ_AXI_DMA_DMACR_DLY_IRQEN BIT(13)
#define EMZ_AXI_DMA_DMACR_IOC_IRQEN BIT(12)
#define EMZ_AXI_DMA_DMACR_RESET BIT(2)
#define EMZ_AXI_DMA_DMACR_RS BIT(0)

#define EMZ_AXI_DMA_DMASR_IRQ_ALL (BIT(14) | BIT(13) | BIT(12))
#define EMZ_AXI_DMA_DMASR_ERROR_MASK (BIT(10) | BIT(9) | BIT(8) | BIT(6) | BIT(5) | BIT(4))
/* DMASR.Halted: the engine clears RS and stops on any DMA/SG error. Nothing
 * restarts it except a full RESET + CURDESC + RS sequence.
 */
#define EMZ_AXI_DMA_DMASR_HALTED BIT(0)

#define EMZ_AXI_DMA_BD_CTRL_SOF BIT(27)
#define EMZ_AXI_DMA_BD_CTRL_EOF BIT(26)
#define EMZ_AXI_DMA_BD_CTRL_LEN_MASK 0x03ffffffu
#define EMZ_AXI_DMA_BD_STATUS_COMPLETE BIT(31)
#define EMZ_AXI_DMA_BD_STATUS_ERROR_MASK (BIT(30) | BIT(29) | BIT(28))
#define EMZ_AXI_DMA_BD_STATUS_LEN_MASK 0x03ffffffu

#if defined(CONFIG_DMA_XILINX_AXI_DMA)
uint32_t dma_xilinx_axi_dma_last_received_frame_length(const struct device *dev);
#endif

#if defined(CONFIG_ETH_EMACZERO_PROFILE)
static const struct device *emz_profile_dev;
#endif

struct emaczero_tx_buffer {
	uint8_t *bytes;
} __aligned(4);

struct emaczero_rx_buffer {
	void *fifo_reserved;
	uint8_t *bytes;
	unsigned int len;
	int status;
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
	uint32_t dma_done_cycle;
#endif
	uint32_t stack_handoff_cycle;
} __aligned(4);

struct emaczero_rx_bd {
	uint32_t nxtdesc;
	uint32_t nxtdesc_msb;
	uint32_t buffer_address;
	uint32_t buffer_address_msb;
	uint32_t reserved0;
	uint32_t reserved1;
	uint32_t control;
	uint32_t status;
	uint32_t app0;
	uint32_t app1;
	uint32_t app2;
	uint32_t app3;
	uint32_t app4;
	uint32_t pad0;
	uint32_t pad1;
	uint32_t pad2;
} __aligned(64);

struct emaczero_rx_frag_ctx {
	const struct device *dev;
	struct emaczero_rx_buffer *rx;
};

struct emaczero_rx_copy_frag_ctx {
	bool in_use;
};

struct emaczero_config {
	uintptr_t base;
	uintptr_t dma_base;
	const struct device *dma;
	unsigned int dma_rx_irq;
	void (*direct_rx_irq_configure)(void);
	k_thread_stack_t *rx_thread_stack;
	size_t rx_thread_stack_size;
	uint32_t speed;
	uint8_t mac[NET_ETH_ADDR_LEN];
};

struct emaczero_data {
	const struct device *dev;
	emaczero_rx_interceptor_t rx_interceptor;
	void *rx_interceptor_user_data;
	struct net_if *iface;
	uint8_t mac[NET_ETH_ADDR_LEN];
	bool promisc;
	bool dma_is_configured_rx;
	bool dma_is_configured_tx;
	size_t tx_populated_buffer_index;
	size_t tx_completed_buffer_index;
	/* Free TX slots on the DMA-API path; given by the MM2S callback. */
	struct k_sem tx_slot_sem;
	/* Set from the first DMA error report until emz_dma_recover() has
	 * rebuilt both channels; refill and RX completions stand down meanwhile.
	 */
	atomic_t dma_recover_pending;
	struct k_work_delayable dma_recover_work;
	uint32_t tx_bd_inflight;
	unsigned int rx_dma_inflight;
	uint32_t last_dma_callback_cycle;
	struct emaczero_rx_bd *tx_bd_ring;
	struct emaczero_rx_bd *rx_bd_ring;
	struct emaczero_rx_buffer *rx_bd_buffer[EMZ_DMA_BUFFER_COUNT_RX];
	size_t rx_bd_consume_index;
	size_t rx_bd_refill_index;
	size_t rx_bd_tail_index;
	uint32_t rx_bd_posted;
	bool rx_direct_ring_started;
	struct k_spinlock rx_direct_lock;
	struct k_work_delayable rx_direct_poll_work;
	struct k_work rx_direct_recover_work;
	atomic_t rx_direct_recover_pending;
	atomic_t rx_free_count;
	atomic_t rx_dma_fifo_count;
	atomic_t rx_ready_fifo_count;
	atomic_t rx_worker_count;
	atomic_t rx_stack_owned_count;
	struct k_spinlock rx_lock;
	struct k_mutex tx_lock;
	struct k_fifo rx_free_fifo;
	struct k_fifo rx_dma_fifo;
	struct k_fifo rx_ready_fifo;
	struct k_thread rx_thread;
	struct emaczero_rx_buffer rx_buffer[EMZ_DMA_BUFFER_COUNT_RX];
	struct emaczero_tx_buffer tx_buffer[EMZ_DMA_BUFFER_COUNT_TX];
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
	/* Shared by every descriptor of a TX benchmark burst. */
	uint8_t *tx_burst_bytes;
#endif
#if CONFIG_ETH_EMACZERO_DMA_MEMORY_SIZE == 0
	uint8_t rx_storage[EMZ_DMA_BUFFER_COUNT_RX][EMZ_ETH_BUFFER_SIZE] __aligned(4);
	uint8_t tx_storage[EMZ_DMA_BUFFER_COUNT_TX][EMZ_ETH_BUFFER_SIZE] __aligned(4);
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
	uint8_t tx_burst_storage[EMZ_ETH_BUFFER_SIZE] __aligned(4);
#endif
#endif
#if defined(CONFIG_NET_STATISTICS_ETHERNET)
	struct net_stats_eth stats;
#endif
};

static int emz_refill_dma_rx(const struct device *dev);
static void emz_dma_request_recover(struct emaczero_data *data);

static void emz_dma_cache_fence(void)
{
#ifdef CONFIG_ETH_EMACZERO_DCACHE_MAINT
	__asm__ volatile("fence iorw, iorw" ::: "memory");
#endif
}

static void emz_dma_cache_clean_line(uintptr_t addr)
{
#ifdef CONFIG_ETH_EMACZERO_DCACHE_MAINT
	__asm__ volatile(
		".option push\n"
		".option arch, +zicbom\n"
		"cbo.clean (%0)\n"
		".option pop\n"
		:
		: "r"(addr)
		: "memory");
#else
	ARG_UNUSED(addr);
#endif
}

static void emz_dma_cache_invd_line(uintptr_t addr)
{
#ifdef CONFIG_ETH_EMACZERO_DCACHE_MAINT
	__asm__ volatile(
		".option push\n"
		".option arch, +zicbom\n"
		"cbo.inval (%0)\n"
		".option pop\n"
		:
		: "r"(addr)
		: "memory");
#else
	ARG_UNUSED(addr);
#endif
}

static void emz_dma_cache_range(const void *addr, size_t size,
				void (*op)(uintptr_t))
{
	uintptr_t start;
	uintptr_t end;

	if (size == 0u) {
		return;
	}

	start = (uintptr_t)addr & ~(uintptr_t)(EMZ_DMA_CACHE_LINE_SIZE - 1u);
	end = ROUND_UP((uintptr_t)addr + size, EMZ_DMA_CACHE_LINE_SIZE);

	/* Skip if the whole range is outside the D-cache aperture. */
	if (end <= (uintptr_t)EMZ_DMA_DCACHE_BASE ||
	    start > (uintptr_t)EMZ_DMA_DCACHE_HIGH) {
		return;
	}

	emz_dma_cache_fence();
	for (uintptr_t line = start; line < end; line += EMZ_DMA_CACHE_LINE_SIZE) {
		op(line);
	}
	emz_dma_cache_fence();
}

static void emz_dma_cache_flush(const void *addr, size_t size)
{
	emz_dma_cache_range(addr, size, emz_dma_cache_clean_line);
}

static void emz_dma_cache_invd(const void *addr, size_t size)
{
	emz_dma_cache_range(addr, size, emz_dma_cache_invd_line);
}

#if defined(CONFIG_ETH_EMACZERO_R7_INSTRUMENTATION)
static inline uint32_t emz_r7_elapsed(uint32_t start, uint32_t end)
{
	return end - start;
}

static inline void emz_r7_add(enum emz_r7_region slot, uint32_t cycles)
{
	uint64_t sum;

	if ((unsigned)slot >= EMZ_R7_SLOT_COUNT) {
		return;
	}
	emaczero_perf_stats.r7_samples[slot]++;
	sum = ((uint64_t)emaczero_perf_stats.r7_sum_hi[slot] << 32) |
	      emaczero_perf_stats.r7_sum_lo[slot];
	sum += cycles;
	emaczero_perf_stats.r7_sum_lo[slot] = (uint32_t)sum;
	emaczero_perf_stats.r7_sum_hi[slot] = (uint32_t)(sum >> 32);
	if (cycles > emaczero_perf_stats.r7_max[slot]) {
		emaczero_perf_stats.r7_max[slot] = cycles;
	}
}

static inline void emz_r7_init_magic(void)
{
	emaczero_perf_stats.r7_magic = EMZ_R7_MAGIC;
	emaczero_perf_stats.r7_hz = (uint32_t)sys_clock_hw_cycles_per_sec();
}
#else
static inline uint32_t emz_r7_elapsed(uint32_t start, uint32_t end)
{
	(void)start; (void)end;
	return 0u;
}
static inline void emz_r7_add(enum emz_r7_region slot, uint32_t cycles)
{
	(void)slot; (void)cycles;
}
static inline void emz_r7_init_magic(void) {}
#endif

static inline void emz_r7_note_lock(void)
{
#if defined(CONFIG_ETH_EMACZERO_R7_INSTRUMENTATION)
	emaczero_perf_stats.r7_lock_acquisitions++;
#endif
}

#if CONFIG_ETH_EMACZERO_DMA_MEMORY_SIZE != 0
static uintptr_t emz_dma_mem_cursor;
static uintptr_t emz_dma_mem_end;
static uintptr_t emz_sg_mem_cursor;
static uintptr_t emz_sg_mem_end;

static void emz_dma_mem_reset(void)
{
	emz_dma_mem_cursor = CONFIG_ETH_EMACZERO_DMA_MEMORY_BASE;
	emz_dma_mem_end = CONFIG_ETH_EMACZERO_DMA_MEMORY_BASE +
			  CONFIG_ETH_EMACZERO_DMA_MEMORY_SIZE -
			  EMACZERO_PERF_STATS_DMA_RESERVED;
}

static void emz_sg_mem_reset(void)
{
#if CONFIG_ETH_EMACZERO_SG_MEMORY_SIZE != 0
	emz_sg_mem_cursor = CONFIG_ETH_EMACZERO_SG_MEMORY_BASE;
	emz_sg_mem_end = CONFIG_ETH_EMACZERO_SG_MEMORY_BASE +
			 CONFIG_ETH_EMACZERO_SG_MEMORY_SIZE;
#else
	emz_sg_mem_cursor = 0u;
	emz_sg_mem_end = 0u;
#endif
}

static void *emz_dma_mem_alloc(size_t align, size_t size)
{
	uintptr_t ptr = ROUND_UP(emz_dma_mem_cursor, align);
	uintptr_t next = ROUND_UP(ptr + size, align);

	if (ptr == 0u || next > emz_dma_mem_end || next < ptr) {
		return NULL;
	}

	emz_dma_mem_cursor = next;
	return (void *)ptr;
}

static void *emz_sg_mem_alloc(size_t align, size_t size)
{
#if CONFIG_ETH_EMACZERO_SG_MEMORY_SIZE != 0
	uintptr_t ptr = ROUND_UP(emz_sg_mem_cursor, align);
	uintptr_t next = ROUND_UP(ptr + size, align);

	if (ptr == 0u || next > emz_sg_mem_end || next < ptr) {
		return NULL;
	}

	emz_sg_mem_cursor = next;
	return (void *)ptr;
#else
	return emz_dma_mem_alloc(align, size);
#endif
}

void *dma_xilinx_axi_dma_sg_descriptor_alloc(size_t align, size_t size)
{
	return emz_sg_mem_alloc(align, size);
}

void dma_xilinx_axi_dma_sg_descriptor_free(void *ptr)
{
	ARG_UNUSED(ptr);
}
#endif

#define EMZ_PROFILE_COUNTER(counter) emaczero_profile_counter(counter)
#define EMZ_PROFILE_ADD_CYCLES(counter, cycles) emaczero_profile_add_cycles(counter, cycles)
#define EMZ_PROFILE_MAX(counter, value) emaczero_profile_max(counter, value)
#define EMZ_PROFILE_MIN(counter, value) emaczero_profile_min(counter, value)

static void emz_perf_set_max_u32(volatile uint32_t *value, uint32_t candidate)
{
	if (candidate > *value) {
		*value = candidate;
	}
}

static void emz_perf_set_min_u32(volatile uint32_t *value, uint32_t candidate)
{
	if (candidate < *value) {
		*value = candidate;
	}
}

static void emz_perf_note_dma_callback_gap(struct emaczero_data *data, uint32_t now_cycle)
{
	if (data->last_dma_callback_cycle != 0u) {
		uint32_t gap_cycles = now_cycle - data->last_dma_callback_cycle;

		emz_perf_set_max_u32(&emaczero_perf_stats.dma_callback_gap_cycles_max,
				      gap_cycles);
		if (gap_cycles >= (sys_clock_hw_cycles_per_sec() / 1000u)) {
			emaczero_perf_stats.dma_callback_gap_ge_1ms++;
		}
	}
	data->last_dma_callback_cycle = now_cycle;
}

static void emz_perf_update_pool_inflight(struct emaczero_data *data)
{
	uint32_t free_count = (uint32_t)atomic_get(&data->rx_free_count);
	uint32_t dma_fifo_count = (uint32_t)atomic_get(&data->rx_dma_fifo_count);
	uint32_t ready_fifo_count = (uint32_t)atomic_get(&data->rx_ready_fifo_count);
	uint32_t worker_count = (uint32_t)atomic_get(&data->rx_worker_count);
	uint32_t stack_owned_count = (uint32_t)atomic_get(&data->rx_stack_owned_count);
	uint32_t owner_sum = free_count + dma_fifo_count + ready_fifo_count + worker_count +
			     stack_owned_count;
	uint32_t inflight = free_count <= EMZ_DMA_BUFFER_COUNT_RX ?
			    EMZ_DMA_BUFFER_COUNT_RX - free_count : 0u;

	emaczero_perf_stats.rx_free_current = free_count;
	emaczero_perf_stats.rx_dma_fifo_current = dma_fifo_count;
	emaczero_perf_stats.rx_ready_fifo_current = ready_fifo_count;
	emaczero_perf_stats.rx_worker_current = worker_count;
	emaczero_perf_stats.rx_stack_owned_current = stack_owned_count;
	emaczero_perf_stats.rx_owner_sum_current = owner_sum;
	/* The five atomic reads above are not a consistent snapshot: a buffer
	 * mid-transfer between two owner counters shows a transient off-by-one
	 * or off-by-two on nearly every callback. Only flag when the drift is
	 * larger than a plausible in-flight window, so this counter continues
	 * to catch real leaks without firing on every completion.
	 */
	if (owner_sum + 8u < EMZ_DMA_BUFFER_COUNT_RX ||
	    owner_sum > EMZ_DMA_BUFFER_COUNT_RX + 8u) {
		emaczero_perf_stats.rx_owner_sum_bad++;
	}
	emaczero_perf_stats.rx_pool_inflight_current = inflight;
	emz_perf_set_max_u32(&emaczero_perf_stats.rx_pool_inflight_high, inflight);
}

#if defined(CONFIG_ETH_EMACZERO_RX_DIRECT_RING)
static void emz_perf_set_bd_available(struct emaczero_data *data)
{
	uint32_t available = EMZ_DMA_BUFFER_COUNT_RX - data->rx_bd_posted;

	emaczero_perf_stats.rx_bd_available_current = available;
	emz_perf_set_min_u32(&emaczero_perf_stats.rx_bd_available_min, available);
}
#endif

static void emz_perf_note_dwell(uint32_t cycles)
{
	uint32_t hz = emaczero_perf_stats.cycles_per_sec;

	if (hz == 0u) {
		hz = sys_clock_hw_cycles_per_sec();
	}

	emaczero_perf_stats.rx_dwell_samples++;
	emaczero_perf_stats.rx_dwell_cycles_total += cycles;
	emz_perf_set_max_u32(&emaczero_perf_stats.rx_dwell_cycles_max, cycles);

	if (cycles < (hz / 1000u)) {
		emaczero_perf_stats.rx_dwell_lt_1ms++;
	} else if (cycles < (hz / 200u)) {
		emaczero_perf_stats.rx_dwell_1_5ms++;
	} else if (cycles < (hz / 50u)) {
		emaczero_perf_stats.rx_dwell_5_20ms++;
	} else if (cycles < (hz / 10u)) {
		emaczero_perf_stats.rx_dwell_20_100ms++;
	} else {
		emaczero_perf_stats.rx_dwell_ge_100ms++;
	}
}

static void emz_release_rx_buffer(const struct device *dev, struct emaczero_rx_buffer *rx)
{
	struct emaczero_data *data = dev->data;
	uint32_t stack_handoff_cycle = rx->stack_handoff_cycle;
	uint32_t r7_rel_start = k_cycle_get_32();

#if defined(CONFIG_ETH_EMACZERO_PROFILE)
	emaczero_profile_note_release(emaczero_profile_elapsed(rx->dma_done_cycle, k_cycle_get_32()));
#endif
	if (stack_handoff_cycle != 0u) {
		emz_perf_note_dwell(k_cycle_get_32() - stack_handoff_cycle);
		rx->stack_handoff_cycle = 0u;
	}
	emaczero_perf_stats.rx_released++;
	atomic_inc(&data->rx_free_count);
	emz_perf_update_pool_inflight(data);
	k_fifo_put(&data->rx_free_fifo, rx);
	(void)emz_refill_dma_rx(dev);
	emz_r7_add(EMZ_R7_RELEASE_REFILL, emz_r7_elapsed(r7_rel_start, k_cycle_get_32()));
}

static void emz_release_rx_buffer_from_worker(const struct device *dev,
					      struct emaczero_rx_buffer *rx)
{
	struct emaczero_data *data = dev->data;

	atomic_dec(&data->rx_worker_count);
	emz_perf_update_pool_inflight(data);
	emz_release_rx_buffer(dev, rx);
}

static void emz_rx_frag_destroy(struct net_buf *buf)
{
	struct emaczero_rx_frag_ctx *ctx = net_buf_user_data(buf);
	const struct device *dev = ctx->dev;
	struct emaczero_rx_buffer *rx = ctx->rx;
	struct emaczero_data *data;

	ctx->dev = NULL;
	ctx->rx = NULL;
	net_buf_destroy(buf);

	if (dev == NULL || rx == NULL) {
		return;
	}

	data = dev->data;
	atomic_dec(&data->rx_stack_owned_count);
	emz_release_rx_buffer(dev, rx);
}

NET_BUF_POOL_FIXED_DEFINE(emz_rx_frag_pool, EMZ_DMA_BUFFER_COUNT_RX, 1,
			  sizeof(struct emaczero_rx_frag_ctx), emz_rx_frag_destroy);

#if EMZ_RX_COPY_FALLBACK_COUNT > 0
static uint8_t emz_rx_copy_storage[EMZ_RX_COPY_FALLBACK_COUNT][EMZ_ETH_BUFFER_SIZE]
	__aligned(4);

static void emz_rx_copy_frag_destroy(struct net_buf *buf)
{
	struct emaczero_rx_copy_frag_ctx *ctx = net_buf_user_data(buf);

	ctx->in_use = false;
	net_buf_destroy(buf);
}

NET_BUF_POOL_FIXED_DEFINE(emz_rx_copy_frag_pool, EMZ_RX_COPY_FALLBACK_COUNT, 1,
			  sizeof(struct emaczero_rx_copy_frag_ctx),
			  emz_rx_copy_frag_destroy);

static struct net_buf *emz_rx_copy_frag_alloc(const struct emaczero_rx_buffer *rx)
{
	struct net_buf *frag;
	struct emaczero_rx_copy_frag_ctx *ctx;
	int id;

	frag = net_buf_alloc_with_data(&emz_rx_copy_frag_pool, NULL, 0, K_NO_WAIT);
	if (frag == NULL) {
		return NULL;
	}

	id = net_buf_id(frag);
	if (id < 0 || id >= EMZ_RX_COPY_FALLBACK_COUNT) {
		net_buf_unref(frag);
		return NULL;
	}

	memcpy(emz_rx_copy_storage[id], rx->bytes, rx->len);
	net_buf_simple_init_with_data(&frag->b, emz_rx_copy_storage[id], rx->len);
	frag->flags = NET_BUF_EXTERNAL_DATA;

	ctx = net_buf_user_data(frag);
	ctx->in_use = true;

	return frag;
}
#endif

static uint32_t emz_read(const struct emaczero_config *cfg, uint32_t reg)
{
	return sys_read32(cfg->base + reg);
}

static void emz_write(const struct emaczero_config *cfg, uint32_t reg, uint32_t val)
{
	sys_write32(val, cfg->base + reg);
}

static uint32_t emz_speed_field(uint32_t speed)
{
	switch (speed) {
	case 10:
		return EMZ_SPEED_10M;
	case 1000:
		return EMZ_SPEED_1G;
	case 100:
	default:
		return EMZ_SPEED_100M;
	}
}

static void emz_set_mac(const struct emaczero_config *cfg, const uint8_t mac[NET_ETH_ADDR_LEN])
{
	uint32_t lo = ((uint32_t)mac[2] << 24) |
		      ((uint32_t)mac[3] << 16) |
		      ((uint32_t)mac[4] << 8) |
		      (uint32_t)mac[5];
	uint32_t hi = ((uint32_t)mac[0] << 8) | (uint32_t)mac[1];

	emz_write(cfg, EMZ_REG_MAC_LO, lo);
	emz_write(cfg, EMZ_REG_MAC_HI, hi);
}

static void emz_update_ctrl(const struct emaczero_config *cfg, uint32_t set, uint32_t clear)
{
	uint32_t ctrl = emz_read(cfg, EMZ_REG_CTRL);

	ctrl &= ~clear;
	ctrl |= set;
	emz_write(cfg, EMZ_REG_CTRL, ctrl);
}

static int emz_start(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;

	emz_update_ctrl(cfg, EMZ_CTRL_TX_EN | EMZ_CTRL_RX_EN, 0);
	return 0;
}

static int emz_stop(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;

	emz_update_ctrl(cfg, 0, EMZ_CTRL_TX_EN | EMZ_CTRL_RX_EN);
	return 0;
}

static enum ethernet_hw_caps emz_get_capabilities(const struct device *dev)
{
	ARG_UNUSED(dev);

	return ETHERNET_LINK_10BASE | ETHERNET_LINK_100BASE |
	       ETHERNET_LINK_1000BASE | ETHERNET_PROMISC_MODE;
}

static int emz_set_config(const struct device *dev, enum ethernet_config_type type,
			  const struct ethernet_config *config)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;

	switch (type) {
	case ETHERNET_CONFIG_TYPE_MAC_ADDRESS:
		memcpy(data->mac, config->mac_address.addr, NET_ETH_ADDR_LEN);
		emz_set_mac(cfg, data->mac);
		if (data->iface != NULL) {
			net_if_set_link_addr(data->iface, data->mac, NET_ETH_ADDR_LEN,
					     NET_LINK_ETHERNET);
		}
		return 0;
	case ETHERNET_CONFIG_TYPE_PROMISC_MODE:
		data->promisc = config->promisc_mode;
		emz_update_ctrl(cfg, data->promisc ? EMZ_CTRL_PROMISC : 0,
				data->promisc ? 0 : EMZ_CTRL_PROMISC);
		return 0;
	default:
		return -ENOTSUP;
	}
}

static int emz_get_config(const struct device *dev, enum ethernet_config_type type,
			  struct ethernet_config *config)
{
	struct emaczero_data *data = dev->data;

	switch (type) {
	case ETHERNET_CONFIG_TYPE_MAC_ADDRESS:
		memcpy(config->mac_address.addr, data->mac, NET_ETH_ADDR_LEN);
		return 0;
	case ETHERNET_CONFIG_TYPE_PROMISC_MODE:
		config->promisc_mode = data->promisc;
		return 0;
	default:
		return -ENOTSUP;
	}
}

static void emz_dma_rx_callback(const struct device *dma, void *user_data, uint32_t channel,
				int status)
{
	const struct device *dev = user_data;
	struct emaczero_data *data = dev->data;
	struct emaczero_rx_buffer *rx;
	k_spinlock_key_t key;
	uint32_t now_cycle = k_cycle_get_32();
	uint32_t start_cycle = now_cycle;

	ARG_UNUSED(channel);
	emz_perf_note_dma_callback_gap(data, now_cycle);
	emaczero_perf_stats.dma_callbacks++;
	EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_DMA_CALLBACKS);

	/* A negative status means S2MM halted. Completions reported after that
	 * are dropped: emz_dma_recover() reclaims every buffer still on
	 * rx_dma_fifo when it rebuilds the ring.
	 */
	if (status < 0) {
		LOG_ERR("DMA RX error: %d", status);
		emaczero_perf_stats.dma_errors++;
		EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_DMA_ERRORS);
		emz_dma_request_recover(data);
		return;
	}
	if (atomic_get(&data->dma_recover_pending) != 0) {
		return;
	}

	/* The DMA driver completes S2MM descriptors in ring order, and
	 * emz_refill_dma_rx() queues each buffer on rx_dma_fifo under rx_lock
	 * together with the dma_reload() that posts it, so the fifo head is the
	 * buffer this descriptor filled.
	 */
	key = k_spin_lock(&data->rx_lock);
	rx = k_fifo_get(&data->rx_dma_fifo, K_NO_WAIT);
	if (rx != NULL && data->rx_dma_inflight > 0u) {
		data->rx_dma_inflight--;
	}
	k_spin_unlock(&data->rx_lock, key);
	if (rx == NULL) {
		LOG_ERR("DMA RX completion without queued buffer");
		emaczero_perf_stats.dma_errors++;
		return;
	}
	atomic_dec(&data->rx_dma_fifo_count);
	emz_perf_update_pool_inflight(data);

	rx->status = status;
#if defined(CONFIG_DMA_XILINX_AXI_DMA)
	rx->len = dma_xilinx_axi_dma_last_received_frame_length(dma);
#else
	ARG_UNUSED(dma);
	rx->len = 0u;
#endif
	/* The transferred-length field is 26 bits, so an errored or stale
	 * descriptor can claim megabytes. Clamp before anyone sees it: the
	 * interceptor below runs in ISR context against a buffer of
	 * EMZ_ETH_BUFFER_SIZE bytes and does no bounds check of its own.
	 */
	if (rx->len == 0u || rx->len > EMZ_ETH_BUFFER_SIZE) {
		rx->len = MIN(rx->len, EMZ_ETH_BUFFER_SIZE);
		rx->status = -EFAULT;
		emaczero_perf_stats.rx_bd_errors++;
	}
	emz_dma_cache_invd(rx->bytes, rx->len);
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
	rx->dma_done_cycle = k_cycle_get_32();
#endif

	/* Frames the interceptor consumes never leave ISR context: the buffer
	 * goes straight back to S2MM without a trip through the RX thread.
	 */
	if (rx->status == DMA_STATUS_COMPLETE && data->rx_interceptor != NULL &&
	    data->rx_interceptor(rx->bytes, rx->len, data->rx_interceptor_user_data)) {
		emz_release_rx_buffer(dev, rx);
		EMZ_PROFILE_ADD_CYCLES(EMACZERO_PROFILE_CYCLES_DMA_CB,
				       emaczero_profile_elapsed(start_cycle, k_cycle_get_32()));
		return;
	}

#if defined(CONFIG_ETH_EMACZERO_PROFILE)
	if (emaczero_profile_get_mode() == EMACZERO_PROFILE_MODE_DROP_AFTER_DMA &&
	    !emaczero_profile_should_keep_control(rx->bytes, rx->len)) {
		EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_DMA_DROP_AFTER_DMA);
		emz_release_rx_buffer(dev, rx);
		EMZ_PROFILE_ADD_CYCLES(EMACZERO_PROFILE_CYCLES_DMA_CB,
				       emaczero_profile_elapsed(start_cycle, k_cycle_get_32()));
		return;
	}
#endif
	atomic_inc(&data->rx_ready_fifo_count);
	emz_perf_update_pool_inflight(data);
	k_fifo_put(&data->rx_ready_fifo, rx);
	EMZ_PROFILE_ADD_CYCLES(EMACZERO_PROFILE_CYCLES_DMA_CB,
			       emaczero_profile_elapsed(start_cycle, k_cycle_get_32()));
}

static void emz_dma_tx_callback(const struct device *dma, void *user_data, uint32_t channel,
				int status)
{
	const struct device *dev = user_data;
	struct emaczero_data *data = dev->data;

	ARG_UNUSED(dma);
	ARG_UNUSED(channel);

	/* MM2S halted. The slot accounting is rebuilt by emz_dma_recover(), so
	 * neither this report nor the frames lost with it return a slot here.
	 */
	if (status < 0) {
		LOG_ERR("DMA TX error: %d", status);
		eth_stats_update_errors_tx(data->iface);
		emaczero_perf_stats.tx_dma_error++;
		emz_dma_request_recover(data);
		return;
	}

	data->tx_completed_buffer_index =
		(data->tx_completed_buffer_index + 1u) % EMZ_DMA_BUFFER_COUNT_TX;
	emaczero_perf_stats.tx_dma_completed++;
	k_sem_give(&data->tx_slot_sem);
}

#if defined(CONFIG_ETH_EMACZERO_RX_DIRECT_RING)
static uint32_t emz_dma_read(const struct emaczero_config *cfg, uint32_t reg)
{
	return sys_read32(cfg->dma_base + reg);
}

static void emz_dma_write(const struct emaczero_config *cfg, uint32_t reg, uint32_t val)
{
	sys_write32(val, cfg->dma_base + reg);
}

static uint32_t emz_tx_direct_dmacr(void)
{
	return EMZ_AXI_DMA_DMACR_RS | EMZ_AXI_DMA_DMACR_IOC_IRQEN |
	       EMZ_AXI_DMA_DMACR_DLY_IRQEN | EMZ_AXI_DMA_DMACR_ERR_IRQEN |
	       (CONFIG_DMA_XILINX_AXI_DMA_INTERRUPT_THRESHOLD <<
		EMZ_AXI_DMA_DMACR_IRQTHRESH_SHIFT) |
	       (CONFIG_DMA_XILINX_AXI_DMA_INTERRUPT_TIMEOUT <<
		EMZ_AXI_DMA_DMACR_IRQDELAY_SHIFT);
}

static bool emz_rx_direct_enabled(const struct emaczero_config *cfg)
{
	return cfg->dma_base != 0u;
}

static int emz_tx_direct_start(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	uintptr_t bd_addr;

	data->tx_bd_ring = emz_sg_mem_alloc(64u,
					     sizeof(struct emaczero_rx_bd) *
					     EMZ_DMA_BUFFER_COUNT_TX);
	if (data->tx_bd_ring == NULL) {
		return -ENOMEM;
	}

	memset((void *)data->tx_bd_ring, 0,
	       sizeof(struct emaczero_rx_bd) * EMZ_DMA_BUFFER_COUNT_TX);
	data->tx_populated_buffer_index = 0u;
	data->tx_completed_buffer_index = 0u;
	data->tx_bd_inflight = 0u;
	for (size_t i = 0; i < EMZ_DMA_BUFFER_COUNT_TX; i++) {
		uintptr_t next = (uintptr_t)&data->tx_bd_ring[(i + 1u) %
							      EMZ_DMA_BUFFER_COUNT_TX];

		__ASSERT(((uintptr_t)&data->tx_bd_ring[i] & 0x3fu) == 0u,
			 "emacZero direct TX BD is not 64-byte aligned");
		data->tx_bd_ring[i].nxtdesc = (uint32_t)next;
	}
	bd_addr = (uintptr_t)data->tx_bd_ring;
	emz_dma_cache_flush((const void *)data->tx_bd_ring,
			    sizeof(struct emaczero_rx_bd) * EMZ_DMA_BUFFER_COUNT_TX);

	emz_dma_write(cfg, EMZ_AXI_DMA_REG_MM2S_DMASR, 0xffffffffu);
	emz_dma_write(cfg, EMZ_AXI_DMA_REG_MM2S_CURDESC, (uint32_t)bd_addr);
	barrier_dmem_fence_full();
	emz_dma_write(cfg, EMZ_AXI_DMA_REG_MM2S_DMACR, emz_tx_direct_dmacr());
	barrier_dmem_fence_full();
	data->dma_is_configured_tx = true;
	return 0;
}

static uint32_t emz_tx_direct_reclaim(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	uint32_t reclaimed = 0u;

	while (data->tx_bd_inflight > 0u) {
		size_t index = data->tx_completed_buffer_index;
		volatile struct emaczero_rx_bd *bd = &data->tx_bd_ring[index];
		uint32_t status;

		emz_dma_cache_invd((const void *)bd, sizeof(*bd));
		status = bd->status;
		if ((status & (EMZ_AXI_DMA_BD_STATUS_COMPLETE |
			       EMZ_AXI_DMA_BD_STATUS_ERROR_MASK)) == 0u) {
			break;
		}

		bd->control = 0u;
		bd->status = 0u;
		emz_dma_cache_flush((const void *)bd, sizeof(*bd));
		data->tx_completed_buffer_index =
			(index + 1u) % EMZ_DMA_BUFFER_COUNT_TX;
		data->tx_bd_inflight--;
		reclaimed++;

		if ((status & EMZ_AXI_DMA_BD_STATUS_ERROR_MASK) != 0u) {
			emaczero_perf_stats.tx_dma_error++;
			eth_stats_update_errors_tx(data->iface);
		} else {
			emaczero_perf_stats.tx_dma_completed++;
		}
	}

	emz_dma_write(cfg, EMZ_AXI_DMA_REG_MM2S_DMASR,
		      EMZ_AXI_DMA_DMASR_IRQ_ALL | EMZ_AXI_DMA_DMASR_ERROR_MASK);
	return reclaimed;
}

static int emz_tx_direct_reserve(const struct device *dev, size_t *descriptor)
{
	struct emaczero_data *data = dev->data;

	if (data->tx_bd_ring == NULL) {
		emaczero_perf_stats.tx_setup_no_dma++;
		emaczero_perf_stats.tx_last_ret = (uint32_t)-ENODEV;
		return -ENODEV;
	}

	(void)emz_tx_direct_reclaim(dev);
	for (uint32_t wait_us = 0u; data->tx_bd_inflight >= EMZ_DMA_BUFFER_COUNT_TX;
	     wait_us++) {
		if (wait_us >= 2000u) {
			emaczero_perf_stats.tx_setup_busy++;
			emaczero_perf_stats.tx_last_ret = (uint32_t)-ENOSPC;
			return -ENOSPC;
		}
		k_busy_wait(1);
		(void)emz_tx_direct_reclaim(dev);
	}

	*descriptor = data->tx_populated_buffer_index;
	return 0;
}

static int emz_setup_dma_tx_direct_transfer(const struct device *dev, size_t len)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	size_t current_descriptor = data->tx_populated_buffer_index;
	volatile struct emaczero_rx_bd *bd;

	if (data->tx_bd_ring == NULL) {
		emaczero_perf_stats.tx_setup_no_dma++;
		emaczero_perf_stats.tx_last_ret = (uint32_t)-ENODEV;
		return -ENODEV;
	}
	if (data->tx_bd_inflight >= EMZ_DMA_BUFFER_COUNT_TX) {
		emaczero_perf_stats.tx_setup_busy++;
		emaczero_perf_stats.tx_last_ret = (uint32_t)-ENOSPC;
		return -ENOSPC;
	}
	bd = &data->tx_bd_ring[current_descriptor];

	emaczero_perf_stats.tx_setup_calls++;
	emaczero_perf_stats.tx_last_len = len;
	emz_dma_cache_flush(data->tx_buffer[current_descriptor].bytes, len);

	bd->buffer_address = (uint32_t)(uintptr_t)data->tx_buffer[current_descriptor].bytes;
	bd->buffer_address_msb = 0u;
	bd->control = EMZ_AXI_DMA_BD_CTRL_SOF | EMZ_AXI_DMA_BD_CTRL_EOF |
		      (len & EMZ_AXI_DMA_BD_CTRL_LEN_MASK);
	bd->app0 = 0u;
	bd->app1 = 0u;
	bd->app2 = 0u;
	bd->app3 = 0u;
	bd->app4 = 0u;
	bd->status = 0u;
	emz_dma_cache_flush((const void *)bd, sizeof(*bd));

	barrier_dmem_fence_full();
	emz_dma_write(cfg, EMZ_AXI_DMA_REG_MM2S_TAILDESC, (uint32_t)(uintptr_t)bd);
	data->tx_populated_buffer_index =
		(current_descriptor + 1u) % EMZ_DMA_BUFFER_COUNT_TX;
	data->tx_bd_inflight++;
	emaczero_perf_stats.tx_dma_start_ok++;
	emaczero_perf_stats.tx_last_ret = 0u;
	return 0;
}

static void emz_rx_direct_program_bd(struct emaczero_data *data, size_t index,
				     struct emaczero_rx_buffer *rx)
{
	volatile struct emaczero_rx_bd *bd = &data->rx_bd_ring[index];

	emz_dma_cache_flush(rx->bytes, EMZ_ETH_BUFFER_SIZE);
	emz_dma_cache_invd(rx->bytes, EMZ_ETH_BUFFER_SIZE);

	/* Xilinx AXI DMA SG invariant: every BD from hardware CURDESC through
	 * TAILDESC inclusive must have a valid buffer pointer and Cmplt=0. Fill
	 * buffer/control first, clear status second, publish by writing TAILDESC
	 * last. Reordering these writes can make S2MM halt or fetch a stale BD.
	 */
	bd->buffer_address = (uint32_t)(uintptr_t)rx->bytes;
	bd->buffer_address_msb = 0u;
	bd->control = EMZ_ETH_BUFFER_SIZE & EMZ_AXI_DMA_BD_CTRL_LEN_MASK;
	bd->app0 = 0u;
	bd->app1 = 0u;
	bd->app2 = 0u;
	bd->app3 = 0u;
	bd->app4 = 0u;
	bd->status = 0u;
	data->rx_bd_buffer[index] = rx;
	emz_dma_cache_flush((const void *)&data->rx_bd_ring[index],
			    sizeof(data->rx_bd_ring[index]));
}

/* Publish the current refill position to S2MM TAILDESC.
 *
 * The index read and the register write must both happen under
 * rx_direct_lock. S2MM stops only when CURDESC reaches TAILDESC, so a
 * TAILDESC write that lands *behind* the engine re-opens BDs the driver has
 * already consumed and whose buffers now belong to the net stack or the free
 * FIFO — the engine would DMA over live data. Reading the index outside the
 * lock allows exactly that: a preempted thread can overwrite a newer tail
 * published by the ISR.
 */
static void emz_rx_direct_update_tail(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	k_spinlock_key_t key;
	uint32_t r7_tail_start;
	size_t index;

	key = k_spin_lock(&data->rx_direct_lock);
	if (!data->rx_direct_ring_started) {
		k_spin_unlock(&data->rx_direct_lock, key);
		return;
	}
	index = data->rx_bd_tail_index;

	r7_tail_start = k_cycle_get_32();
	barrier_dmem_fence_full();
	emz_dma_write(cfg, EMZ_AXI_DMA_REG_S2MM_TAILDESC,
		      (uint32_t)(uintptr_t)&data->rx_bd_ring[index]);
	k_spin_unlock(&data->rx_direct_lock, key);

	emz_r7_add(EMZ_R7_TAIL_CSR, emz_r7_elapsed(r7_tail_start, k_cycle_get_32()));
	emaczero_perf_stats.rx_bd_tail_updates++;
}

static int emz_rx_direct_post_one(const struct device *dev, struct emaczero_rx_buffer *rx)
{
	struct emaczero_data *data = dev->data;
	size_t index;
	k_spinlock_key_t key;
	uint32_t r7_post_start = k_cycle_get_32();

	key = k_spin_lock(&data->rx_direct_lock);
	emz_r7_note_lock();
	index = data->rx_bd_refill_index;
	if (data->rx_bd_buffer[index] != NULL) {
		k_spin_unlock(&data->rx_direct_lock, key);
		emz_r7_add(EMZ_R7_LOCK_POST, emz_r7_elapsed(r7_post_start, k_cycle_get_32()));
		emaczero_perf_stats.rx_bd_no_free++;
		return 0;
	}

	if (data->rx_dma_inflight >= EMZ_DMA_RX_MAX_INFLIGHT) {
		k_spin_unlock(&data->rx_direct_lock, key);
		emz_r7_add(EMZ_R7_LOCK_POST, emz_r7_elapsed(r7_post_start, k_cycle_get_32()));
		return 0;
	}
	data->rx_dma_inflight++;
	emz_perf_set_max_u32(&emaczero_perf_stats.rx_max_dma_inflight,
			      data->rx_dma_inflight);
	EMZ_PROFILE_MAX(EMACZERO_PROFILE_MAX_RX_DMA_INFLIGHT, data->rx_dma_inflight);

	emz_rx_direct_program_bd(data, index, rx);
	data->rx_bd_posted++;
	emz_perf_set_bd_available(data);
	emaczero_perf_stats.rx_bd_refilled++;

	data->rx_bd_refill_index = (index + 1u) % EMZ_DMA_BUFFER_COUNT_RX;
	data->rx_bd_tail_index = index;
	k_spin_unlock(&data->rx_direct_lock, key);
	emz_r7_add(EMZ_R7_LOCK_POST, emz_r7_elapsed(r7_post_start, k_cycle_get_32()));

	atomic_inc(&data->rx_dma_fifo_count);
	emz_perf_update_pool_inflight(data);
	return 1;
}

static int emz_rx_direct_refill(const struct device *dev)
{
	struct emaczero_data *data = dev->data;
	int queued = 0;

	while (true) {
		struct emaczero_rx_buffer *rx = k_fifo_get(&data->rx_free_fifo, K_NO_WAIT);
		int ret;

		if (rx == NULL) {
			emaczero_perf_stats.rx_refill_no_free++;
			emaczero_perf_stats.rx_bd_no_free++;
			EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_REFILL_NO_FREE);
			break;
		}

		ret = emz_rx_direct_post_one(dev, rx);
		if (ret <= 0) {
			k_fifo_put(&data->rx_free_fifo, rx);
			break;
		}

		atomic_dec(&data->rx_free_count);
		emz_perf_update_pool_inflight(data);
		emz_perf_set_min_u32(&emaczero_perf_stats.rx_min_free,
				      (uint32_t)atomic_get(&data->rx_free_count));
		EMZ_PROFILE_MIN(EMACZERO_PROFILE_MIN_RX_FREE, (uint32_t)atomic_get(&data->rx_free_count));
		queued++;
		emaczero_perf_stats.rx_refill_queued++;
		EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_REFILL_QUEUED);
	}

	if (queued > 0) {
		emz_rx_direct_update_tail(dev);
	}

	return queued;
}

/* Queue one ring rebuild; collapses repeated requests (e.g. the interrupt
 * storm from a halted engine) into a single pass.
 */
static void emz_rx_direct_request_recover(struct emaczero_data *data)
{
	if (atomic_cas(&data->rx_direct_recover_pending, 0, 1)) {
		(void)k_work_submit(&data->rx_direct_recover_work);
	}
}

static void emz_rx_direct_poll(const struct device *dev)
{
	struct emaczero_data *data = dev->data;
	uint32_t completed = 0u;

	while (true) {
		size_t index;
		volatile struct emaczero_rx_bd *bd;
		struct emaczero_rx_buffer *rx;
		uint32_t status;
		k_spinlock_key_t key;
		uint32_t r7_lock_start;

		r7_lock_start = k_cycle_get_32();
		key = k_spin_lock(&data->rx_direct_lock);
		emz_r7_note_lock();
		index = data->rx_bd_consume_index;
		bd = &data->rx_bd_ring[index];
		rx = data->rx_bd_buffer[index];
		emz_dma_cache_invd((const void *)&data->rx_bd_ring[index],
				   sizeof(data->rx_bd_ring[index]));
		status = bd->status;
		if ((status & (EMZ_AXI_DMA_BD_STATUS_COMPLETE |
			       EMZ_AXI_DMA_BD_STATUS_ERROR_MASK)) == 0u) {
			k_spin_unlock(&data->rx_direct_lock, key);
			emz_r7_add(EMZ_R7_LOCK_CONSUME,
				   emz_r7_elapsed(r7_lock_start, k_cycle_get_32()));
			break;
		}

		if (rx == NULL) {
			/* Consumed BDs are retired with status cleared (below), and
			 * program_bd records the buffer before TAILDESC can expose
			 * the slot, so Cmplt on a slot with no buffer means S2MM
			 * wrote a BD it never owned. The ring's ownership state is
			 * no longer trustworthy: skipping the slot would move the
			 * consume index past refill and strand in-flight buffers.
			 * Stop here and let the recovery pass rebuild the ring.
			 */
			k_spin_unlock(&data->rx_direct_lock, key);
			emz_r7_add(EMZ_R7_LOCK_CONSUME,
				   emz_r7_elapsed(r7_lock_start, k_cycle_get_32()));
			emaczero_perf_stats.rx_bd_errors++;
			emz_rx_direct_request_recover(data);
			break;
		}

		/* Retire the slot: clear Cmplt so a drained ring (consume ==
		 * refill) reads as idle rather than as a stale completion. The
		 * slot sits behind CURDESC, so the engine no longer owns it.
		 */
		bd->status = 0u;
		emz_dma_cache_flush((const void *)&data->rx_bd_ring[index],
				    sizeof(data->rx_bd_ring[index]));
		data->rx_bd_buffer[index] = NULL;
		data->rx_bd_posted--;
		emz_perf_set_bd_available(data);
		data->rx_bd_consume_index = (index + 1u) % EMZ_DMA_BUFFER_COUNT_RX;

		if (data->rx_dma_inflight > 0u) {
			data->rx_dma_inflight--;
		}
		k_spin_unlock(&data->rx_direct_lock, key);
		emz_r7_add(EMZ_R7_LOCK_CONSUME,
			   emz_r7_elapsed(r7_lock_start, k_cycle_get_32()));
		atomic_dec(&data->rx_dma_fifo_count);

		rx->status = (status & EMZ_AXI_DMA_BD_STATUS_ERROR_MASK) != 0u ? -EFAULT :
			     DMA_STATUS_COMPLETE;
		/* The transferred-length field is 26 bits, so a corrupt or stale
		 * status word can claim megabytes. Clamp before anyone sees it:
		 * the interceptor below runs in ISR context against a
		 * 1518-byte buffer and does no bounds check of its own.
		 */
		rx->len = status & EMZ_AXI_DMA_BD_STATUS_LEN_MASK;
		if (rx->len > EMZ_ETH_BUFFER_SIZE) {
			rx->len = EMZ_ETH_BUFFER_SIZE;
			rx->status = -EFAULT;
			emaczero_perf_stats.rx_bd_errors++;
		}
		emz_dma_cache_invd(rx->bytes, rx->len);
		if (rx->status == DMA_STATUS_COMPLETE && data->rx_interceptor != NULL &&
		    data->rx_interceptor(rx->bytes, rx->len, data->rx_interceptor_user_data)) {
			emz_release_rx_buffer(dev, rx);
			emaczero_perf_stats.dma_callbacks++;
			EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_DMA_CALLBACKS);
			emaczero_perf_stats.rx_bd_hw_completed++;
			completed++;
			continue;
		}
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
		rx->dma_done_cycle = k_cycle_get_32();
		if (emaczero_profile_get_mode() == EMACZERO_PROFILE_MODE_DROP_AFTER_DMA &&
		    !emaczero_profile_should_keep_control(rx->bytes, rx->len)) {
			bool rx_error = rx->status < 0;

			EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_DMA_DROP_AFTER_DMA);
			emz_release_rx_buffer(dev, rx);
			emaczero_perf_stats.dma_callbacks++;
			EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_DMA_CALLBACKS);
			emaczero_perf_stats.rx_bd_hw_completed++;
			if (rx_error) {
				emaczero_perf_stats.dma_errors++;
				emaczero_perf_stats.rx_bd_errors++;
			}
			completed++;
			continue;
		}
#endif
		{
			uint32_t r7_enq_start = k_cycle_get_32();
			atomic_inc(&data->rx_ready_fifo_count);
			k_fifo_put(&data->rx_ready_fifo, rx);
			emz_r7_add(EMZ_R7_READY_ENQUEUE,
				   emz_r7_elapsed(r7_enq_start, k_cycle_get_32()));
		}
		emz_perf_update_pool_inflight(data);

		emaczero_perf_stats.dma_callbacks++;
		EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_DMA_CALLBACKS);
		emaczero_perf_stats.rx_bd_hw_completed++;
		if (rx->status < 0) {
			emaczero_perf_stats.dma_errors++;
			emaczero_perf_stats.rx_bd_errors++;
		}
		completed++;
	}

	emz_perf_set_max_u32(&emaczero_perf_stats.rx_poll_completed_max, completed);
	if (completed != 0u) {
		(void)emz_refill_dma_rx(dev);
	}
}

static void emz_rx_direct_poll_work_handler(struct k_work *work)
{
	struct k_work_delayable *dwork = k_work_delayable_from_work(work);
	struct emaczero_data *data =
		CONTAINER_OF(dwork, struct emaczero_data, rx_direct_poll_work);

	if (data->rx_direct_ring_started && data->dev != NULL) {
		emz_rx_direct_poll(data->dev);
	}

	(void)k_work_reschedule(&data->rx_direct_poll_work, K_MSEC(1));
}

/* Reset S2MM and (re)start it on the current ring. Callers own
 * irq_disable/irq_enable. RS alone does not fetch in SG mode; the TAILDESC
 * write does, so it is only issued when at least one BD is posted.
 */
static void emz_rx_direct_arm(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	k_spinlock_key_t key;
	uint32_t dmacr;

	emz_dma_write(cfg, EMZ_AXI_DMA_REG_S2MM_DMACR, EMZ_AXI_DMA_DMACR_RESET);
	k_busy_wait(10);
	emz_dma_write(cfg, EMZ_AXI_DMA_REG_S2MM_DMASR, 0xffffffffu);
	emz_dma_write(cfg, EMZ_AXI_DMA_REG_S2MM_CURDESC,
		      (uint32_t)(uintptr_t)&data->rx_bd_ring[data->rx_bd_consume_index]);
	barrier_dmem_fence_full();
	/* Coalesce IOC interrupts across up to 32 completions to amortise ISR
	 * cost. Enable Dly_IrqEn with a short delay so bursts smaller than the
	 * threshold still get serviced quickly. IRQDelay unit = 125 SG cycles;
	 * at 81.25 MHz that is ~1.54 us, so 32 = ~50 us of idle before wakeup.
	 */
	dmacr = EMZ_AXI_DMA_DMACR_RS | EMZ_AXI_DMA_DMACR_IOC_IRQEN |
		EMZ_AXI_DMA_DMACR_DLY_IRQEN | EMZ_AXI_DMA_DMACR_ERR_IRQEN |
		(32u << EMZ_AXI_DMA_DMACR_IRQTHRESH_SHIFT) |
		(32u << EMZ_AXI_DMA_DMACR_IRQDELAY_SHIFT);
	emz_dma_write(cfg, EMZ_AXI_DMA_REG_S2MM_DMACR, dmacr);
	barrier_dmem_fence_full();

	/* An empty ring leaves tail_index on an unprogrammed BD, and CURDESC ==
	 * TAILDESC still processes that one BD: the engine would fetch an
	 * invalid descriptor, halt, and re-trigger recovery until a buffer
	 * came back. Arm without a tail instead; the first refill publishes it
	 * through emz_rx_direct_update_tail(). Checking posted under the lock
	 * also catches a refill that ran while ring_started was still false.
	 */
	key = k_spin_lock(&data->rx_direct_lock);
	data->rx_direct_ring_started = true;
	if (data->rx_bd_posted > 0u) {
		emz_dma_write(cfg, EMZ_AXI_DMA_REG_S2MM_TAILDESC,
			      (uint32_t)(uintptr_t)&data->rx_bd_ring[data->rx_bd_tail_index]);
		emaczero_perf_stats.rx_bd_tail_updates++;
	}
	k_spin_unlock(&data->rx_direct_lock, key);
}

/* Rebuild the RX ring after S2MM halted on a DMA/SG error.
 *
 * A halted engine never restarts on its own, so without this the first
 * DMADecErr/DMASlvErr takes RX down until reboot. Runs from the system work
 * queue, not the ISR: the reset sequence busy-waits.
 */
static void emz_rx_direct_recover(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	struct emaczero_rx_buffer *orphans[EMZ_DMA_BUFFER_COUNT_RX];
	size_t orphan_count = 0u;
	k_spinlock_key_t key;

	irq_disable(cfg->dma_rx_irq);

	/* Stop the engine before touching the ring: a halted S2MM may still be
	 * mid-writeback on the BD it faulted on.
	 */
	emz_dma_write(cfg, EMZ_AXI_DMA_REG_S2MM_DMACR, EMZ_AXI_DMA_DMACR_RESET);
	k_busy_wait(10);
	emz_dma_write(cfg, EMZ_AXI_DMA_REG_S2MM_DMASR, 0xffffffffu);
	barrier_dmem_fence_full();

	key = k_spin_lock(&data->rx_direct_lock);
	data->rx_direct_ring_started = false;
	for (size_t i = 0; i < EMZ_DMA_BUFFER_COUNT_RX; i++) {
		if (data->rx_bd_buffer[i] != NULL) {
			orphans[orphan_count] = data->rx_bd_buffer[i];
			orphan_count++;
			data->rx_bd_buffer[i] = NULL;
		}
		data->rx_bd_ring[i].status = 0u;
		data->rx_bd_ring[i].control = 0u;
	}
	data->rx_bd_consume_index = 0u;
	data->rx_bd_refill_index = 0u;
	data->rx_bd_tail_index = 0u;
	data->rx_bd_posted = 0u;
	data->rx_dma_inflight = 0u;
	emz_perf_set_bd_available(data);
	k_spin_unlock(&data->rx_direct_lock, key);

	emz_dma_cache_flush((const void *)data->rx_bd_ring,
			    sizeof(struct emaczero_rx_bd) * EMZ_DMA_BUFFER_COUNT_RX);

	/* Return every buffer the engine still owned to the free pool. Done
	 * outside the lock and without emz_release_rx_buffer(), which would
	 * re-enter the refill path mid-rebuild.
	 */
	atomic_sub(&data->rx_dma_fifo_count, (atomic_val_t)orphan_count);
	for (size_t i = 0; i < orphan_count; i++) {
		atomic_inc(&data->rx_free_count);
		k_fifo_put(&data->rx_free_fifo, orphans[i]);
	}
	emz_perf_update_pool_inflight(data);

	/* Repopulate before arming. If the pool is momentarily empty the ring
	 * comes up bare and untailed; the next buffer release refills and
	 * publishes the tail through the normal path.
	 */
	(void)emz_rx_direct_refill(dev);
	emz_rx_direct_arm(dev);
	irq_enable(cfg->dma_rx_irq);

	emaczero_perf_stats.rx_dma_recoveries++;
	atomic_clear(&data->rx_direct_recover_pending);
}

static void emz_rx_direct_recover_work_handler(struct k_work *work)
{
	struct emaczero_data *data =
		CONTAINER_OF(work, struct emaczero_data, rx_direct_recover_work);

	if (data->dev != NULL) {
		emz_rx_direct_recover(data->dev);
	} else {
		atomic_clear(&data->rx_direct_recover_pending);
	}
}

static void emz_rx_direct_isr(const void *arg)
{
	const struct device *dev = arg;
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	uint32_t now_cycle = k_cycle_get_32();
	uint32_t r7_isr_start = now_cycle;
	uint32_t dmasr = emz_dma_read(cfg, EMZ_AXI_DMA_REG_S2MM_DMASR);

	emaczero_perf_stats.rx_irq_count++;
	emz_perf_note_dma_callback_gap(data, now_cycle);
	if ((dmasr & EMZ_AXI_DMA_DMASR_ERROR_MASK) != 0u) {
		emaczero_perf_stats.dma_errors++;
		emaczero_perf_stats.rx_bd_errors++;

		/* An error halts S2MM (RS clears). Clearing the status bits does
		 * not restart it, so hand off to the work queue for a full ring
		 * rebuild. The flag collapses the interrupt storm a halted
		 * engine produces into a single recovery pass.
		 */
		if ((dmasr & EMZ_AXI_DMA_DMASR_HALTED) != 0u) {
			emz_rx_direct_request_recover(data);
		}
	}

	/* Acknowledge the edge-causing IRQ before walking completed BDs. At
	 * high packet rates, clearing DMASR after polling can erase a completion
	 * that arrived during the poll/refill window and leave S2MM parked at the
	 * published tail until another interrupt source happens to fire.
	 */
	emz_dma_write(cfg, EMZ_AXI_DMA_REG_S2MM_DMASR,
		      dmasr & (EMZ_AXI_DMA_DMASR_IRQ_ALL |
			       EMZ_AXI_DMA_DMASR_ERROR_MASK));
	barrier_dmem_fence_full();
	emz_rx_direct_poll(dev);
	barrier_dmem_fence_full();
	emz_r7_add(EMZ_R7_ISR_TOTAL, emz_r7_elapsed(r7_isr_start, k_cycle_get_32()));
}

static int emz_rx_direct_start(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	int queued;

	data->rx_bd_ring = emz_sg_mem_alloc(64u,
					     sizeof(struct emaczero_rx_bd) *
					     EMZ_DMA_BUFFER_COUNT_RX);
	if (data->rx_bd_ring == NULL) {
		return -ENOMEM;
	}
	memset((void *)data->rx_bd_ring, 0,
	       sizeof(struct emaczero_rx_bd) * EMZ_DMA_BUFFER_COUNT_RX);
	for (size_t i = 0; i < EMZ_DMA_BUFFER_COUNT_RX; i++) {
		uintptr_t next = (uintptr_t)&data->rx_bd_ring[(i + 1u) % EMZ_DMA_BUFFER_COUNT_RX];

		__ASSERT(((uintptr_t)&data->rx_bd_ring[i] & 0x3fu) == 0u,
			 "emacZero direct RX BD is not 64-byte aligned");
		data->rx_bd_ring[i].nxtdesc = (uint32_t)next;
	}
	emz_dma_cache_flush((const void *)data->rx_bd_ring,
			    sizeof(struct emaczero_rx_bd) * EMZ_DMA_BUFFER_COUNT_RX);

	emaczero_perf_stats.rx_bd_available_min = UINT32_MAX;
	emz_perf_set_bd_available(data);

	queued = emz_rx_direct_refill(dev);
	if (queued <= 0) {
		return queued < 0 ? queued : -ENOSPC;
	}

	irq_disable(cfg->dma_rx_irq);
	emz_rx_direct_arm(dev);
	irq_enable(cfg->dma_rx_irq);
	(void)k_work_schedule(&data->rx_direct_poll_work, K_MSEC(1));
	return queued;
}
#else
static bool emz_rx_direct_enabled(const struct emaczero_config *cfg)
{
	ARG_UNUSED(cfg);
	return false;
}

static int emz_setup_dma_tx_direct_transfer(const struct device *dev, size_t len)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(len);
	return -ENOTSUP;
}

static int emz_tx_direct_reserve(const struct device *dev, size_t *descriptor)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(descriptor);
	return -ENOTSUP;
}
#endif

/* Post one buffer to S2MM without publishing it: the descriptor only becomes
 * visible to the engine at the next dma_start() (TAILDESC write). Caller holds
 * rx_lock so the descriptor and the rx_dma_fifo entry naming its buffer appear
 * together to the completion callback. emz_dma_recover() is the exception: it
 * posts while the engine is halted and the callback stands down.
 */
static int emz_post_dma_rx_buffer(const struct device *dev, struct emaczero_rx_buffer *rx)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	int ret;

	if (!data->dma_is_configured_rx) {
		struct dma_block_config block = {
			.source_address = 0u,
			.dest_address = (uintptr_t)rx->bytes,
			.block_size = EMZ_ETH_BUFFER_SIZE,
			.source_addr_adj = DMA_ADDR_ADJ_INCREMENT,
			.dest_addr_adj = DMA_ADDR_ADJ_INCREMENT,
		};
		struct dma_config dma_cfg = {
			.dma_slot = 0,
			.channel_direction = PERIPHERAL_TO_MEMORY,
			.complete_callback_en = 1,
			.error_callback_dis = 0,
			.block_count = 1,
			.head_block = &block,
			.user_data = (void *)dev,
			.dma_callback = emz_dma_rx_callback,
			.linked_channel = EMZ_DMA_LINKED_CHANNEL_NO_CSUM_OFFLOAD,
		};

		emaczero_perf_stats.rx_dma_config_calls++;
		ret = dma_config(cfg->dma, EMZ_DMA_RX_CHANNEL, &dma_cfg);
		if (ret != 0) {
			emaczero_perf_stats.rx_dma_config_fail++;
			return ret;
		}
		data->dma_is_configured_rx = true;
	} else {
		emaczero_perf_stats.rx_dma_reload_calls++;
		ret = dma_reload(cfg->dma, EMZ_DMA_RX_CHANNEL, 0u,
				 (uintptr_t)rx->bytes, EMZ_ETH_BUFFER_SIZE);
		if (ret != 0) {
			emaczero_perf_stats.rx_dma_reload_fail++;
			return ret;
		}
	}

	emz_dma_cache_flush(rx->bytes, EMZ_ETH_BUFFER_SIZE);
	emz_dma_cache_invd(rx->bytes, EMZ_ETH_BUFFER_SIZE);

	k_fifo_put(&data->rx_dma_fifo, rx);
	atomic_inc(&data->rx_dma_fifo_count);
	emz_perf_update_pool_inflight(data);
	return 0;
}

static int emz_refill_dma_rx(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	uint32_t start_cycle = k_cycle_get_32();
	k_spinlock_key_t key;
	int queued = 0;
	int err = 0;

	EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_REFILL_CALLS);
	emaczero_perf_stats.rx_refill_calls++;
#if defined(CONFIG_ETH_EMACZERO_RX_DIRECT_RING)
	if (emz_rx_direct_enabled(cfg)) {
		queued = emz_rx_direct_refill(dev);
		goto out;
	}
#endif
	if (cfg->dma == NULL) {
		return -ENODEV;
	}

	/* Refills run from threads (buffer release) and from the RX completion
	 * callback (interceptor release) and can interleave. Holding rx_lock
	 * across the whole batch, dma_start() included, keeps every TAILDESC
	 * write strictly ahead of the previous one and covering only buffers
	 * already on rx_dma_fifo.
	 */
	key = k_spin_lock(&data->rx_lock);
	/* Mid-recovery, freed buffers wait on rx_free_fifo: emz_dma_recover()
	 * restarts the ring itself once the core is reset.
	 */
	if (atomic_get(&data->dma_recover_pending) != 0) {
		k_spin_unlock(&data->rx_lock, key);
		return 0;
	}
	while (data->rx_dma_inflight < EMZ_DMA_RX_MAX_INFLIGHT) {
		struct emaczero_rx_buffer *rx = k_fifo_get(&data->rx_free_fifo, K_NO_WAIT);

		if (rx == NULL) {
			emaczero_perf_stats.rx_refill_no_free++;
			EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_REFILL_NO_FREE);
			break;
		}
		atomic_dec(&data->rx_free_count);
		emz_perf_set_min_u32(&emaczero_perf_stats.rx_min_free,
				      (uint32_t)atomic_get(&data->rx_free_count));
		EMZ_PROFILE_MIN(EMACZERO_PROFILE_MIN_RX_FREE, (uint32_t)atomic_get(&data->rx_free_count));

		err = emz_post_dma_rx_buffer(dev, rx);
		if (err != 0) {
			atomic_inc(&data->rx_free_count);
			k_fifo_put(&data->rx_free_fifo, rx);
			emz_perf_update_pool_inflight(data);
			break;
		}
		data->rx_dma_inflight++;
		emz_perf_set_max_u32(&emaczero_perf_stats.rx_max_dma_inflight,
				      data->rx_dma_inflight);
		EMZ_PROFILE_MAX(EMACZERO_PROFILE_MAX_RX_DMA_INFLIGHT, data->rx_dma_inflight);
		queued++;
		emaczero_perf_stats.rx_refill_queued++;
		EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_REFILL_QUEUED);
	}
	if (queued > 0) {
		int ret;

		emaczero_perf_stats.rx_dma_start_calls++;
		ret = dma_start(cfg->dma, EMZ_DMA_RX_CHANNEL);
		if (ret != 0) {
			emaczero_perf_stats.rx_dma_start_fail++;
			err = err != 0 ? err : ret;
		}
	}
	k_spin_unlock(&data->rx_lock, key);
	if (err != 0) {
		return err;
	}

#if defined(CONFIG_ETH_EMACZERO_RX_DIRECT_RING)
out:
#endif
	emz_perf_set_max_u32(&emaczero_perf_stats.rx_refill_queued_max, (uint32_t)queued);
	if (queued > 0) {
		uint32_t refill_cycles = k_cycle_get_32() - start_cycle;

		emz_perf_set_max_u32(&emaczero_perf_stats.rx_refill_cycles_max,
				      refill_cycles);
		if (refill_cycles >= (sys_clock_hw_cycles_per_sec() / 1000u)) {
			emaczero_perf_stats.rx_refill_cycles_ge_1ms++;
		}
	}

	return queued;
}

/* Rebuild both DMA channels after either one reported a halt.
 *
 * An AXI DMA error halts the channel until dma_stop() and then dma_config(),
 * whose soft reset covers the whole core and sleeps. So this runs from the
 * system work queue and rebuilds TX and RX together. Refill and the RX
 * callback stand down while dma_recover_pending is set.
 */
static void emz_dma_recover(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	struct emaczero_rx_buffer *rx;
	unsigned int reclaimed = 0u;
	k_spinlock_key_t key;
	int ret;

	/* tx_lock keeps senders off MM2S. One blocked in emz_tx_reserve() gives
	 * up within EMZ_TX_SLOT_TIMEOUT: a halted MM2S returns no slots.
	 */
	k_mutex_lock(&data->tx_lock, K_FOREVER);
	(void)dma_stop(cfg->dma, EMZ_DMA_RX_CHANNEL);
	(void)dma_stop(cfg->dma, EMZ_DMA_TX_CHANNEL);

	/* Frames posted to MM2S are lost. The next send re-runs dma_config(),
	 * which rebuilds the TX ring once the core is reset.
	 */
	data->dma_is_configured_tx = false;
	data->tx_populated_buffer_index = 0u;
	data->tx_completed_buffer_index = 0u;
	k_sem_reset(&data->tx_slot_sem);
	for (unsigned int i = 0u; i < EMZ_TX_SLOTS; i++) {
		k_sem_give(&data->tx_slot_sem);
	}

	/* Take back every buffer still posted to S2MM. Nothing draws on the
	 * pool while refill is gated, and the soft reset in dma_config() below
	 * completes before any of these is posted again.
	 */
	key = k_spin_lock(&data->rx_lock);
	while ((rx = k_fifo_get(&data->rx_dma_fifo, K_NO_WAIT)) != NULL) {
		k_fifo_put(&data->rx_free_fifo, rx);
		reclaimed++;
	}
	data->rx_dma_inflight = 0u;
	data->dma_is_configured_rx = false;
	k_spin_unlock(&data->rx_lock, key);
	atomic_sub(&data->rx_dma_fifo_count, (atomic_val_t)reclaimed);
	atomic_add(&data->rx_free_count, (atomic_val_t)reclaimed);
	emz_perf_update_pool_inflight(data);

	/* dma_config() needs a first buffer. If the stack holds all of them,
	 * try again once some come back.
	 */
	rx = k_fifo_get(&data->rx_free_fifo, K_NO_WAIT);
	if (rx == NULL) {
		goto retry;
	}
	atomic_dec(&data->rx_free_count);

	/* Soft reset and ring rebuild happen here. No rx_lock: it may sleep,
	 * and refill and the RX callback are idle until the flag clears.
	 */
	ret = emz_post_dma_rx_buffer(dev, rx);
	if (ret != 0) {
		atomic_inc(&data->rx_free_count);
		k_fifo_put(&data->rx_free_fifo, rx);
		goto retry;
	}
	data->rx_dma_inflight = 1u;
	k_mutex_unlock(&data->tx_lock);

	emaczero_perf_stats.rx_dma_recoveries++;
	atomic_clear(&data->dma_recover_pending);
	(void)emz_refill_dma_rx(dev);
	return;

retry:
	emz_perf_update_pool_inflight(data);
	k_mutex_unlock(&data->tx_lock);
	(void)k_work_reschedule(&data->dma_recover_work, K_MSEC(1));
}

static void emz_dma_recover_work_handler(struct k_work *work)
{
	struct k_work_delayable *dwork = k_work_delayable_from_work(work);
	struct emaczero_data *data =
		CONTAINER_OF(dwork, struct emaczero_data, dma_recover_work);

	emz_dma_recover(data->dev);
}

/* Callable from the DMA ISR: the first report schedules one recovery pass,
 * and later ones fold into it.
 */
static void emz_dma_request_recover(struct emaczero_data *data)
{
	if (atomic_cas(&data->dma_recover_pending, 0, 1)) {
		(void)k_work_reschedule(&data->dma_recover_work, K_NO_WAIT);
	}
}

static uint32_t emz_sample_word(const uint8_t *bytes, size_t len, size_t offset);

static uint16_t emz_sample_be16(const uint8_t *bytes, size_t len, size_t offset)
{
	if (offset + 1u >= len) {
		return 0u;
	}

	return ((uint16_t)bytes[offset] << 8) | bytes[offset + 1u];
}

static uint32_t emz_sample_be32(const uint8_t *bytes, size_t len, size_t offset)
{
	if (offset + 3u >= len) {
		return 0u;
	}

	return ((uint32_t)bytes[offset] << 24) | ((uint32_t)bytes[offset + 1u] << 16) |
	       ((uint32_t)bytes[offset + 2u] << 8) | bytes[offset + 3u];
}

static void emz_note_tx_icmp(const uint8_t *frame, size_t len)
{
	size_t ihl;
	size_t icmp;

	if (len < 42u || emz_sample_be16(frame, len, 12u) != EMZ_ETH_TYPE_IPV4 ||
	    (frame[14] >> 4) != 4u) {
		return;
	}

	ihl = (size_t)(frame[14] & 0x0fu) * 4u;
	icmp = 14u + ihl;
	if (ihl < 20u || len < icmp + 8u || frame[23] != EMZ_IP_PROTO_ICMP) {
		return;
	}

	emaczero_perf_stats.tx_last_icmp_src = emz_sample_be32(frame, len, 26u);
	emaczero_perf_stats.tx_last_icmp_dst = emz_sample_be32(frame, len, 30u);
	emaczero_perf_stats.tx_last_icmp_id = emz_sample_be16(frame, len, icmp + 4u);
	emaczero_perf_stats.tx_last_icmp_seq = emz_sample_be16(frame, len, icmp + 6u);
}

/* Point C in the four-point trace: the bytes about to be handed to MM2S,
 * exactly as the sender produced them.
 */
static void emz_note_tx_frame(const uint8_t *frame, size_t len)
{
	volatile uint32_t *txw = &emaczero_perf_stats.tx_ext_word0;

	emaczero_perf_stats.tx_last_len = len;
	emaczero_perf_stats.tx_last_word0 = emz_sample_word(frame, len, 0u);
	emaczero_perf_stats.tx_last_word1 = emz_sample_word(frame, len, 4u);
	emaczero_perf_stats.tx_last_word2 = emz_sample_word(frame, len, 8u);
	emaczero_perf_stats.tx_last_word3 = emz_sample_word(frame, len, 12u);
	emaczero_perf_stats.tx_ext_len = (uint32_t)len;
	for (size_t i = 0; i < 16u; i++) {
		txw[i] = emz_sample_word(frame, len, i * 4u);
	}
}

/* Post one MM2S descriptor for bytes[0..len) and advance the slot index. The
 * descriptor reaches the engine at the next dma_start(). Caller holds tx_lock
 * and has reserved a TX slot.
 */
static int emz_post_dma_tx(const struct device *dev, const uint8_t *bytes, size_t len)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	int ret;

	emz_dma_cache_flush(bytes, len);
	if (!data->dma_is_configured_tx) {
		struct dma_block_config block = {
			.source_address = (uintptr_t)bytes,
			.dest_address = 0u,
			.block_size = len,
			.source_addr_adj = DMA_ADDR_ADJ_INCREMENT,
			.dest_addr_adj = DMA_ADDR_ADJ_INCREMENT,
		};
		struct dma_config dma_cfg = {
			.dma_slot = 0,
			.channel_direction = MEMORY_TO_PERIPHERAL,
			.complete_callback_en = 1,
			.error_callback_dis = 0,
			.block_count = 1,
			.head_block = &block,
			.user_data = (void *)dev,
			.dma_callback = emz_dma_tx_callback,
			.linked_channel = EMZ_DMA_LINKED_CHANNEL_NO_CSUM_OFFLOAD,
		};

		ret = dma_config(cfg->dma, EMZ_DMA_TX_CHANNEL, &dma_cfg);
		if (ret != 0) {
			emaczero_perf_stats.tx_dma_config_fail++;
			return ret;
		}
		data->dma_is_configured_tx = true;
	} else {
		ret = dma_reload(cfg->dma, EMZ_DMA_TX_CHANNEL, (uintptr_t)bytes, 0u, len);
		if (ret != 0) {
			emaczero_perf_stats.tx_dma_reload_fail++;
			return ret;
		}
	}

	data->tx_populated_buffer_index =
		(data->tx_populated_buffer_index + 1u) % EMZ_DMA_BUFFER_COUNT_TX;
	return 0;
}

/* Claim the next TX slot (and its buffer) for the caller to fill. Caller
 * holds tx_lock. Slots come back from the MM2S completion callback, so a full
 * ring drains within a few frame times: wait for one instead of failing.
 */
static int emz_tx_reserve(const struct device *dev, size_t *descriptor)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;

	if (emz_rx_direct_enabled(cfg)) {
		return emz_tx_direct_reserve(dev, descriptor);
	}
	if (cfg->dma == NULL) {
		emaczero_perf_stats.tx_setup_no_dma++;
		emaczero_perf_stats.tx_last_ret = (uint32_t)-ENODEV;
		return -ENODEV;
	}
	if (k_sem_take(&data->tx_slot_sem, EMZ_TX_SLOT_TIMEOUT) != 0) {
		emaczero_perf_stats.tx_setup_busy++;
		emaczero_perf_stats.tx_last_ret = (uint32_t)-ENOSPC;
		return -ENOSPC;
	}

	*descriptor = data->tx_populated_buffer_index;
	return 0;
}

/* Hand back a slot from emz_tx_reserve() that was never posted. */
static void emz_tx_unreserve(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;

	if (!emz_rx_direct_enabled(cfg)) {
		k_sem_give(&data->tx_slot_sem);
	}
}

/* Post the frame in the slot claimed by emz_tx_reserve() and start MM2S. */
static int emz_setup_dma_tx_transfer(const struct device *dev, size_t len)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	size_t current_descriptor = data->tx_populated_buffer_index;
	int ret;

	if (emz_rx_direct_enabled(cfg)) {
		return emz_setup_dma_tx_direct_transfer(dev, len);
	}

	emaczero_perf_stats.tx_setup_calls++;
	emaczero_perf_stats.tx_last_len = len;
	ret = emz_post_dma_tx(dev, data->tx_buffer[current_descriptor].bytes, len);
	if (ret != 0) {
		emz_tx_unreserve(dev);
		emaczero_perf_stats.tx_last_ret = (uint32_t)ret;
		return ret;
	}
	/* The descriptor is in the ring now, so the slot stays claimed even if
	 * the start fails: the TX callback releases it when MM2S completes it.
	 */
	ret = dma_start(cfg->dma, EMZ_DMA_TX_CHANNEL);
	if (ret != 0) {
		emaczero_perf_stats.tx_dma_start_fail++;
	} else {
		emaczero_perf_stats.tx_dma_start_ok++;
	}
	emaczero_perf_stats.tx_last_ret = (uint32_t)ret;

	return ret;
}

static int emz_send(const struct device *dev, struct net_pkt *pkt)
{
	struct emaczero_data *data = dev->data;
	size_t len = net_pkt_get_len(pkt);
	size_t current_descriptor;
	int ret;

	emaczero_perf_stats.tx_send_calls++;
	emaczero_perf_stats.tx_last_len = len;
	if (len == 0u || len > EMZ_ETH_BUFFER_SIZE) {
		emaczero_perf_stats.tx_last_ret = (uint32_t)-EMSGSIZE;
		return -EMSGSIZE;
	}

	k_mutex_lock(&data->tx_lock, K_FOREVER);
	ret = emz_tx_reserve(dev, &current_descriptor);
	if (ret != 0) {
		k_mutex_unlock(&data->tx_lock);
		return ret;
	}
	if (net_pkt_read(pkt, data->tx_buffer[current_descriptor].bytes, len) != 0) {
		emz_tx_unreserve(dev);
		k_mutex_unlock(&data->tx_lock);
		emaczero_perf_stats.tx_send_read_fail++;
		emaczero_perf_stats.tx_last_ret = (uint32_t)-EIO;
		return -EIO;
	}
	emz_note_tx_frame(data->tx_buffer[current_descriptor].bytes, len);
	emz_note_tx_icmp(data->tx_buffer[current_descriptor].bytes, len);

	ret = emz_setup_dma_tx_transfer(dev, len);
	k_mutex_unlock(&data->tx_lock);
	return ret;
}

int emaczero_send_raw_frame(struct net_if *iface, const uint8_t *frame, size_t len)
{
	const struct device *dev;
	struct emaczero_data *data;
	size_t current_descriptor;
	int ret;

	if (iface == NULL) {
		return -ENODEV;
	}
	dev = net_if_get_device(iface);

	data = dev->data;
	if (len == 0u || len > EMZ_ETH_BUFFER_SIZE) {
		emaczero_perf_stats.tx_last_ret = (uint32_t)-EMSGSIZE;
		return -EMSGSIZE;
	}

	emaczero_perf_stats.tx_send_calls++;
	emaczero_perf_stats.tx_last_len = len;
	k_mutex_lock(&data->tx_lock, K_FOREVER);
	ret = emz_tx_reserve(dev, &current_descriptor);
	if (ret != 0) {
		k_mutex_unlock(&data->tx_lock);
		return ret;
	}

	memcpy(data->tx_buffer[current_descriptor].bytes, frame, len);
	emz_note_tx_frame(data->tx_buffer[current_descriptor].bytes, len);

	ret = emz_setup_dma_tx_transfer(dev, len);
	k_mutex_unlock(&data->tx_lock);
	return ret;
}

int emaczero_set_rx_interceptor(struct net_if *iface, emaczero_rx_interceptor_t interceptor,
				void *user_data)
{
	const struct device *dev;
	struct emaczero_data *data;

	if (iface == NULL) {
		return -ENODEV;
	}

	dev = net_if_get_device(iface);
	if (dev == NULL) {
		return -ENODEV;
	}

	data = dev->data;
	data->rx_interceptor_user_data = user_data;
	barrier_dmem_fence_full();
	data->rx_interceptor = interceptor;
	return 0;
}

#if defined(CONFIG_ETH_EMACZERO_PROFILE)
int emaczero_profile_send_raw_frame(const uint8_t *frame, size_t len)
{
	if (emz_profile_dev == NULL) {
		return -ENODEV;
	}

	return emaczero_send_raw_frame(net_if_lookup_by_dev(emz_profile_dev), frame, len);
}

/* Queue count copies of one frame with a single TAILDESC write, so the TX
 * benchmark measures MM2S and the MAC rather than per-frame driver overhead.
 */
static int emz_profile_send_burst_dma(const struct device *dev, const uint8_t *frame,
				      size_t len, uint32_t count)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	uint32_t queued = 0u;
	int ret = 0;

	if (cfg->dma == NULL) {
		return -ENODEV;
	}
	count = MIN(count, EMZ_TX_SLOTS);

	k_mutex_lock(&data->tx_lock, K_FOREVER);
	/* Every descriptor of the previous burst points at tx_burst_bytes, so
	 * wait for MM2S to finish with all of them before overwriting it.
	 */
	for (uint32_t wait_us = 0u; k_sem_count_get(&data->tx_slot_sem) != EMZ_TX_SLOTS;
	     wait_us++) {
		if (wait_us >= 10000u) {
			k_mutex_unlock(&data->tx_lock);
			emaczero_perf_stats.tx_setup_busy++;
			emaczero_perf_stats.tx_last_ret = (uint32_t)-ENOSPC;
			return -ENOSPC;
		}
		k_busy_wait(1);
	}

	memcpy(data->tx_burst_bytes, frame, len);
	emz_note_tx_frame(data->tx_burst_bytes, len);
	while (queued < count && k_sem_take(&data->tx_slot_sem, K_NO_WAIT) == 0) {
		ret = emz_post_dma_tx(dev, data->tx_burst_bytes, len);
		if (ret != 0) {
			k_sem_give(&data->tx_slot_sem);
			break;
		}
		queued++;
	}
	if (queued > 0u) {
		int start_ret = dma_start(cfg->dma, EMZ_DMA_TX_CHANNEL);

		if (start_ret != 0) {
			emaczero_perf_stats.tx_dma_start_fail++;
			ret = ret != 0 ? ret : start_ret;
		} else {
			emaczero_perf_stats.tx_dma_start_ok += queued;
		}
	}
	emaczero_perf_stats.tx_send_calls += queued;
	emaczero_perf_stats.tx_setup_calls += queued;
	emaczero_perf_stats.tx_last_ret = (uint32_t)ret;
	k_mutex_unlock(&data->tx_lock);

	return queued > 0u ? (int)queued : ret;
}

/* Fault injection for the DMA recovery test: post a zero-length descriptor.
 * When the engine reaches it the DataMover raises DMAIntErr and the channel
 * halts, the same state a bus error leaves, without writing any memory.
 * S2MM reaches it once every RX buffer posted ahead of it has been filled;
 * MM2S reaches it at once.
 */
int emaczero_profile_inject_dma_fault(bool tx)
{
	const struct device *dev = emz_profile_dev;
	const struct emaczero_config *cfg;
	struct emaczero_data *data;
	k_spinlock_key_t key;
	size_t slot;
	int ret;

	if (dev == NULL) {
		return -ENODEV;
	}
	cfg = dev->config;
	data = dev->data;
	if (cfg->dma == NULL || emz_rx_direct_enabled(cfg)) {
		return -ENOTSUP;
	}

	if (tx) {
		k_mutex_lock(&data->tx_lock, K_FOREVER);
		if (!data->dma_is_configured_tx) {
			k_mutex_unlock(&data->tx_lock);
			return -EAGAIN;
		}
		ret = emz_tx_reserve(dev, &slot);
		if (ret == 0) {
			ret = dma_reload(cfg->dma, EMZ_DMA_TX_CHANNEL,
					 (uintptr_t)data->tx_buffer[slot].bytes, 0u, 0u);
			if (ret == 0) {
				data->tx_populated_buffer_index =
					(data->tx_populated_buffer_index + 1u) %
					EMZ_DMA_BUFFER_COUNT_TX;
				ret = dma_start(cfg->dma, EMZ_DMA_TX_CHANNEL);
			} else {
				emz_tx_unreserve(dev);
			}
		}
		k_mutex_unlock(&data->tx_lock);
		return ret;
	}

	key = k_spin_lock(&data->rx_lock);
	if (!data->dma_is_configured_rx || atomic_get(&data->dma_recover_pending) != 0) {
		k_spin_unlock(&data->rx_lock, key);
		return -EAGAIN;
	}
	ret = dma_reload(cfg->dma, EMZ_DMA_RX_CHANNEL, 0u, (uintptr_t)data->rx_buffer[0].bytes,
			 0u);
	if (ret == 0) {
		ret = dma_start(cfg->dma, EMZ_DMA_RX_CHANNEL);
	}
	k_spin_unlock(&data->rx_lock, key);
	return ret;
}

int emaczero_profile_send_raw_frame_burst(const uint8_t *frame, size_t len, uint32_t count)
{
	const struct device *dev = emz_profile_dev;
	const struct emaczero_config *cfg;

	if (dev == NULL) {
		return -ENODEV;
	}

	cfg = dev->config;
	if (len == 0u || len > EMZ_ETH_BUFFER_SIZE) {
		emaczero_perf_stats.tx_last_ret = (uint32_t)-EMSGSIZE;
		return -EMSGSIZE;
	}
	if (count == 0u) {
		return 0;
	}
	if (!emz_rx_direct_enabled(cfg)) {
		return emz_profile_send_burst_dma(dev, frame, len, count);
	}
#if defined(CONFIG_ETH_EMACZERO_RX_DIRECT_RING)
	struct emaczero_data *data = dev->data;
	size_t first_descriptor;
	size_t last_descriptor;
	uint32_t queued = 0u;

	if (count > EMZ_DMA_BUFFER_COUNT_TX) {
		count = EMZ_DMA_BUFFER_COUNT_TX;
	}

	k_mutex_lock(&data->tx_lock, K_FOREVER);
	(void)emz_tx_direct_reclaim(dev);
	for (uint32_t wait_us = 0u; data->tx_bd_inflight != 0u; wait_us++) {
		if (wait_us >= 10000u) {
			k_mutex_unlock(&data->tx_lock);
			emaczero_perf_stats.tx_setup_busy++;
			emaczero_perf_stats.tx_last_ret = (uint32_t)-ENOSPC;
			return -ENOSPC;
		}
		k_busy_wait(1);
		(void)emz_tx_direct_reclaim(dev);
	}

	first_descriptor = data->tx_populated_buffer_index;
	last_descriptor = first_descriptor;
	memcpy(data->tx_buffer[first_descriptor].bytes, frame, len);
	emz_dma_cache_flush(data->tx_buffer[first_descriptor].bytes, len);
	emaczero_perf_stats.tx_last_len = len;
	emaczero_perf_stats.tx_last_word0 =
		emz_sample_word(data->tx_buffer[first_descriptor].bytes, len, 0u);
	emaczero_perf_stats.tx_last_word1 =
		emz_sample_word(data->tx_buffer[first_descriptor].bytes, len, 4u);
	emaczero_perf_stats.tx_last_word2 =
		emz_sample_word(data->tx_buffer[first_descriptor].bytes, len, 8u);
	emaczero_perf_stats.tx_last_word3 =
		emz_sample_word(data->tx_buffer[first_descriptor].bytes, len, 12u);
	emaczero_perf_stats.tx_ext_len = (uint32_t)len;
	{
		volatile uint32_t *txw = &emaczero_perf_stats.tx_ext_word0;
		for (size_t i = 0; i < 16u; i++) {
			txw[i] = emz_sample_word(
				data->tx_buffer[first_descriptor].bytes, len,
				(size_t)(i * 4u));
		}
	}

	while (queued < count) {
		size_t index = data->tx_populated_buffer_index;
		volatile struct emaczero_rx_bd *bd = &data->tx_bd_ring[index];

		bd->buffer_address =
			(uint32_t)(uintptr_t)data->tx_buffer[first_descriptor].bytes;
		bd->buffer_address_msb = 0u;
		bd->control = EMZ_AXI_DMA_BD_CTRL_SOF | EMZ_AXI_DMA_BD_CTRL_EOF |
			      (len & EMZ_AXI_DMA_BD_CTRL_LEN_MASK);
		bd->app0 = 0u;
		bd->app1 = 0u;
		bd->app2 = 0u;
		bd->app3 = 0u;
		bd->app4 = 0u;
		bd->status = 0u;
		emz_dma_cache_flush((const void *)bd, sizeof(*bd));

		last_descriptor = index;
		data->tx_populated_buffer_index = (index + 1u) % EMZ_DMA_BUFFER_COUNT_TX;
		data->tx_bd_inflight++;
		queued++;
	}

	barrier_dmem_fence_full();
	emz_dma_write(cfg, EMZ_AXI_DMA_REG_MM2S_TAILDESC,
		      (uint32_t)(uintptr_t)&data->tx_bd_ring[last_descriptor]);
	emaczero_perf_stats.tx_send_calls += queued;
	emaczero_perf_stats.tx_setup_calls += queued;
	emaczero_perf_stats.tx_dma_start_ok += queued;
	emaczero_perf_stats.tx_last_ret = 0u;
	k_mutex_unlock(&data->tx_lock);
	return (int)queued;
#else
	return -ENOTSUP;
#endif
}
#endif

static uint32_t emz_sample_word(const uint8_t *bytes, size_t len, size_t offset)
{
	uint32_t word = 0u;

	for (size_t i = 0; i < 4u; i++) {
		if (offset + i < len) {
			word |= (uint32_t)bytes[offset + i] << (i * 8u);
		}
	}

	return word;
}

static void emz_note_bad_sample(struct emaczero_rx_buffer *rx)
{
	if (emaczero_perf_stats.rx_bad_sample_seen != 0u) {
		return;
	}

	emaczero_perf_stats.rx_bad_sample_seen = 1u;
	emaczero_perf_stats.rx_bad_sample_len = rx->len;
	emaczero_perf_stats.rx_bad_sample_status = (uint32_t)rx->status;
	emaczero_perf_stats.rx_bad_sample_word0 = emz_sample_word(rx->bytes, rx->len, 0u);
	emaczero_perf_stats.rx_bad_sample_word1 = emz_sample_word(rx->bytes, rx->len, 4u);
	emaczero_perf_stats.rx_bad_sample_word2 = emz_sample_word(rx->bytes, rx->len, 8u);
	emaczero_perf_stats.rx_bad_sample_word3 = emz_sample_word(rx->bytes, rx->len, 12u);
}

static void emz_note_good_sample(struct emaczero_rx_buffer *rx)
{
	if (emaczero_perf_stats.rx_good_sample_seen != 0u) {
		return;
	}

	emaczero_perf_stats.rx_good_sample_seen = 1u;
	emaczero_perf_stats.rx_good_sample_len = rx->len;
	emaczero_perf_stats.rx_good_sample_word0 = emz_sample_word(rx->bytes, rx->len, 0u);
	emaczero_perf_stats.rx_good_sample_word1 = emz_sample_word(rx->bytes, rx->len, 4u);
	emaczero_perf_stats.rx_good_sample_word2 = emz_sample_word(rx->bytes, rx->len, 8u);
	emaczero_perf_stats.rx_good_sample_word3 = emz_sample_word(rx->bytes, rx->len, 12u);
}

static void emz_note_last_sample(struct emaczero_rx_buffer *rx)
{
	emaczero_perf_stats.rx_last_sample_len = rx->len;
	emaczero_perf_stats.rx_last_sample_status = (uint32_t)rx->status;
	emaczero_perf_stats.rx_last_sample_word0 = emz_sample_word(rx->bytes, rx->len, 0u);
	emaczero_perf_stats.rx_last_sample_word1 = emz_sample_word(rx->bytes, rx->len, 4u);
	emaczero_perf_stats.rx_last_sample_word2 = emz_sample_word(rx->bytes, rx->len, 8u);
	emaczero_perf_stats.rx_last_sample_word3 = emz_sample_word(rx->bytes, rx->len, 12u);
	emaczero_perf_stats.rx_last_sample_word4 = emz_sample_word(rx->bytes, rx->len, 16u);
	emaczero_perf_stats.rx_last_sample_word5 = emz_sample_word(rx->bytes, rx->len, 20u);
	emaczero_perf_stats.rx_last_sample_word6 = emz_sample_word(rx->bytes, rx->len, 24u);
	emaczero_perf_stats.rx_last_sample_word7 = emz_sample_word(rx->bytes, rx->len, 28u);
}

static void emz_note_rx_pre_stack(struct emaczero_data *data, struct emaczero_rx_buffer *rx)
{
	const uint8_t *frame = rx->bytes;
	uint16_t eth_type;
	size_t ip_header_len;
	size_t icmp_offset;
	size_t udp_offset;
	bool broadcast = true;
	bool multicast;
	bool dst_me;

	emz_note_last_sample(rx);

	if (rx->len < 14u) {
		emaczero_perf_stats.rx_pre_type_other++;
		emz_note_bad_sample(rx);
		return;
	}

	for (size_t i = 0; i < NET_ETH_ADDR_LEN; i++) {
		if (frame[i] != 0xffu) {
			broadcast = false;
			break;
		}
	}

	multicast = (frame[0] & 0x01u) != 0u;
	dst_me = memcmp(frame, data->mac, NET_ETH_ADDR_LEN) == 0;

	if (dst_me) {
		emaczero_perf_stats.rx_pre_dst_me++;
	} else if (broadcast) {
		emaczero_perf_stats.rx_pre_dst_broadcast++;
	} else if (multicast) {
		emaczero_perf_stats.rx_pre_dst_multicast++;
	} else {
		emaczero_perf_stats.rx_pre_dst_other++;
		emz_note_bad_sample(rx);
	}

	eth_type = ((uint16_t)frame[12] << 8) | frame[13];
	if (eth_type == EMZ_ETH_TYPE_ARP) {
		emaczero_perf_stats.rx_pre_type_arp++;
		return;
	}

	if (eth_type != EMZ_ETH_TYPE_IPV4) {
		emaczero_perf_stats.rx_pre_type_other++;
		emz_note_bad_sample(rx);
		return;
	}

	emaczero_perf_stats.rx_pre_type_ipv4++;
	if (rx->len < 34u || (frame[14] >> 4) != 4u || (frame[14] & 0x0fu) < 5u) {
		emaczero_perf_stats.rx_pre_ipv4_bad++;
		emz_note_bad_sample(rx);
		return;
	}

	ip_header_len = (size_t)(frame[14] & 0x0fu) * 4u;
	if (frame[23] == EMZ_IP_PROTO_ICMP) {
		icmp_offset = 14u + ip_header_len;
		if (rx->len >= icmp_offset + 8u) {
			emaczero_perf_stats.rx_last_icmp_src =
				emz_sample_be32(frame, rx->len, 26u);
			emaczero_perf_stats.rx_last_icmp_dst =
				emz_sample_be32(frame, rx->len, 30u);
			emaczero_perf_stats.rx_last_icmp_id =
				emz_sample_be16(frame, rx->len, icmp_offset + 4u);
			emaczero_perf_stats.rx_last_icmp_seq =
				emz_sample_be16(frame, rx->len, icmp_offset + 6u);
		}
		return;
	}

	if (frame[23] != EMZ_IP_PROTO_UDP) {
		return;
	}

	emaczero_perf_stats.rx_pre_ipv4_udp++;
	udp_offset = 14u + ip_header_len;
	if (rx->len < udp_offset + 8u) {
		emaczero_perf_stats.rx_pre_udp_bad_len++;
		emz_note_bad_sample(rx);
		return;
	}

	emz_note_good_sample(rx);
}

static void emz_rx_thread(void *arg1, void *arg2, void *arg3)
{
	const struct device *dev = arg1;
	struct emaczero_data *data = dev->data;

	ARG_UNUSED(arg2);
	ARG_UNUSED(arg3);

	while (true) {
		struct emaczero_rx_buffer *rx = k_fifo_get(&data->rx_ready_fifo, K_FOREVER);
		uint32_t r7_thread_start = k_cycle_get_32();
		struct emaczero_rx_frag_ctx *ctx;
		struct net_buf *frag;
		struct net_pkt *pkt;
		bool copy_fallback;
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
		uint32_t build_start_cycle = k_cycle_get_32();
#endif

		atomic_dec(&data->rx_ready_fifo_count);
		atomic_inc(&data->rx_worker_count);
		emz_perf_update_pool_inflight(data);
		EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_WORKER_PACKETS);
		emaczero_perf_stats.rx_worker_packets++;
		if (data->iface == NULL || !net_if_is_up(data->iface)) {
			emz_release_rx_buffer_from_worker(dev, rx);
			continue;
		}

		if (rx->status < 0 || rx->len == 0u || rx->len > EMZ_ETH_BUFFER_SIZE) {
			LOG_ERR("DMA RX invalid frame status %d length %u", rx->status, rx->len);
			emaczero_perf_stats.rx_invalid++;
			EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_INVALID);
			eth_stats_update_errors_rx(data->iface);
			emz_release_rx_buffer_from_worker(dev, rx);
			continue;
		}

		emz_note_rx_pre_stack(data, rx);

		copy_fallback = atomic_get(&data->rx_stack_owned_count) >=
				EMZ_RX_MAX_STACK_OWNED_ZEROCOPY;
		if (copy_fallback) {
			pkt = net_pkt_rx_alloc_on_iface(data->iface, K_NO_WAIT);
			if (pkt == NULL) {
				LOG_ERR("Could not allocate RX copy-fallback packet");
				emaczero_perf_stats.rx_alloc_pkt_fail++;
				emaczero_perf_stats.rx_alloc_pkt_copy_fail++;
				EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_ALLOC_PKT_FAIL);
				eth_stats_update_errors_rx(data->iface);
				emz_release_rx_buffer_from_worker(dev, rx);
				continue;
			}
			net_pkt_set_family(pkt, AF_UNSPEC);

#if EMZ_RX_COPY_FALLBACK_COUNT > 0
			frag = emz_rx_copy_frag_alloc(rx);
			if (frag == NULL) {
				LOG_ERR("Could not allocate RX copy-fallback fragment");
				net_pkt_unref(pkt);
				emaczero_perf_stats.rx_alloc_frag_fail++;
				eth_stats_update_errors_rx(data->iface);
				emz_release_rx_buffer_from_worker(dev, rx);
				continue;
			}
			net_pkt_append_buffer(pkt, frag);
#else
			if (net_pkt_write(pkt, rx->bytes, rx->len) != 0) {
				LOG_ERR("Could not copy RX fallback packet");
				emaczero_perf_stats.rx_copy_write_fail++;
				net_pkt_unref(pkt);
				eth_stats_update_errors_rx(data->iface);
				emz_release_rx_buffer_from_worker(dev, rx);
				continue;
			}
#endif

#if defined(CONFIG_ETH_EMACZERO_PROFILE)
			EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_COPY_FALLBACK);
			EMZ_PROFILE_ADD_CYCLES(EMACZERO_PROFILE_CYCLES_RX_BUILD,
					       emaczero_profile_elapsed(build_start_cycle,
								   k_cycle_get_32()));
			if (emaczero_profile_get_mode() == EMACZERO_PROFILE_MODE_DROP_AFTER_PKT &&
			    !emaczero_profile_should_keep_control(rx->bytes, rx->len)) {
				EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_DROP_AFTER_PKT);
				net_pkt_unref(pkt);
				emz_release_rx_buffer_from_worker(dev, rx);
				continue;
			}
			build_start_cycle = k_cycle_get_32();
#endif
			// 64-byte RX-ext capture (copy-fallback path) — point B in the
			// four-point trace. Bytes that Zephyr is about to receive.
			emaczero_perf_stats.rx_ext_len = (uint32_t)rx->len;
			{
				volatile uint32_t *rxw = &emaczero_perf_stats.rx_ext_word0;
				for (size_t i = 0; i < 16u; i++) {
					rxw[i] = emz_sample_word(rx->bytes,
								  (size_t)rx->len,
								  (size_t)(i * 4u));
				}
			}
			if (net_recv_data(data->iface, pkt) < 0) {
				LOG_ERR("Could not submit RX copy-fallback packet");
				net_pkt_unref(pkt);
				eth_stats_update_errors_rx(data->iface);
				emaczero_perf_stats.rx_net_recv_fail++;
				EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_NET_RECV_FAIL);
			} else {
				emaczero_perf_stats.rx_copy_submit++;
				EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_COPY_SUBMIT);
			}
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
			EMZ_PROFILE_ADD_CYCLES(EMACZERO_PROFILE_CYCLES_NET_RECV,
					       emaczero_profile_elapsed(build_start_cycle,
								   k_cycle_get_32()));
#endif
			emz_r7_add(EMZ_R7_RX_THREAD_BUILD,
				   emz_r7_elapsed(r7_thread_start, k_cycle_get_32()));
			emz_release_rx_buffer_from_worker(dev, rx);
			continue;
		}

		pkt = net_pkt_rx_alloc_on_iface(data->iface, K_NO_WAIT);
		if (pkt == NULL) {
			LOG_ERR("Could not allocate RX packet");
			emaczero_perf_stats.rx_alloc_pkt_fail++;
			emaczero_perf_stats.rx_alloc_pkt_zc_fail++;
			EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_ALLOC_PKT_FAIL);
			eth_stats_update_errors_rx(data->iface);
			emz_release_rx_buffer_from_worker(dev, rx);
			continue;
		}

		frag = net_buf_alloc_with_data(&emz_rx_frag_pool, rx->bytes, rx->len, K_NO_WAIT);
		if (frag == NULL) {
			LOG_ERR("Could not allocate RX zero-copy fragment");
			net_pkt_unref(pkt);
			emaczero_perf_stats.rx_alloc_frag_fail++;
			EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_ALLOC_FRAG_FAIL);
			eth_stats_update_errors_rx(data->iface);
			emz_release_rx_buffer_from_worker(dev, rx);
			continue;
		}

		ctx = net_buf_user_data(frag);
		ctx->dev = dev;
		ctx->rx = rx;
		rx->stack_handoff_cycle = k_cycle_get_32();
		atomic_inc(&data->rx_stack_owned_count);
		atomic_dec(&data->rx_worker_count);
		emz_perf_update_pool_inflight(data);
		emz_perf_set_max_u32(&emaczero_perf_stats.rx_max_stack_owned,
				      (uint32_t)atomic_get(&data->rx_stack_owned_count));
		EMZ_PROFILE_MAX(EMACZERO_PROFILE_MAX_RX_STACK_OWNED,
				(uint32_t)atomic_get(&data->rx_stack_owned_count));
		net_pkt_set_family(pkt, AF_UNSPEC);
		net_pkt_append_buffer(pkt, frag);

#if defined(CONFIG_ETH_EMACZERO_PROFILE)
		EMZ_PROFILE_ADD_CYCLES(EMACZERO_PROFILE_CYCLES_RX_BUILD,
				       emaczero_profile_elapsed(build_start_cycle, k_cycle_get_32()));
		if (emaczero_profile_get_mode() == EMACZERO_PROFILE_MODE_DROP_AFTER_PKT &&
		    !emaczero_profile_should_keep_control(rx->bytes, rx->len)) {
			EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_DROP_AFTER_PKT);
			net_pkt_unref(pkt);
			continue;
		}
		build_start_cycle = k_cycle_get_32();
#endif
		// 64-byte RX-ext capture (zero-copy path) — point B in the four-point
		// trace. Bytes that Zephyr is about to receive.
		emaczero_perf_stats.rx_ext_len = (uint32_t)rx->len;
		{
			volatile uint32_t *rxw = &emaczero_perf_stats.rx_ext_word0;
			for (size_t i = 0; i < 16u; i++) {
				rxw[i] = emz_sample_word(rx->bytes,
							  (size_t)rx->len,
							  (size_t)(i * 4u));
			}
		}
		if (net_recv_data(data->iface, pkt) < 0) {
			LOG_ERR("Could not submit RX packet");
			net_pkt_unref(pkt);
			eth_stats_update_errors_rx(data->iface);
			emaczero_perf_stats.rx_net_recv_fail++;
			EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_NET_RECV_FAIL);
		} else {
			emaczero_perf_stats.rx_zero_copy_submit++;
			EMZ_PROFILE_COUNTER(EMACZERO_PROFILE_COUNTER_RX_ZERO_COPY_SUBMIT);
		}
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
		EMZ_PROFILE_ADD_CYCLES(EMACZERO_PROFILE_CYCLES_NET_RECV,
				       emaczero_profile_elapsed(build_start_cycle, k_cycle_get_32()));
#endif
		emz_r7_add(EMZ_R7_RX_THREAD_BUILD,
			   emz_r7_elapsed(r7_thread_start, k_cycle_get_32()));
	}
}

#if defined(CONFIG_NET_STATISTICS_ETHERNET)
static struct net_stats_eth *emz_get_stats(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;

	data->stats.bytes.sent = emz_read(cfg, EMZ_REG_TX_BYTE_CNT);
	data->stats.bytes.received = emz_read(cfg, EMZ_REG_RX_BYTE_CNT);
	data->stats.pkts.tx = emz_read(cfg, EMZ_REG_TX_FRAME_CNT);
	data->stats.pkts.rx = emz_read(cfg, EMZ_REG_RX_FRAME_CNT);
	data->stats.errors.rx = emz_read(cfg, EMZ_REG_RX_ERR_CNT);
	data->stats.broadcast.rx = emz_read(cfg, EMZ_REG_RX_BCAST);
	data->stats.multicast.rx = emz_read(cfg, EMZ_REG_RX_MCAST);
	data->stats.error_details.rx_align_errors = emz_read(cfg, EMZ_REG_RX_ERR_ALIGN);

	return &data->stats;
}
#endif

static void emz_iface_init(struct net_if *iface)
{
	const struct device *dev = net_if_get_device(iface);
	struct emaczero_data *data = dev->data;

	data->iface = iface;
	net_if_set_link_addr(iface, data->mac, NET_ETH_ADDR_LEN, NET_LINK_ETHERNET);
	ethernet_init(iface);
	net_eth_carrier_on(iface);
}

static int emz_init(const struct device *dev)
{
	const struct emaczero_config *cfg = dev->config;
	struct emaczero_data *data = dev->data;
	uint32_t version = emz_read(cfg, EMZ_REG_VERSION);
	uint32_t ctrl;

	if (version != EMZ_VERSION_VALUE) {
		LOG_ERR("bad VERSION register 0x%08x at %p", version, (void *)cfg->base);
		return -ENODEV;
	}

	data->dev = dev;
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
	emz_profile_dev = dev;
#endif
	memcpy(data->mac, cfg->mac, NET_ETH_ADDR_LEN);
	k_mutex_init(&data->tx_lock);
	k_sem_init(&data->tx_slot_sem, EMZ_TX_SLOTS, EMZ_TX_SLOTS);
	k_work_init_delayable(&data->dma_recover_work, emz_dma_recover_work_handler);

	// Write self-describing sentinels for the 64-byte four-point-trace
	// capture blocks. Host tooling scans the perf-stats DDR region for
	// these magics, so the byte offset of the surrounding fields does
	// not need to be known.
	emaczero_perf_stats.rx_ext_magic = 0x52584542u; // "RXEB"
	emaczero_perf_stats.tx_ext_magic = 0x54584542u; // "TXEB"
#if defined(CONFIG_ETH_EMACZERO_RX_DIRECT_RING)
	k_work_init_delayable(&data->rx_direct_poll_work, emz_rx_direct_poll_work_handler);
	k_work_init(&data->rx_direct_recover_work, emz_rx_direct_recover_work_handler);
#endif
	k_fifo_init(&data->rx_free_fifo);
	k_fifo_init(&data->rx_dma_fifo);
	k_fifo_init(&data->rx_ready_fifo);
#if CONFIG_ETH_EMACZERO_DMA_MEMORY_SIZE != 0
	emz_dma_mem_reset();
	emz_sg_mem_reset();
	emz_r7_init_magic();
	for (size_t i = 0; i < ARRAY_SIZE(data->rx_buffer); i++) {
		data->rx_buffer[i].bytes = emz_dma_mem_alloc(64u, EMZ_ETH_BUFFER_SIZE);
		if (data->rx_buffer[i].bytes == NULL) {
			return -ENOMEM;
		}
	}
	for (size_t i = 0; i < ARRAY_SIZE(data->tx_buffer); i++) {
		data->tx_buffer[i].bytes = emz_dma_mem_alloc(64u, EMZ_ETH_BUFFER_SIZE);
		if (data->tx_buffer[i].bytes == NULL) {
			return -ENOMEM;
		}
	}
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
	data->tx_burst_bytes = emz_dma_mem_alloc(64u, EMZ_ETH_BUFFER_SIZE);
	if (data->tx_burst_bytes == NULL) {
		return -ENOMEM;
	}
#endif
#else
	for (size_t i = 0; i < ARRAY_SIZE(data->rx_buffer); i++) {
		data->rx_buffer[i].bytes = data->rx_storage[i];
	}
	for (size_t i = 0; i < ARRAY_SIZE(data->tx_buffer); i++) {
		data->tx_buffer[i].bytes = data->tx_storage[i];
	}
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
	data->tx_burst_bytes = data->tx_burst_storage;
#endif
#endif
	for (size_t i = 0; i < ARRAY_SIZE(data->rx_buffer); i++) {
		k_fifo_put(&data->rx_free_fifo, &data->rx_buffer[i]);
	}
	atomic_set(&data->rx_free_count, EMZ_DMA_BUFFER_COUNT_RX);
	atomic_set(&data->rx_dma_fifo_count, 0);
	atomic_set(&data->rx_ready_fifo_count, 0);
	atomic_set(&data->rx_worker_count, 0);
	atomic_set(&data->rx_stack_owned_count, 0);
	emaczero_perf_stats.rx_pool_size = EMZ_DMA_BUFFER_COUNT_RX;
	emaczero_perf_stats.rx_min_free = UINT32_MAX;
	emz_perf_update_pool_inflight(data);
#if defined(CONFIG_ETH_EMACZERO_PROFILE)
	emaczero_profile_reset();
#endif

	k_thread_create(&data->rx_thread, cfg->rx_thread_stack,
			cfg->rx_thread_stack_size, emz_rx_thread,
			(void *)dev, NULL, NULL, EMZ_RX_THREAD_PRIORITY, 0, K_NO_WAIT);
	k_thread_name_set(&data->rx_thread, "emaczero_rx");
	emz_set_mac(cfg, data->mac);

	ctrl = EMZ_CTRL_TX_EN | EMZ_CTRL_RX_EN | EMZ_CTRL_FULL_DUPLEX |
	       ((emz_speed_field(cfg->speed) << EMZ_CTRL_SPEED_SHIFT) & EMZ_CTRL_SPEED_MASK);
	emz_write(cfg, EMZ_REG_CTRL, ctrl);
	emz_write(cfg, EMZ_REG_IRQ_EN, 0);
	emz_write(cfg, EMZ_REG_IRQ_STATUS, EMZ_IRQ_ALL);

	if (cfg->dma != NULL) {
		int ret;

		if (emz_rx_direct_enabled(cfg)) {
#if defined(CONFIG_ETH_EMACZERO_RX_DIRECT_RING)
			if (cfg->direct_rx_irq_configure != NULL) {
				cfg->direct_rx_irq_configure();
			}
			ret = emz_rx_direct_start(dev);
			if (ret < 0) {
				LOG_ERR("failed to queue RX DMA buffers: %d", ret);
				return ret;
			}
			ret = emz_tx_direct_start(dev);
			if (ret != 0) {
				LOG_ERR("failed to start TX DMA channel: %d", ret);
				return ret;
			}
#else
			ret = -ENOTSUP;
#endif
		} else {
			ret = emz_refill_dma_rx(dev);
		}

		if (ret < 0) {
			LOG_ERR("failed to queue RX DMA buffers: %d", ret);
			return ret;
		}
	}

	LOG_INF("emacZero initialized at %p", (void *)cfg->base);
	return 0;
}

static const struct ethernet_api emz_api = {
	.iface_api.init = emz_iface_init,
#if defined(CONFIG_NET_STATISTICS_ETHERNET)
	.get_stats = emz_get_stats,
#endif
	.start = emz_start,
	.stop = emz_stop,
	.get_capabilities = emz_get_capabilities,
	.set_config = emz_set_config,
	.get_config = emz_get_config,
	.send = emz_send,
};

#if defined(CONFIG_ETH_EMACZERO_RX_DIRECT_RING)
#define EMZ_DIRECT_RX_IRQ_CONFIGURE(inst)						\
	static void emz_direct_rx_irq_configure_##inst(void)				\
	{										\
		IRQ_CONNECT(DT_IRQN_BY_IDX(DT_INST_PHANDLE(inst, axistream_connected), 1),	\
			    DT_IRQ_BY_IDX(DT_INST_PHANDLE(inst, axistream_connected), 1,	\
					  priority),					\
			    emz_rx_direct_isr, DEVICE_DT_INST_GET(inst), 0);		\
	}
#else
#define EMZ_DIRECT_RX_IRQ_CONFIGURE(inst)						\
	static void emz_direct_rx_irq_configure_##inst(void)				\
	{										\
	}
#endif

/* The packet-buffer window and the DMA's descriptor region must not overlap:
 * the bump allocator would hand out buffers on top of live descriptors.
 */
#define EMZ_DMA_WINDOW_END								\
	((uint64_t)CONFIG_ETH_EMACZERO_DMA_MEMORY_BASE + CONFIG_ETH_EMACZERO_DMA_MEMORY_SIZE)
#define EMZ_DESC_REGION_CHECK(desc)							\
	BUILD_ASSERT(CONFIG_ETH_EMACZERO_DMA_MEMORY_SIZE == 0 ||			\
		     (uint64_t)DT_REG_ADDR(desc) + DT_REG_SIZE(desc) <=			\
			     CONFIG_ETH_EMACZERO_DMA_MEMORY_BASE ||			\
		     (uint64_t)DT_REG_ADDR(desc) >= EMZ_DMA_WINDOW_END,			\
		     "emacZero DMA memory window overlaps the AXI DMA descriptor region");
#define EMZ_DMA_DESC_CHECK(dma)								\
	COND_CODE_1(DT_NODE_HAS_PROP(dma, memory_region),				\
		    (EMZ_DESC_REGION_CHECK(DT_PHANDLE(dma, memory_region))), ())

#define EMZ_INIT(inst)									\
	COND_CODE_1(DT_INST_NODE_HAS_PROP(inst, axistream_connected),			\
		    (EMZ_DMA_DESC_CHECK(DT_INST_PHANDLE(inst, axistream_connected))), ())\
	EMZ_DIRECT_RX_IRQ_CONFIGURE(inst)						\
	static struct emaczero_data emz_data_##inst;					\
	K_THREAD_STACK_DEFINE(emz_rx_thread_stack_##inst, EMZ_RX_THREAD_STACK_SIZE);	\
	static const struct emaczero_config emz_config_##inst = {			\
		.base = DT_INST_REG_ADDR(inst),						\
		.dma_base = COND_CODE_1(DT_INST_NODE_HAS_PROP(inst, axistream_connected),\
					(DT_REG_ADDR(DT_INST_PHANDLE(inst, axistream_connected))),\
					(0)),						\
		.dma = COND_CODE_1(DT_INST_NODE_HAS_PROP(inst, axistream_connected),	\
				   (DEVICE_DT_GET(DT_INST_PHANDLE(inst, axistream_connected))),\
				   (NULL)),						\
		.dma_rx_irq = COND_CODE_1(DT_INST_NODE_HAS_PROP(inst, axistream_connected),\
					  (DT_IRQN_BY_IDX(DT_INST_PHANDLE(inst, axistream_connected), 1)),\
					  (0)),						\
		.direct_rx_irq_configure = emz_direct_rx_irq_configure_##inst,		\
		.rx_thread_stack = emz_rx_thread_stack_##inst,			\
		.rx_thread_stack_size = K_THREAD_STACK_SIZEOF(emz_rx_thread_stack_##inst),\
		.speed = DT_INST_PROP_OR(inst, link_speed, 100),			\
		.mac = DT_INST_PROP_OR(inst, local_mac_address, {0}),			\
	};										\
	ETH_NET_DEVICE_DT_INST_DEFINE(inst, emz_init, NULL, &emz_data_##inst,		\
				      &emz_config_##inst,				\
				      CONFIG_ETH_EMACZERO_INIT_PRIORITY, &emz_api,	\
				      NET_ETH_MTU)

DT_INST_FOREACH_STATUS_OKAY(EMZ_INIT)
