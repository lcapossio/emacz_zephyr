/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 *
 * VexRiscv data cache maintenance for Zephyr's cache API.
 *
 * VexRiscv's DBusCachedPlugin decodes a custom MISC-MEM instruction
 * (funct3 = 101, rs1 = address) that works on one write-back D-cache line.
 * Bits 28, 29 and 30 of the instruction, imm bits 8, 9 and 10 of an I-type
 * encoding, select:
 *   clean       write the line back if it is dirty
 *   invalidate  drop the line
 *   index       pick the line by its index bits instead of an address hit
 * An address that misses, or lies outside the cached aperture, is a no-op.
 *
 * A clean only hands the dirty line to the victim buffer, which writes it
 * out on the D-bus. A second clean issued while that write-back is still
 * in flight can be lost: back to back, some lines of a range never reach
 * memory. An uncached read waits for the victim buffer to empty, and the
 * bus adapter holds every read until all outstanding writes are
 * acknowledged, so each cleaned line is followed by one. Once it returns,
 * the line is in memory and a DMA master started afterwards reads it.
 * FENCE cannot do this here, the core decodes it as a no-op.
 */

#include <zephyr/arch/cache.h>
#include <zephyr/arch/cpu.h>
#include <zephyr/devicetree.h>
#include <zephyr/sys/util.h>

#define LINE_SIZE CONFIG_DCACHE_LINE_SIZE

#define OP_CLEAN 0x100
#define OP_INVD  0x200
#define OP_INDEX 0x400

#define VEX_DCACHE_OP(op, addr)                                                                    \
	__asm__ volatile(".insn i 0x0f, 5, x0, %0, %1" : : "r"(addr), "i"(op) : "memory")

/* mtime: any uncached read would do, this one has no side effects */
#define DRAIN_ADDR DT_REG_ADDR(DT_INST(0, riscv_machine_timer))

static ALWAYS_INLINE void drain_writes(void)
{
	(void)sys_read32(DRAIN_ADDR);
}

/* one line; a clean waits for its write-back before the next op issues */
#define LINE_OP(op, addr)                                                                          \
	do {                                                                                       \
		VEX_DCACHE_OP(op, addr);                                                           \
		if ((op) & OP_CLEAN) {                                                             \
			drain_writes();                                                            \
		}                                                                                  \
	} while (false)

#define RANGE_OP(op, addr, size)                                                                   \
	do {                                                                                       \
		uintptr_t line = ROUND_DOWN((uintptr_t)(addr), LINE_SIZE);                         \
		uintptr_t end = (uintptr_t)(addr) + (size);                                        \
                                                                                                   \
		for (; line < end; line += LINE_SIZE) {                                            \
			LINE_OP(op, line);                                                         \
		}                                                                                  \
	} while (false)

#define ALL_OP(op)                                                                                 \
	do {                                                                                       \
		for (uintptr_t idx = 0; idx < CONFIG_VEXRISCV_DCACHE_SIZE; idx += LINE_SIZE) {     \
			LINE_OP((op) | OP_INDEX, idx);                                             \
		}                                                                                  \
	} while (false)

void arch_cache_init(void)
{
	/* the core starts with the caches on and nothing to set up */
}

void arch_dcache_enable(void)
{
	/* always on */
}

void arch_dcache_disable(void)
{
	/* cannot be turned off */
}

int arch_dcache_flush_range(void *addr, size_t size)
{
	RANGE_OP(OP_CLEAN, addr, size);
	return 0;
}

int arch_dcache_invd_range(void *addr, size_t size)
{
	RANGE_OP(OP_INVD, addr, size);
	return 0;
}

int arch_dcache_flush_and_invd_range(void *addr, size_t size)
{
	RANGE_OP(OP_CLEAN | OP_INVD, addr, size);
	return 0;
}

int arch_dcache_flush_all(void)
{
	ALL_OP(OP_CLEAN);
	return 0;
}

int arch_dcache_invd_all(void)
{
	ALL_OP(OP_INVD);
	return 0;
}

int arch_dcache_flush_and_invd_all(void)
{
	ALL_OP(OP_CLEAN | OP_INVD);
	return 0;
}
