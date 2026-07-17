// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
// MicroBlaze V bare-metal smoke test for AXI UARTLite through fcapz EJTAG-UART.

#include <stdint.h>

#define UART_BASE 0x40600000u
#define UART_RX   0x00u
#define UART_TX   0x04u
#define UART_STAT 0x08u

#define UART_STAT_RX_VALID 0x01u
#define UART_STAT_TX_FULL  0x08u

static volatile uint32_t *const uart = (volatile uint32_t *)UART_BASE;

static uint32_t reg_read(uint32_t offset)
{
    return uart[offset >> 2];
}

static void reg_write(uint32_t offset, uint32_t value)
{
    uart[offset >> 2] = value;
}

static void delay(unsigned cycles)
{
    for (volatile unsigned i = 0; i < cycles; ++i) {
    }
}

static void uart_putc(char c)
{
    while ((reg_read(UART_STAT) & UART_STAT_TX_FULL) != 0u) {
    }
    reg_write(UART_TX, (uint32_t)(uint8_t)c);
}

static int uart_getc_nonblock(void)
{
    if ((reg_read(UART_STAT) & UART_STAT_RX_VALID) == 0u) {
        return -1;
    }
    return (int)(reg_read(UART_RX) & 0xFFu);
}

static void uart_puts(const char *s)
{
    while (*s != '\0') {
        if (*s == '\n') {
            uart_putc('\r');
        }
        uart_putc(*s++);
    }
}

static void uart_puthex32(uint32_t value)
{
    static const char hex[] = "0123456789ABCDEF";

    uart_puts("0x");
    for (int shift = 28; shift >= 0; shift -= 4) {
        uart_putc(hex[(value >> shift) & 0xFu]);
    }
}

int main(void)
{
    uint32_t beat = 0;

    uart_puts("\nmbv fcapz ejtaguart smoke\n");
    uart_puts("uartlite=");
    uart_puthex32(UART_BASE);
    uart_puts("\n");
    uart_puts("type characters and they should echo through USER4\n");

    for (;;) {
        int ch = uart_getc_nonblock();
        if (ch >= 0) {
            uart_puts("rx ");
            uart_putc((char)ch);
            uart_puts("\n");
        }

        if ((beat++ & 0x3FFFFu) == 0u) {
            uart_puts("beat ");
            uart_puthex32(beat);
            uart_puts("\n");
        }
        delay(128);
    }
}
