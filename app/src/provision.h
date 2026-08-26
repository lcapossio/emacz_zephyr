/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 */
#ifndef EMACZ_PROVISION_H_
#define EMACZ_PROVISION_H_

#include <stdbool.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_ip.h>

#define EMACZ_PROVISION_PORT 5004u

/* Host->board JTAG-AXI mailbox at EMACZERO_JTAG_MAILBOX_ADDR (0x9FFFE000).
 * The board polls it from the provisioning thread; the host pokes it via
 * fcapz when the network path is not yet reachable (typical bring-up).
 *
 * Wire format (little-endian, 32-byte header, matches host script):
 *   +0x00  u32 magic        = 0x50525856 ("PRVX", host writes)
 *   +0x04  u32 epoch        (host bumps each new request)
 *   +0x08  u32 ip           (network-byte-order IPv4 address)
 *   +0x0C  u32 gateway      (network-byte-order, 0 = none)
 *   +0x10  u32 prefix       (CIDR bits, 1..30)
 *   +0x14  u32 reserved     (must be 0)
 *   +0x18  u32 ack_epoch    (board mirrors epoch on success)
 *   +0x1C  i32 status       (board writes: 0 = ok, negative errno on failure)
 *
 * `magic` doubles as a sentinel: on cold boot the block is zero (or garbage
 * from a prior run), so the board only reacts when both `magic == 0x50525856`
 * AND `epoch != last_applied_epoch`. The host writes the whole header, then
 * bumps epoch last, then polls ack_epoch to observe completion.
 */
#define EMACZ_JTAG_MAILBOX_MAGIC 0x50525856u /* 'PRVX' */

struct emacz_jtag_mailbox {
	uint32_t magic;
	uint32_t epoch;
	uint32_t ip;
	uint32_t gateway;
	uint32_t prefix;
	uint32_t reserved;
	uint32_t ack_epoch;
	int32_t  status;
};

int emacz_provision_start(struct net_if *iface);
bool emacz_provision_get_ipv4(struct in_addr *addr);
bool emacz_provision_ingress(const uint8_t *payload, size_t len);

#endif /* EMACZ_PROVISION_H_ */
