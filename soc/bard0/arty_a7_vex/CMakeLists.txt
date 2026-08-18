# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

zephyr_sources(
    ${ZEPHYR_BASE}/soc/common/riscv-privileged/soc_irq.S
    ${ZEPHYR_BASE}/soc/common/riscv-privileged/vector.S
)

set(SOC_LINKER_SCRIPT ${ZEPHYR_BASE}/include/zephyr/arch/riscv/common/linker.ld CACHE INTERNAL "")
