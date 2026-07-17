/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 */
#ifndef ETH_EMACZERO_H_
#define ETH_EMACZERO_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct net_if;

typedef bool (*emaczero_rx_interceptor_t)(const uint8_t *frame, size_t len, void *user_data);

int emaczero_send_raw_frame(struct net_if *iface, const uint8_t *frame, size_t len);
int emaczero_set_rx_interceptor(struct net_if *iface, emaczero_rx_interceptor_t interceptor,
				void *user_data);

#endif /* ETH_EMACZERO_H_ */
