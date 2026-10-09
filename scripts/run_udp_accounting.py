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
import sys
import threading
import time

from read_perf_stats import read_stats

KEEP = [
    "mac_rx_frames",
    "gate_good_frames",
    "mac_rx_err",
    "gate_dropped_bad_frames",
    "gate_dropped_overflow_frames",
    "gate_drain_tready_low_cycles",
    "eth_rx_errors",
    "eth_rx_dma_failed",
    "net_ipv4_recv",
    "net_ipv4_drop",
    "net_udp_recv",
    "net_udp_drop",
    "net_udp_chkerr",
    "net_processing_error",
    "sink_packets",
    "sink_bytes",
    "sink_recv_errors",
    "sink_eagain",
    "sink_recvfrom_calls",
    "sink_recvfrom_cycles_total",
    "sink_recvfrom_cycles_max",
]

# The firmware refreshes the MAC and network-stack fields once a second; the
# sink fields are live. Wait this long after sending before the final read.
SETTLE_S = 1.5

# Printed, with the send duration in seconds, once the first stats read is
# done; JTAG is idle from here until the final read. The load starts now,
# or with --stdin-control once the first line arrives.
SENDING_MARKER = "sending_s="

# Printed when the load ends: "stdin" if --stdin-control stopped it, else
# "duration"
STOPPED_MARKER = "stopped_by="


def delta(after, before, name: str) -> int:
    return int(getattr(after, name)) - int(getattr(before, name))


def control_check(board: str, bind: str, port: int, timeout: float) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((bind, 0))
        sock.settimeout(timeout)
        sock.sendto(b"s", (board, port))
        data, addr = sock.recvfrom(2048)
    return f"{addr[0]}:{addr[1]} {data.decode('ascii', errors='replace').strip()}"


class StdinControl:
    """--stdin-control: the first line on stdin starts the load, the second
    stops it, and EOF releases the final stats read. EOF also counts as
    any line not yet seen."""

    def __init__(self) -> None:
        self.go = threading.Event()
        self.stop = threading.Event()
        self.eof = threading.Event()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self) -> None:
        for event in (self.go, self.stop):
            if not sys.stdin.readline():
                break
            event.set()
        else:
            while sys.stdin.readline():
                pass
        self.go.set()
        self.stop.set()
        self.eof.set()


def send_fast_sink(args: argparse.Namespace, stop: threading.Event | None) -> int:
    """Send the load, until the duration or stop, and return the datagram count."""
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
            if stop is not None and stop.is_set():
                stopped = "stdin"
                break
            if now - start >= args.duration:
                stopped = "duration"
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
    print(f"{STOPPED_MARKER}{stopped}")
    return packets


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addr", type=lambda s: int(s, 0), default=0x9FFFF000)
    parser.add_argument("--tap", default="xc7a100t")
    parser.add_argument("--chain", type=int, default=3,
                        help="JTAG-AXI chain (3=mbv shell, 4=vex shell)")
    parser.add_argument("--target", default="192.168.137.200")
    parser.add_argument("--bind", default="192.168.137.1")
    parser.add_argument("--port", type=int, default=5001)
    parser.add_argument("--control-port", type=int, default=5002)
    parser.add_argument("--rate-mbps", type=float, default=40.0)
    parser.add_argument("--duration", type=float, default=4.0)
    parser.add_argument("--stdin-control", action="store_true",
                        help="start sending on a first line on stdin, stop on a second "
                             "(--duration is then the cap), take the final read on EOF")
    parser.add_argument("--packet-size", type=int, default=1472)
    parser.add_argument("--timeout", type=float, default=1.0)
    parser.add_argument("--skip-control-check", action="store_true")
    parser.add_argument("--expect-min-packets", type=int, default=1)
    args = parser.parse_args()

    if not args.skip_control_check:
        try:
            reply = control_check(args.target, args.bind, args.control_port, args.timeout)
        except OSError as exc:
            print(f"control_check=fail error={exc}")
            print("hint=the control port must reply before RX tests; try the elevated host context")
            return 2
        print(f"control_check=ok reply_from={reply}")

    before = read_stats(args.addr, args.tap, args.chain)
    # A caller that runs another JTAG tool alongside (run_board_suite.py's
    # bidi step) waits for this line, and with --stdin-control times the load
    control = StdinControl() if args.stdin_control else None
    print(f"{SENDING_MARKER}{args.duration:g}", flush=True)
    if control is not None:
        control.go.wait()
    started = time.time()
    sent_frames = send_fast_sink(args, control.stop if control is not None else None)
    elapsed = time.time() - started
    time.sleep(SETTLE_S)
    if control is not None:
        control.eof.wait()
    after = read_stats(args.addr, args.tap, args.chain)

    print("sender=udp-sink")
    print(f"elapsed_s={elapsed:.3f}")
    for name in KEEP:
        print(f"{name}_delta={delta(after, before, name)}")

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
    # Frames the MAC rejected plus frames the driver dropped. The stack's
    # net_*_drop also count the host's background traffic for other
    # addresses and ports, so they are printed above but not judged.
    rx_failures = delta(after, before, "eth_rx_errors")
    dma_failures = delta(after, before, "eth_rx_dma_failed")

    if elapsed > 0:
        print(f"sink_payload_mbps={sink_bytes * 8 / elapsed / 1_000_000:.3f}")
        print(f"sent_pps={sent_frames / elapsed:.1f}")
        print(f"sent_payload_mbps={sent_frames * args.packet_size * 8 / elapsed / 1_000_000:.3f}")
        print(f"sink_pps={sink_packets / elapsed:.1f}")
    if sent_frames > 0:
        print(f"host_to_sink_delivery_pct={sink_packets * 100.0 / sent_frames:.3f}")
    if recv_calls > 0 and cycles_per_sec > 0:
        avg_cycles = recv_cycles / recv_calls
        print(f"sink_recvfrom_avg_cycles={avg_cycles:.1f}")
        print(f"sink_recvfrom_avg_us={avg_cycles * 1_000_000.0 / cycles_per_sec:.3f}")

    passed = (
        sink_packets >= args.expect_min_packets and
        sink_errors == 0 and
        gate_drops == 0 and
        rx_failures == 0 and
        dma_failures == 0
    )
    print(f"fast_sink_result={'pass' if passed else 'fail'}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
