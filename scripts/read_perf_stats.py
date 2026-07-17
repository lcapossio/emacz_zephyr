#!/usr/bin/env python3
"""Read the emacZero Zephyr perf page from DDR over fcapz EJTAG-AXI."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "fcapz" / "host"))

from fcapz.ejtagaxi import EjtagAxiController  # noqa: E402
from fcapz.transport import XilinxHwServerTransport  # noqa: E402


FIELDS = (
    ("magic", "u32"),
    ("version", "u32"),
    ("cycles_per_sec", "u32"),
    ("rx_pool_size", "u32"),
    ("uptime_ms", "u32"),
    ("cycle_delta_1s", "u32"),
    ("cycle_delta_30s", "u32"),
    ("mac_rx_frames", "u32"),
    ("mac_rx_bytes", "u32"),
    ("mac_rx_err", "u32"),
    ("mac_rx_err_align", "u32"),
    ("mac_rx_err_overflow", "u32"),
    ("mac_rx_err_oversize", "u32"),
    ("mac_rx_bcast", "u32"),
    ("mac_rx_mcast", "u32"),
    ("mac_rx_size_1024_1518", "u32"),
    ("gate_magic", "u32"),
    ("gate_good_frames", "u32"),
    ("gate_dropped_bad_frames", "u32"),
    ("gate_dropped_overflow_frames", "u32"),
    ("gate_drain_samples", "u32"),
    ("gate_drain_cycles_total", "u32"),
    ("gate_drain_cycles_max", "u32"),
    ("gate_drain_lt_50us", "u32"),
    ("gate_drain_50_100us", "u32"),
    ("gate_drain_100_200us", "u32"),
    ("gate_drain_200_500us", "u32"),
    ("gate_drain_ge_500us", "u32"),
    ("gate_drain_tready_low_cycles", "u32"),
    ("gate_drain_tready_low_cycles_max", "u32"),
    ("gate_drain_tready_low_samples", "u32"),
    ("_reserved_v12", "u32"),
    ("dma_callbacks", "u64"),
    ("dma_errors", "u64"),
    ("dma_callback_gap_cycles_max", "u32"),
    ("dma_callback_gap_ge_1ms", "u32"),
    ("rx_refill_cycles_max", "u32"),
    ("rx_refill_cycles_ge_1ms", "u32"),
    ("rx_refill_queued_max", "u32"),
    ("_reserved_v10", "u32"),
    ("rx_bd_hw_completed", "u64"),
    ("rx_bd_refilled", "u64"),
    ("rx_bd_tail_updates", "u64"),
    ("rx_bd_no_free", "u64"),
    ("rx_irq_count", "u64"),
    ("rx_bd_available_current", "u32"),
    ("rx_bd_available_min", "u32"),
    ("rx_poll_completed_max", "u32"),
    ("rx_bd_errors", "u32"),
    ("_reserved_v11", "u32"),
    ("rx_worker_packets", "u64"),
    ("rx_invalid", "u64"),
    ("rx_alloc_pkt_fail", "u64"),
    ("rx_alloc_frag_fail", "u64"),
    ("rx_alloc_pkt_zc_fail", "u64"),
    ("rx_alloc_pkt_copy_fail", "u64"),
    ("rx_copy_write_fail", "u64"),
    ("rx_zero_copy_submit", "u64"),
    ("rx_copy_submit", "u64"),
    ("rx_net_recv_fail", "u64"),
    ("rx_released", "u64"),
    ("rx_refill_calls", "u64"),
    ("rx_refill_queued", "u64"),
    ("rx_refill_no_free", "u64"),
    ("rx_dma_config_calls", "u64"),
    ("rx_dma_reload_calls", "u64"),
    ("rx_dma_start_calls", "u64"),
    ("rx_dma_config_fail", "u64"),
    ("rx_dma_reload_fail", "u64"),
    ("rx_dma_start_fail", "u64"),
    ("rx_pool_inflight_current", "u32"),
    ("rx_pool_inflight_high", "u32"),
    ("rx_free_current", "u32"),
    ("rx_dma_fifo_current", "u32"),
    ("rx_ready_fifo_current", "u32"),
    ("rx_worker_current", "u32"),
    ("rx_stack_owned_current", "u32"),
    ("rx_owner_sum_current", "u32"),
    ("rx_owner_sum_bad", "u32"),
    ("rx_max_dma_inflight", "u32"),
    ("rx_max_stack_owned", "u32"),
    ("rx_min_free", "u32"),
    ("rx_dwell_samples", "u64"),
    ("rx_dwell_cycles_total", "u64"),
    ("rx_dwell_cycles_max", "u32"),
    ("rx_dwell_lt_1ms", "u32"),
    ("rx_dwell_1_5ms", "u32"),
    ("rx_dwell_5_20ms", "u32"),
    ("rx_dwell_20_100ms", "u32"),
    ("rx_dwell_ge_100ms", "u32"),
    ("net_udp_recv", "u32"),
    ("net_udp_drop", "u32"),
    ("net_ipv4_recv", "u32"),
    ("net_ipv4_drop", "u32"),
    ("net_processing_error", "u32"),
    ("net_pkt_filter_rx_drop", "u32"),
    ("net_pkt_filter_rx_ipv4_drop", "u32"),
    ("net_pkt_filter_rx_local_drop", "u32"),
    ("_reserved_v13", "u32"),
    ("sink_packets", "u64"),
    ("sink_bytes", "u64"),
    ("sink_recv_errors", "u64"),
    ("sink_eagain", "u64"),
    ("sink_recvfrom_calls", "u64"),
    ("sink_recvfrom_cycles_total", "u64"),
    ("sink_recvfrom_cycles_max", "u32"),
    ("sink_last_errno", "u32"),
    ("sink_first_cycle", "u32"),
    ("sink_last_cycle", "u32"),
    ("sink_last_len", "u32"),
    ("net_ip_vhlerr", "u32"),
    ("net_ip_hblenerr", "u32"),
    ("net_ip_lblenerr", "u32"),
    ("net_ip_fragerr", "u32"),
    ("net_ip_chkerr", "u32"),
    ("net_ip_protoerr", "u32"),
    ("net_udp_chkerr", "u32"),
    ("net_icmp_recv", "u32"),
    ("net_icmp_sent", "u32"),
    ("net_icmp_drop", "u32"),
    ("net_icmp_typeerr", "u32"),
    ("rx_last_icmp_src", "u32"),
    ("rx_last_icmp_dst", "u32"),
    ("rx_last_icmp_id", "u32"),
    ("rx_last_icmp_seq", "u32"),
    ("rx_pre_dst_me", "u32"),
    ("rx_pre_dst_broadcast", "u32"),
    ("rx_pre_dst_multicast", "u32"),
    ("rx_pre_dst_other", "u32"),
    ("rx_pre_type_ipv4", "u32"),
    ("rx_pre_type_arp", "u32"),
    ("rx_pre_type_other", "u32"),
    ("rx_pre_ipv4_bad", "u32"),
    ("rx_pre_ipv4_udp", "u32"),
    ("rx_pre_udp_bad_len", "u32"),
    ("rx_pre_udp_port_5001", "u32"),
    ("rx_last_sample_len", "u32"),
    ("rx_last_sample_status", "u32"),
    ("rx_last_sample_word0", "u32"),
    ("rx_last_sample_word1", "u32"),
    ("rx_last_sample_word2", "u32"),
    ("rx_last_sample_word3", "u32"),
    ("rx_last_sample_word4", "u32"),
    ("rx_last_sample_word5", "u32"),
    ("rx_last_sample_word6", "u32"),
    ("rx_last_sample_word7", "u32"),
    ("rx_bad_sample_seen", "u32"),
    ("rx_bad_sample_len", "u32"),
    ("rx_bad_sample_status", "u32"),
    ("rx_bad_sample_word0", "u32"),
    ("rx_bad_sample_word1", "u32"),
    ("rx_bad_sample_word2", "u32"),
    ("rx_bad_sample_word3", "u32"),
    ("rx_good_sample_seen", "u32"),
    ("rx_good_sample_len", "u32"),
    ("rx_good_sample_word0", "u32"),
    ("rx_good_sample_word1", "u32"),
    ("rx_good_sample_word2", "u32"),
    ("rx_good_sample_word3", "u32"),
    ("tx_send_calls", "u64"),
    ("tx_send_read_fail", "u64"),
    ("tx_setup_calls", "u64"),
    ("tx_setup_no_dma", "u64"),
    ("tx_setup_busy", "u64"),
    ("tx_dma_config_fail", "u64"),
    ("tx_dma_reload_fail", "u64"),
    ("tx_dma_start_fail", "u64"),
    ("tx_dma_start_ok", "u64"),
    ("tx_dma_completed", "u64"),
    ("tx_dma_error", "u64"),
    ("tx_last_len", "u32"),
    ("tx_last_ret", "u32"),
    ("tx_last_word0", "u32"),
    ("tx_last_word1", "u32"),
    ("tx_last_word2", "u32"),
    ("tx_last_word3", "u32"),
    ("tx_last_icmp_src", "u32"),
    ("tx_last_icmp_dst", "u32"),
    ("tx_last_icmp_id", "u32"),
    ("tx_last_icmp_seq", "u32"),
    ("rx_ext_magic", "u32"),
    ("rx_ext_len", "u32"),
    ("rx_ext_word0", "u32"),
    ("rx_ext_word1", "u32"),
    ("rx_ext_word2", "u32"),
    ("rx_ext_word3", "u32"),
    ("rx_ext_word4", "u32"),
    ("rx_ext_word5", "u32"),
    ("rx_ext_word6", "u32"),
    ("rx_ext_word7", "u32"),
    ("rx_ext_word8", "u32"),
    ("rx_ext_word9", "u32"),
    ("rx_ext_word10", "u32"),
    ("rx_ext_word11", "u32"),
    ("rx_ext_word12", "u32"),
    ("rx_ext_word13", "u32"),
    ("rx_ext_word14", "u32"),
    ("rx_ext_word15", "u32"),
    ("tx_ext_magic", "u32"),
    ("tx_ext_len", "u32"),
    ("tx_ext_word0", "u32"),
    ("tx_ext_word1", "u32"),
    ("tx_ext_word2", "u32"),
    ("tx_ext_word3", "u32"),
    ("tx_ext_word4", "u32"),
    ("tx_ext_word5", "u32"),
    ("tx_ext_word6", "u32"),
    ("tx_ext_word7", "u32"),
    ("tx_ext_word8", "u32"),
    ("tx_ext_word9", "u32"),
    ("tx_ext_word10", "u32"),
    ("tx_ext_word11", "u32"),
    ("tx_ext_word12", "u32"),
    ("tx_ext_word13", "u32"),
    ("tx_ext_word14", "u32"),
    ("tx_ext_word15", "u32"),
)

def read_stats(addr: int = 0x9FFFF000, tap: str = "xc7a100t", chain: int = 3):
    total_bytes = 0
    for _, kind in FIELDS:
        if kind == "u64":
            total_bytes = (total_bytes + 7) & ~7
            total_bytes += 8
        else:
            total_bytes += 4
    words = (total_bytes + 3) // 4
    transport = XilinxHwServerTransport(fpga_name=tap)
    axi = EjtagAxiController(transport, chain=chain)
    axi.connect()
    try:
        chunks = []
        for offset in range(0, words, 16):
            chunks.extend(axi.burst_read(addr + offset * 4, min(16, words - offset)))
        data = b"".join(w.to_bytes(4, "little") for w in chunks)
    finally:
        axi.close()

    offset = 0
    values = {}
    for name, kind in FIELDS:
        if kind == "u64":
            offset = (offset + 7) & ~7
            values[name] = struct.unpack_from("<Q", data, offset)[0]
            offset += 8
        else:
            values[name] = struct.unpack_from("<I", data, offset)[0]
            offset += 4

    return SimpleNamespace(**values)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addr", type=lambda s: int(s, 0), default=0x9FFFF000)
    parser.add_argument("--tap", default="xc7a100t")
    parser.add_argument("--chain", type=int, default=3)
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()

    values = vars(read_stats(args.addr, args.tap, args.chain))

    interesting = {
        "magic", "version", "uptime_ms",
        "mac_rx_frames", "mac_rx_bytes", "mac_rx_err",
        "gate_good_frames", "gate_dropped_bad_frames", "gate_dropped_overflow_frames",
        "dma_callbacks", "dma_errors", "rx_bd_hw_completed", "rx_irq_count",
        "rx_worker_packets", "rx_invalid", "rx_alloc_pkt_fail", "rx_alloc_frag_fail",
        "rx_zero_copy_submit", "rx_copy_submit", "rx_net_recv_fail", "rx_released",
        "rx_free_current", "rx_dma_fifo_current", "rx_ready_fifo_current",
        "rx_worker_current", "rx_stack_owned_current", "rx_owner_sum_bad",
        "net_ipv4_recv", "net_ipv4_drop", "net_processing_error",
        "net_pkt_filter_rx_drop", "net_pkt_filter_rx_ipv4_drop", "net_pkt_filter_rx_local_drop",
        "net_ip_chkerr", "net_ip_protoerr", "net_icmp_recv", "net_icmp_sent",
        "net_icmp_drop", "net_icmp_typeerr", "rx_last_icmp_src", "rx_last_icmp_dst",
        "rx_last_icmp_id", "rx_last_icmp_seq", "rx_pre_dst_me", "rx_pre_dst_broadcast",
        "rx_pre_type_ipv4", "rx_pre_type_arp", "rx_pre_ipv4_bad",
        "rx_last_sample_len", "rx_last_sample_status", "rx_last_sample_word0",
        "rx_last_sample_word1", "rx_last_sample_word2", "rx_last_sample_word3",
        "rx_last_sample_word4", "rx_last_sample_word5", "rx_last_sample_word6",
        "rx_last_sample_word7",
        "rx_good_sample_seen", "rx_good_sample_len", "rx_good_sample_word0",
        "rx_good_sample_word1", "rx_good_sample_word2", "rx_good_sample_word3",
        "tx_send_calls", "tx_send_read_fail", "tx_setup_calls", "tx_setup_no_dma",
        "tx_setup_busy", "tx_dma_config_fail", "tx_dma_reload_fail", "tx_dma_start_fail",
        "tx_dma_start_ok", "tx_dma_completed", "tx_dma_error", "tx_last_len",
        "tx_last_ret", "tx_last_word0", "tx_last_word1", "tx_last_word2", "tx_last_word3",
        "tx_last_icmp_src", "tx_last_icmp_dst", "tx_last_icmp_id", "tx_last_icmp_seq",
        "rx_ext_magic", "rx_ext_len", "rx_ext_word0", "rx_ext_word1", "rx_ext_word2",
        "rx_ext_word3", "rx_ext_word4", "rx_ext_word5", "rx_ext_word6", "rx_ext_word7",
        "rx_ext_word8", "rx_ext_word9", "rx_ext_word10", "rx_ext_word11", "rx_ext_word12",
        "rx_ext_word13", "rx_ext_word14", "rx_ext_word15",
        "tx_ext_magic", "tx_ext_len", "tx_ext_word0", "tx_ext_word1", "tx_ext_word2",
        "tx_ext_word3", "tx_ext_word4", "tx_ext_word5", "tx_ext_word6", "tx_ext_word7",
        "tx_ext_word8", "tx_ext_word9", "tx_ext_word10", "tx_ext_word11", "tx_ext_word12",
        "tx_ext_word13", "tx_ext_word14", "tx_ext_word15",
    }
    for name, value in values.items():
        if args.all or name in interesting:
            print(f"{name}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
