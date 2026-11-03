/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Leonardo Capossio - bard0 design
 *
 * The functions the MBV spends its time in under UDP RX and TX, linked
 * together at the start of .text (EMACZ_APP_HOT_TEXT). The MicroBlaze V's
 * 16 KiB I-cache is direct-mapped, so code from all over the image evicts
 * itself; packed into 15 KiB, these cannot evict each other, though
 * interrupt handlers and the functions left out still can. Functions not
 * found are skipped silently and a list made for older code moves the rest
 * around, which can cost as well as gain: after large changes, check an
 * image with read_pc_samples.py hot-check and regenerate the list.
 *
 * Generated from two app/perf/pc_sample.conf profiles of the Arty MBV shell
 * (RX flood at 90 Mbit/s, unthrottled TX), saved with
 * scripts/read_pc_samples.py read --save, then:
 *   read_pc_samples.py hot-ld --elf zephyr.elf rx.json tx.json
 */
/* 50 functions, 15360 bytes, 85% of the samples */
__emz_hot_text_start = .;
*(.text.memcpy)
*(.text.z_impl_k_mutex_unlock)
*(.text.calc_chksum)
*(.text.z_impl_k_mutex_lock)
*(.text.emz_rx_refill)
*(.text.net_conn_input)
*(.text.ethernet_send)
*(.text.net_pkt_cursor_operate)
*(.text.ethernet_recv)
*(.text.net_if_ipv4_addr_lookup_raw)
*(.text.net_try_send_data)
*(.text.dma_xilinx_axi_dma_config_reload)
*(.text.net_buf_alloc_len)
*(.text.net_if_ipv4_is_addr_bcast_raw)
*(.text.net_context_get_option)
*(.text.sys_timepoint_timeout)
*(.text.net_pkt_get_contiguous_len)
*(.text.net_pkt_alloc_buffer_with_reserve)
*(.text.net_if_tx.isra.0)
*(.text.context_sendto)
*(.text.ipv4_is_broadcast_address)
*(.text.net_udp_finalize)
*(.text.net_recv_data)
*(.text.z_impl_k_sem_give)
*(.text.net_ipv4_input)
*(.text.net_context_create_ipv4_new)
*(.text.net_ipv4_create_full)
*(.text.sys_clock_cycle_get_32)
*(.text.net_calc_chksum)
*(.text.z_impl_zsock_sendto)
*(.text.net_pkt_cursor_init)
*(.text.zvfs_get_fd_obj_and_vtable)
*(.text.net_pkt_unref)
*(.text.sys_timepoint_calc)
*(.text.net_pkt_set_data)
*(.text.zsock_sendto_ctx)
*(.text.net_pkt_available_payload_buffer)
*(.text.net_pkt_remaining_data)
*(.text.pkt_alloc_with_buffer)
*(.text.net_arp_prepare)
*(.text.memset)
*(.text.net_udp_input)
*(.text.emz_get_stats)
*(.text.k_mem_slab_alloc)
*(.text.net_pkt_read)
*(.text.net_context_packet_received)
*(.text.processing_data)
*(.text.net_buf_simple_max_len)
*(.text.atomic_get)
*(.text.sock_sendto_vmeth)
__emz_hot_text_end = .;
