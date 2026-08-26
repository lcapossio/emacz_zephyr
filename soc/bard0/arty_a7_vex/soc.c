/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 *
 * Multi-level IRQ glue for the Arty A7-100T VexRiscv-full shell. Mirrors
 * the mbv32 upstream soc.c (deps/zephyr/soc/xlnx/mbv32/soc.c) since we
 * inherit the same AXI-INTC-behind-riscv,cpu-intc topology.
 *
 *   Level 1: riscv,cpu-intc (16 M-mode lines, mie/mip CSRs)
 *   Level 2: xlnx,xps-intc @ 0x41200000 aggregated onto cpu0_intc line 11
 *
 * Without these overrides, Zephyr's default arch_irq_* helpers write bits
 * straight into mie for every irqn, which silently drops any encoded
 * 2nd-level IRQ (dma_xilinx_axi_dma_*, emz_rx_direct_isr, ...). They also
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

	/* No fence: the RISC-V `fence` opcode is not decoded by the
	 * VexRiscv-full demo config used here and raises illegal-instruction,
	 * which would turn one fatal into a fault storm and clobber the
	 * captured (reason, mepc). To make our scratch stores visible to
	 * JTAG-AXI despite the write-back D-cache, scrub one D-cache worth
	 * of unrelated cached DDR to force natural capacity eviction of the
	 * scratch line to DDR. Address must be in the CACHED range
	 * (0x90000000-0x97FFFFFF); reads from the uncached DMA region at
	 * 0x9F000000+ bypass cache entirely and would not evict anything.
	 * 0x91000000 is well past Zephyr's .text/.data and safely cached.
	 */
	{
		volatile uint32_t *evict = (volatile uint32_t *)0x91000000;
		for (int i = 0; i < 32768; i++) {
			(void)evict[i];
		}
	}

	for (;;) {
		__asm__ volatile("" ::: "memory");
	}
}
