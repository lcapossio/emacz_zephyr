/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 *
 * Multi-level IRQ glue for the VexRiscv-full shells (Arty A7, ZCU106). Mirrors
 * the mbv32 upstream soc.c (deps/zephyr/soc/xlnx/mbv32/soc.c) since we
 * inherit the same AXI-INTC-behind-riscv,cpu-intc topology.
 *
 *   Level 1: riscv,cpu-intc (16 M-mode lines, mie/mip CSRs)
 *   Level 2: xlnx,xps-intc @ 0x41200000 aggregated onto cpu0_intc line 11
 *
 * Without these overrides, Zephyr's default arch_irq_* helpers write bits
 * straight into mie for every irqn, which silently drops any encoded
 * 2nd-level IRQ (the dma_xilinx_axi_dma_* ISRs, ...). They also
 * never dispatch the AXI INTC's ISR when cpu0_intc line 11 fires.
 */

#include <zephyr/arch/cpu.h>
#include <zephyr/arch/riscv/irq.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/interrupt_controller/intc_xlnx.h>
#include <zephyr/irq.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/__assert.h>
#include <zephyr/tracing/tracing.h>

void arch_irq_enable(uint32_t irq)
{
	unsigned int level = irq_get_level(irq);

	if (level == 1) {
		(void)csr_read_set(mie, 1UL << irq);
	} else if (level == 2) {
		irq = irq_from_level_2(irq);
		xlnx_intc_irq_enable(irq);
		/* Also make sure the M-mode external IRQ bit stays enabled so
		 * axi_intc's output actually reaches the trap handler.
		 */
		(void)csr_read_set(mie, 1UL << RISCV_IRQ_MEXT);
	} else {
		__ASSERT(0, "unsupported IRQ level %u for irqn %u", level, irq);
	}
}

void arch_irq_disable(uint32_t irq)
{
	unsigned int level = irq_get_level(irq);

	if (level == 2) {
		irq = irq_from_level_2(irq);
		xlnx_intc_irq_disable(irq);
	} else {
		(void)csr_read_clear(mie, 1UL << irq);
	}
}

int arch_irq_is_enabled(uint32_t irq)
{
	unsigned int level = irq_get_level(irq);
	uint32_t bits;

	if (level == 2) {
		irq = irq_from_level_2(irq);
		return !!(BIT(irq) & xlnx_intc_irq_get_enabled());
	}

	bits = csr_read(mie);
	return !!(bits & (1UL << irq));
}

uint32_t arch_irq_pending(void)
{
	return xlnx_intc_irq_pending();
}

uint32_t arch_irq_pending_vector(uint32_t ipending)
{
	ARG_UNUSED(ipending);
	return xlnx_intc_irq_pending_vector();
}

/* NOTE: no WFI here. VexRiscv-full's WFI implementation gates the pipeline
 * on `interrupt.pending && interrupt.enabled`, so if mstatus.MIE was ever
 * clear when we hit WFI the core never wakes even after mip lights up. The
 * mbv32 SoC dodges the same corner case by just re-enabling IRQs and
 * spinning; idle-thread cycles are cheap compared to a deadlocked kernel.
 */
#ifdef CONFIG_ARCH_HAS_CUSTOM_CPU_IDLE
void arch_cpu_idle(void)
{
	sys_trace_idle();
	irq_unlock(MSTATUS_IEN);
}
#endif

#ifdef CONFIG_ARCH_HAS_CUSTOM_CPU_ATOMIC_IDLE
void arch_cpu_atomic_idle(unsigned int key)
{
	sys_trace_idle();
	irq_unlock(key);
}
#endif

/* Publish fatal-error context to a scratch region so we can decode boot hangs
 * via JTAG-AXI when the UART is unavailable. Address is discovered by looking
 * up `vex_fatal_scratch` in the ELF symbol table.
 */
volatile uint32_t vex_fatal_scratch[4] __attribute__((section(".noinit")));

FUNC_NORETURN void k_sys_fatal_error_handler(unsigned int reason,
					     const struct arch_esf *esf)
{
	/* Disable interrupts so we can't be pre-empted mid-capture. */
	(void)csr_read_clear(mstatus, MSTATUS_MIE);

	/* First-invocation guard: nested/subsequent faults must not clobber
	 * the original fault context. vex_fatal_scratch[0]'s magic nibble
	 * (0xFA7A) marks "capture done".
	 */
	if ((vex_fatal_scratch[0] >> 16) != 0xFA7A) {
		vex_fatal_scratch[0] = 0xFA7A0000u | (reason & 0xFFFFu);
		vex_fatal_scratch[1] = esf ? (uint32_t)esf->mepc : 0xDEADBEEFu;
		vex_fatal_scratch[2] = esf ? (uint32_t)esf->mstatus : 0xDEADBEEFu;
		vex_fatal_scratch[3] = esf ? (uint32_t)esf->a0 : 0xDEADBEEFu;
	}

	/* A fence would not help here: it orders accesses but never writes a
	 * D-cache line back, and this core has no Zicbom cbo.clean (it traps
	 * as illegal-instruction, which would turn one fatal into a fault
	 * storm and clobber the captured (reason, mepc)). To make our scratch
	 * stores visible to JTAG-AXI despite the D-cache, read 128 KiB of
	 * unrelated cached RAM to force natural capacity eviction of the
	 * scratch line. The span starts at the end of the image, so it never
	 * holds the scratch line itself (.noinit sits below _end), and it must
	 * lie in the D-cache aperture (0x90000000-0x97FFFFFF): reads from the
	 * uncached DMA window bypass the cache and would evict nothing. It is
	 * clipped to the end of zephyr,sram on boards with little RAM.
	 */
	{
		extern char _end[];
		uintptr_t start = ROUND_UP((uintptr_t)_end, 64);
		uintptr_t stop = MIN(start + KB(128),
				     DT_REG_ADDR(DT_CHOSEN(zephyr_sram)) +
				     DT_REG_SIZE(DT_CHOSEN(zephyr_sram)));

		for (uintptr_t addr = start; addr < stop; addr += sizeof(uint32_t)) {
			(void)*(volatile uint32_t *)addr;
		}
	}

	for (;;) {
		__asm__ volatile("" ::: "memory");
	}
}
