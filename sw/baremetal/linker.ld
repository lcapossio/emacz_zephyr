/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright (c) 2026 Leonardo Capossio - bard0 design */

ENTRY(_start)

MEMORY
{
    bram (rwx) : ORIGIN = 0x80000000, LENGTH = 256K
}

SECTIONS
{
    .text : ALIGN(4)
    {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > bram

    .rodata : ALIGN(4)
    {
        *(.rodata .rodata.*)
    } > bram

    .data : ALIGN(4)
    {
        *(.sdata .sdata.*)
        *(.data .data.*)
    } > bram

    .bss (NOLOAD) : ALIGN(4)
    {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > bram

    . = ALIGN(16);
    _stack_top = ORIGIN(bram) + LENGTH(bram);
}
