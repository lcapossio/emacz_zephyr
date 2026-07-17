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

int emacz_provision_start(struct net_if *iface);
bool emacz_provision_get_ipv4(struct in_addr *addr);
bool emacz_provision_ingress(const uint8_t *payload, size_t len);

#endif /* EMACZ_PROVISION_H_ */
