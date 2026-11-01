# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

zephyr_sources(
    soc.c
    ${ZEPHYR_BASE}/soc/common/riscv-privileged/soc_irq.S
    ${ZEPHYR_BASE}/soc/common/riscv-privileged/vector.S
)
zephyr_sources_ifdef(CONFIG_ARCH_CACHE cache.c)

set(SOC_LINKER_SCRIPT ${ZEPHYR_BASE}/include/zephyr/arch/riscv/common/linker.ld CACHE INTERNAL "")
