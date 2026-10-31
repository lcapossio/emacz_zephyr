/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 */

#ifndef EMACZ_HOSTIO_H_
#define EMACZ_HOSTIO_H_

#include <zephyr/devicetree.h>
#include <zephyr/toolchain.h>

/*
 * Host-visible page at the top of the uncached DMA window, reserved by the
 * board overlay's emz_hostio node. The host tools reach it over JTAG-AXI at
 * fixed addresses, so the layout is:
 *   +0x0000 (0x9FFFE000): struct emacz_jtag_mailbox (provision.h)
 *   +0x1000 (0x9FFFF000): struct emacz_perf_stats (perf_stats.h)
 * Being uncached, plain volatile accesses see host writes and vice versa.
 */
#define EMACZ_HOSTIO_NODE DT_NODELABEL(emz_hostio)
#define EMACZ_JTAG_MAILBOX_ADDR DT_REG_ADDR(EMACZ_HOSTIO_NODE)
#define EMACZ_PERF_STATS_ADDR (DT_REG_ADDR(EMACZ_HOSTIO_NODE) + 0x1000u)
#define EMACZ_HOSTIO_SLOT_SIZE 0x1000u

BUILD_ASSERT(DT_REG_SIZE(EMACZ_HOSTIO_NODE) >= 2u * EMACZ_HOSTIO_SLOT_SIZE,
	     "emz_hostio must hold the JTAG mailbox and the perf-stats block");

#endif /* EMACZ_HOSTIO_H_ */
