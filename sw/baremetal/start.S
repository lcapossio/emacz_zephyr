// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
// Minimal RV32 startup for the Arty A7 MicroBlaze V bare-metal smoke test.

    .section .text.start, "ax", @progbits
    .globl _start
    .type _start, @function
_start:
    .option push
    .option norelax
    la sp, _stack_top
    .option pop
    call main

1:
    wfi
    j 1b

    .size _start, . - _start
