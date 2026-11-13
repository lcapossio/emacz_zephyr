/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 *
 * Program-counter sampler for profiling on the soft CPUs, which have no
 * instruction counter. A timer records the interrupted pc and ra of every
 * busy tick into a buffer in uncached memory (the emz_pcs node of
 * app/perf/pc_sample.overlay); scripts/read_pc_samples.py arms it over
 * JTAG-AXI, reads it back and names the functions from the ELF.
 *
 * The buffer only fills while the host has armed it, and stops when full,
 * so it holds the start of the run the host is measuring. Ticks that land
 * in the idle thread are only counted.
 */

#include <zephyr/kernel.h>
#include <zephyr/devicetree.h>

#define PCS_NODE  DT_NODELABEL(emz_pcs)
#define PCS_MAGIC 0x50435331u /* "PCS1" */
/* off any multiple of the 50 ms usage thread and the 1 s main loop; rounds
 * up to a whole tick
 */
#define PCS_PERIOD K_USEC(1100)

struct pcs_buf {
	uint32_t magic;
	/* the host sets it to start a run; cleared when the buffer is full */
	uint32_t armed;
	uint32_t capacity;
	uint32_t count;
	uint32_t idle;
	uint32_t reserved[3];
	struct {
		uint32_t pc;
		uint32_t ra;
	} sample[];
};

#define PCS_CAPACITY ((DT_REG_SIZE(PCS_NODE) - sizeof(struct pcs_buf)) / 8u)
#define pcs ((volatile struct pcs_buf *)DT_REG_ADDR(PCS_NODE))

static void pcs_tick(struct k_timer *timer)
{
	/*
	 * The ISR wrapper (arch/riscv/core/isr.S) saves the interrupted
	 * context, then leaves a pointer to it 16 bytes below the top of the
	 * IRQ stack before running the handler; Zephyr's perf backend reads it
	 * the same way.
	 */
	const struct arch_esf *esf =
		*(struct arch_esf **)((uintptr_t)_current_cpu->irq_stack - 16);
	uint32_t n;

	ARG_UNUSED(timer);

	if (!pcs->armed) {
		return;
	}
	if (k_thread_priority_get(k_current_get()) == K_IDLE_PRIO) {
		pcs->idle++;
		return;
	}

	n = pcs->count;
	pcs->sample[n].pc = (uint32_t)esf->mepc;
	pcs->sample[n].ra = (uint32_t)esf->ra;
	pcs->count = ++n;
	if (n >= PCS_CAPACITY) {
		pcs->armed = 0;
	}
}

static K_TIMER_DEFINE(pcs_timer, pcs_tick, NULL);

void pc_sample_start(void)
{
	pcs->armed = 0;
	pcs->count = 0;
	pcs->idle = 0;
	pcs->capacity = PCS_CAPACITY;
	pcs->magic = PCS_MAGIC;
	k_timer_start(&pcs_timer, PCS_PERIOD, PCS_PERIOD);
}
