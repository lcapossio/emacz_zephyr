#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

"""Run one UDP load test and print selected emacZero perf-counter deltas.

Current DDR firmware normally uses CONFIG_NET_ZPERF=n. A zperf-style sender
will time out waiting for receiver stats even when RX is healthy, because the
app-owned socket sink consumes port-5001 traffic. The default sender below
therefore uses plain UDP and treats sink_packets/sink_bytes as the pass signal.
"""

from __future__ import annotations

import argparse
import socket
import time

from read_perf_stats import read_stats


KEEP = [
    "mac_rx_frames",
    "gate_good_frames",
    "mac_rx_err",
    "gate_dropped_bad_frames",
    "gate_dropped_overflow_frames",
    "gate_drain_tready_low_cycles",
    "dma_callbacks",
    "dma_errors",
    "rx_bd_hw_completed",
    "rx_bd_errors",
    "rx_invalid",
    "rx_alloc_pkt_fail",
    "rx_alloc_frag_fail",
    "rx_alloc_pkt_zc_fail",
    "rx_alloc_pkt_copy_fail",
    "rx_copy_write_fail",
    "rx_zero_copy_submit",
    "rx_copy_submit",
    "rx_net_recv_fail",
    "rx_refill_no_free",
    "rx_stack_owned_current",
    "rx_max_stack_owned",
    "rx_pre_type_ipv4",
    "rx_pre_ipv4_udp",
    "rx_pre_udp_bad_len",
    "rx_pre_udp_port_5001",
    "net_ipv4_recv",
    "net_ipv4_drop",
    "net_udp_recv",
    "net_udp_drop",
    "net_udp_chkerr",
    "net_processing_error",
    "net_pkt_filter_rx_drop",
    "net_pkt_filter_rx_ipv4_drop",
    "net_pkt_filter_rx_local_drop",
    "sink_packets",
    "sink_bytes",
    "sink_recv_errors",
    "sink_eagain",
    "sink_recvfrom_calls",
    "sink_recvfrom_cycles_total",
    "sink_recvfrom_cycles_max",
]


def delta(after, before, name: str) -> int:
    return int(getattr(after, name)) - int(getattr(before, name))


def profile_check(board: str, bind: str, port: int, timeout: float) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((bind, 0))
        sock.settimeout(timeout)
        sock.sendto(b"s", (board, port))
        data, addr = sock.recvfrom(2048)
    return f"{addr[0]}:{addr[1]} {data.decode('ascii', errors='replace').strip()}"


def send_fast_sink(args: argparse.Namespace) -> int:
    rate_bps = args.rate_mbps * 1_000_000.0
    interval = (args.packet_size * 8.0) / rate_bps if rate_bps > 0 else 0.0
    payload = bytes((i & 0xff) for i in range(args.packet_size))
    target = (args.target, args.port)

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((args.bind, 0))
        sock.settimeout(args.timeout)

        start = time.perf_counter()
        next_send = start
        packets = 0
        while True:
            now = time.perf_counter()
            if now - start >= args.duration:
                break
            if interval > 0 and now < next_send:
                time.sleep(min(next_send - now, 0.001))
                continue
            sock.sendto(payload, target)
            packets += 1
            next_send += interval

    elapsed = time.perf_counter() - start
    sent_bytes = packets * args.packet_size
    rate = (sent_bytes * 8.0 / elapsed / 1_000_000.0) if elapsed > 0 else 0.0
    print(
        f"sender=udp-sink packets={packets} bytes={sent_bytes} "
        f"time={elapsed:.3f}s rate={rate:.3f} Mbits/sec"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addr", type=lambda s: int(s, 0), default=0x9FFFF000)
    parser.add_argument("--tap", default="xc7a100t")
    parser.add_argument("--target", default="192.168.137.200")
    parser.add_argument("--bind", default="192.168.137.1")
    parser.add_argument("--port", type=int, default=5001)
    parser.add_argument("--control-port", type=int, default=5002)
    parser.add_argument("--rate-mbps", type=float, default=40.0)
    parser.add_argument("--duration", type=float, default=4.0)
    parser.add_argument("--packet-size", type=int, default=1472)
    parser.add_argument("--timeout", type=float, default=1.0)
    parser.add_argument("--skip-profile-check", action="store_true")
    parser.add_argument("--expect-min-packets", type=int, default=1)
    args = parser.parse_args()

    if not args.skip_profile_check:
        try:
            reply = profile_check(args.target, args.bind, args.control_port, args.timeout)
        except OSError as exc:
            print(f"profile_check=fail error={exc}")
            print("hint=profile control must reply before RX tests; try the elevated host context")
            return 2
        print(f"profile_check=ok reply_from={reply}")

    before = read_stats(args.addr, args.tap)
    started = time.time()
    sender_returncode = send_fast_sink(args)
    elapsed = time.time() - started
    time.sleep(1.0)
    after = read_stats(args.addr, args.tap)

    print("sender=udp-sink")
    print(f"sender_returncode={sender_returncode}")
    print(f"elapsed_s={elapsed:.3f}")
    for name in KEEP:
        print(f"{name}_delta={delta(after, before, name)}")

    sent_frames = delta(after, before, "rx_pre_udp_port_5001")
    sink_packets = delta(after, before, "sink_packets")
    sink_bytes = delta(after, before, "sink_bytes")
    sink_errors = delta(after, before, "sink_recv_errors")
    recv_calls = delta(after, before, "sink_recvfrom_calls")
    recv_cycles = delta(after, before, "sink_recvfrom_cycles_total")
    cycles_per_sec = int(after.cycles_per_sec)
    gate_drops = (
        delta(after, before, "gate_dropped_bad_frames") +
        delta(after, before, "gate_dropped_overflow_frames")
    )
    dma_errors = delta(after, before, "dma_errors")
    rx_failures = (
        delta(after, before, "rx_bd_errors") +
        delta(after, before, "rx_invalid") +
        delta(after, before, "rx_alloc_pkt_fail") +
        delta(after, before, "rx_alloc_frag_fail") +
        delta(after, before, "rx_net_recv_fail")
    )

    if elapsed > 0:
        print(f"sink_payload_mbps={sink_bytes * 8 / elapsed / 1_000_000:.3f}")
        print(f"pre_udp_pps={sent_frames / elapsed:.1f}")
        print(f"sink_pps={sink_packets / elapsed:.1f}")
    if sent_frames > 0:
        print(f"driver_to_sink_delivery_pct={sink_packets * 100.0 / sent_frames:.3f}")
    if recv_calls > 0 and cycles_per_sec > 0:
        avg_cycles = recv_cycles / recv_calls
        print(f"sink_recvfrom_avg_cycles={avg_cycles:.1f}")
        print(f"sink_recvfrom_avg_us={avg_cycles * 1_000_000.0 / cycles_per_sec:.3f}")

    passed = (
        sink_packets >= args.expect_min_packets and
        sink_errors == 0 and
        gate_drops == 0 and
        dma_errors == 0 and
        rx_failures == 0
    )
    print(f"fast_sink_result={'pass' if passed else 'fail'}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
