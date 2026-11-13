/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 *
 * VexRiscv data cache maintenance for Zephyr's cache API.
 *
 * The data cache is write-through without write allocate: every store goes
 * out on the D-bus, and the cache never holds data memory lacks. Cleaning a
 * range therefore only has to wait until the stores issued so far have
 * reached memory. The D-bus bridge holds every uncached read until all
 * outstanding writes are acknowledged (cached refills wait only for writes
 * to their own line), so one uncached read does it: once it returns,
 * a DMA master started afterwards reads what the CPU wrote. FENCE cannot,
 * this configuration decodes it as a no-op.
 *
 * DBusCachedPlugin decodes a MISC-MEM instruction (funct3 = 101, rd = x0,
 * imm[4:0] = 0) that invalidates one line, chosen by the index bits of rs1,
 * whether or not it holds that address; with rs1 = x0 it invalidates the
 * whole cache. Dropping an unrelated line that shares the index costs a
 * refill and loses no data.
 */

#include <zephyr/arch/cache.h>
#include <zephyr/arch/cpu.h>
#include <zephyr/devicetree.h>
#include <zephyr/sys/util.h>

#define LINE_SIZE CONFIG_DCACHE_LINE_SIZE

#define VEX_DCACHE_INVD_LINE(addr)                                                                 \
	__asm__ volatile(".insn i 0x0f, 5, x0, %0, 0" : : "r"(addr) : "memory")
#define VEX_DCACHE_INVD_ALL() __asm__ volatile(".insn i 0x0f, 5, x0, x0, 0" : : : "memory")

/* mtime: any uncached read would do, this one has no side effects */
#define DRAIN_ADDR DT_REG_ADDR(DT_INST(0, riscv_machine_timer))

static ALWAYS_INLINE void drain_writes(void)
{
	(void)sys_read32(DRAIN_ADDR);
}

static ALWAYS_INLINE void invd_range(void *addr, size_t size)
{
	uintptr_t line = ROUND_DOWN((uintptr_t)addr, LINE_SIZE);
	uintptr_t end = (uintptr_t)addr + size;

	for (; line < end; line += LINE_SIZE) {
		VEX_DCACHE_INVD_LINE(line);
	}
}

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
	ARG_UNUSED(addr);
	ARG_UNUSED(size);

	drain_writes();
	return 0;
}

int arch_dcache_invd_range(void *addr, size_t size)
{
	invd_range(addr, size);
	return 0;
}

int arch_dcache_flush_and_invd_range(void *addr, size_t size)
{
	drain_writes();
	invd_range(addr, size);
	return 0;
}

int arch_dcache_flush_all(void)
{
	drain_writes();
	return 0;
}

int arch_dcache_invd_all(void)
{
	VEX_DCACHE_INVD_ALL();
	return 0;
}

int arch_dcache_flush_and_invd_all(void)
{
	drain_writes();
	VEX_DCACHE_INVD_ALL();
	return 0;
}
