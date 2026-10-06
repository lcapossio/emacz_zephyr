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

import fcapz_jtag  # noqa: E402


# Must match EMACZ_PERF_STATS_VERSION in app/src/perf_stats.h. FIELDS
# mirrors that layout, so any other version would be read at wrong offsets.
PERF_STATS_VERSION = 20

FIELDS = (
    ("magic", "u32"),
    ("version", "u32"),
    ("cycles_per_sec", "u32"),
    ("rx_buffer_count", "u32"),
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
    ("mac_tx_frames", "u32"),
    ("mac_tx_bytes", "u32"),
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
    ("eth_rx_errors", "u32"),
    ("eth_rx_dma_failed", "u32"),
    ("eth_tx_dma_failed", "u32"),
    ("net_ipv4_recv", "u32"),
    ("net_ipv4_drop", "u32"),
    ("net_udp_recv", "u32"),
    ("net_udp_drop", "u32"),
    ("net_udp_chkerr", "u32"),
    ("net_processing_error", "u32"),
    ("net_ip_vhlerr", "u32"),
    ("net_ip_hblenerr", "u32"),
    ("net_ip_lblenerr", "u32"),
    ("net_ip_fragerr", "u32"),
    ("net_ip_chkerr", "u32"),
    ("net_ip_protoerr", "u32"),
    ("net_icmp_recv", "u32"),
    ("net_icmp_sent", "u32"),
    ("net_icmp_drop", "u32"),
    ("net_icmp_typeerr", "u32"),
    ("sink_seq", "u32"),
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
)


def field_offsets() -> tuple[dict[str, int], int]:
    """Byte offset of every field under C natural alignment, plus total size."""
    offsets = {}
    offset = 0
    for name, kind in FIELDS:
        if kind == "u64":
            offset = (offset + 7) & ~7
            offsets[name] = offset
            offset += 8
        else:
            offsets[name] = offset
            offset += 4
    return offsets, offset


# vex's JTAG-AXI bridge rejects a 16-beat burst with SLVERR (mbv is OK);
# 15 works on both.
BURST = 15
SEQ_RETRIES = 8


def read_stats(
    addr: int = 0x9FFFF000,
    tap: str = "xc7a100t",
    chain: int = 3,
    *,
    sink_consistent: bool = True,
):
    """Read the perf-stats block over JTAG-AXI.

    With sink_consistent=False the sink_* fields may be torn. Use it only when
    the caller ignores them: under sustained sink traffic the block changes
    faster than a JTAG read completes, so a consistent copy may never come.
    """
    offsets, total_bytes = field_offsets()
    words = (total_bytes + 3) // 4
    seq_addr = addr + offsets["sink_seq"]
    axi = fcapz_jtag.axi(tap, chain)
    try:
        # The firmware updates the sink_* block under a seqlock while we read
        # it beat by beat. Bursts walk ascending addresses and sink_seq sits
        # below the block, so the copy inside `data` was read first; re-read
        # it afterwards and retry if an update was in flight or completed
        # mid-read (a torn 64-bit counter is off by 2**32).
        for _ in range(SEQ_RETRIES):
            chunks = []
            for offset in range(0, words, BURST):
                chunks.extend(axi.burst_read(addr + offset * 4, min(BURST, words - offset)))
            data = b"".join(w.to_bytes(4, "little") for w in chunks)
            if not sink_consistent:
                break
            seq_before = struct.unpack_from("<I", data, offsets["sink_seq"])[0]
            seq_after = axi.burst_read(seq_addr, 1)[0]
            if seq_before % 2 == 0 and seq_before == seq_after:
                break
        else:
            raise RuntimeError(
                f"sink_* block never read consistently in {SEQ_RETRIES} attempts"
            )
    finally:
        axi.close()

    values = {}
    for name, kind in FIELDS:
        fmt = "<Q" if kind == "u64" else "<I"
        values[name] = struct.unpack_from(fmt, data, offsets[name])[0]
    if values["version"] != PERF_STATS_VERSION:
        raise RuntimeError(
            f"perf stats layout v{values['version']} on the board, this reader "
            f"expects v{PERF_STATS_VERSION}: rebuild the firmware or update FIELDS"
        )

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
        "mac_rx_frames", "mac_rx_bytes", "mac_rx_err", "mac_tx_frames", "mac_tx_bytes",
        "gate_good_frames", "gate_dropped_bad_frames", "gate_dropped_overflow_frames",
        "eth_rx_errors", "eth_rx_dma_failed", "eth_tx_dma_failed", "net_ipv4_recv", "net_ipv4_drop", "net_udp_recv", "net_udp_drop",
        "net_processing_error", "net_ip_chkerr", "net_ip_protoerr",
        "net_icmp_recv", "net_icmp_sent", "net_icmp_drop",
        "sink_packets", "sink_bytes", "sink_recv_errors",
    }
    for name, value in values.items():
        if args.all or name in interesting:
            print(f"{name}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
