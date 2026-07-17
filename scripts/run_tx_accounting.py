#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

"""Run the board-side UDP TX benchmark and print host/perf-counter deltas."""

from __future__ import annotations

import argparse
import socket
import sys
import threading
import time
from pathlib import Path

from read_perf_stats import read_stats

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "fcapz" / "host"))

from fcapz.ejtagaxi import EjtagAxiController  # noqa: E402
from fcapz.transport import XilinxHwServerTransport  # noqa: E402


REGS = {
    "tx_frames": 0x028,
    "tx_bytes": 0x02C,
    "rx_frames": 0x030,
    "rx_err": 0x038,
    "tx_sf_frames_committed": 0x1C4,
    "tx_sf_frames_drained": 0x1C8,
    "tx_sf_level_pending": 0x1CC,
    "tx_er_pulses": 0x1D0,
    "tx_er_frames": 0x1D4,
}

PERF_KEEP = [
    "tx_send_calls",
    "tx_send_read_fail",
    "tx_setup_calls",
    "tx_setup_no_dma",
    "tx_setup_busy",
    "tx_dma_config_fail",
    "tx_dma_reload_fail",
    "tx_dma_start_fail",
    "tx_dma_start_ok",
    "tx_dma_completed",
    "tx_dma_error",
    "tx_last_len",
    "tx_last_ret",
]


def read_regs(base: int, tap: str, chain: int) -> dict[str, int]:
    transport = XilinxHwServerTransport(fpga_name=tap)
    transport.connect()
    axi = EjtagAxiController(transport, chain=chain)
    axi.attach()
    try:
        return {name: axi.axi_read(base + off) for name, off in REGS.items()}
    finally:
        axi.close()


def parse_reply(text: str) -> dict[str, int]:
    out: dict[str, int] = {}
    for token in text.replace("\r", " ").replace("\n", " ").split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        try:
            out[key] = int(value, 0)
        except ValueError:
            pass
    return out


def delta(after, before, name: str) -> int:
    return int(getattr(after, name)) - int(getattr(before, name))


def profile_check(board: str, bind: str, port: int, timeout: float) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((bind, 0))
        sock.settimeout(timeout)
        sock.sendto(b"s", (board, port))
        data, addr = sock.recvfrom(2048)
    return f"{addr[0]}:{addr[1]} {data.decode('ascii', errors='replace').strip()}"


class Receiver(threading.Thread):
    def __init__(self, bind: str, port: int):
        super().__init__(daemon=True)
        self.bind = bind
        self.port = port
        self.stop = threading.Event()
        self.packets = 0
        self.bytes = 0
        self.errors = 0
        self.first_time: float | None = None
        self.last_time: float | None = None

    def run(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind((self.bind, self.port))
            sock.settimeout(0.2)
            while not self.stop.is_set():
                try:
                    data, _addr = sock.recvfrom(65535)
                except socket.timeout:
                    continue
                except OSError:
                    self.errors += 1
                    continue
                now = time.time()
                if self.first_time is None:
                    self.first_time = now
                self.last_time = now
                self.packets += 1
                self.bytes += len(data)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addr", type=lambda s: int(s, 0), default=0x9FFFF000)
    parser.add_argument("--csr-base", type=lambda s: int(s, 0), default=0x44A00000)
    parser.add_argument("--tap", default="xc7a100t")
    parser.add_argument("--chain", type=int, default=3)
    parser.add_argument("--board", default="192.168.137.200")
    parser.add_argument("--bind", default="192.168.137.1")
    parser.add_argument("--control-port", type=int, default=5002)
    parser.add_argument("--listen-port", type=int, default=5003)
    parser.add_argument("--profile-timeout", type=float, default=2.0)
    parser.add_argument("--skip-profile-check", action="store_true")
    parser.add_argument("--rate-mbps", type=float, default=0.0,
                        help="Payload pacing request; 0 means unthrottled")
    parser.add_argument("--duration", type=float, default=5.0)
    parser.add_argument("--packet-size", type=int, default=1472)
    args = parser.parse_args()

    rate_x1000 = max(0, int(round(args.rate_mbps * 1000.0)))
    duration_ms = max(1, int(round(args.duration * 1000.0)))
    command = f"t {duration_ms} {args.packet_size} {rate_x1000} {args.listen_port}"

    if not args.skip_profile_check:
        try:
            reply = profile_check(args.board, args.bind, args.control_port,
                                  args.profile_timeout)
        except OSError as exc:
            print(f"profile_check=fail error={exc}")
            print("hint=profile control must reply before TX tests; try the elevated host context")
            return 2
        print(f"profile_check=ok reply_from={reply}")

    rx = Receiver(args.bind, args.listen_port)
    rx.start()
    time.sleep(0.2)

    before_perf = read_stats(args.addr, args.tap, args.chain)
    before_regs = read_regs(args.csr_base, args.tap, args.chain)
    started = time.time()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((args.bind, 0))
        sock.settimeout(args.duration + 5.0)
        sock.sendto(command.encode("ascii"), (args.board, args.control_port))
        data, addr = sock.recvfrom(2048)
    elapsed = time.time() - started
    time.sleep(0.5)
    rx.stop.set()
    rx.join(timeout=2.0)

    after_perf = read_stats(args.addr, args.tap, args.chain)
    after_regs = read_regs(args.csr_base, args.tap, args.chain)

    reply_text = data.decode("ascii", errors="replace").strip()
    reply = parse_reply(reply_text)
    board_elapsed = reply.get("elapsed_ms", 0) / 1000.0
    board_bytes = reply.get("bytes", 0)
    host_window = 0.0
    if rx.first_time is not None and rx.last_time is not None:
        host_window = max(rx.last_time - rx.first_time, 1e-9)

    print(f"reply_from={addr[0]}:{addr[1]}")
    print(f"reply={reply_text}")
    print(f"control_elapsed_s={elapsed:.3f}")
    print(f"host_rx_packets={rx.packets}")
    print(f"host_rx_bytes={rx.bytes}")
    print(f"host_rx_errors={rx.errors}")
    if board_elapsed > 0:
        print(f"board_payload_mbps={board_bytes * 8 / board_elapsed / 1_000_000:.3f}")
        print(f"host_payload_mbps_board_window={rx.bytes * 8 / board_elapsed / 1_000_000:.3f}")
    if host_window > 0:
        print(f"host_payload_mbps_rx_window={rx.bytes * 8 / host_window / 1_000_000:.3f}")

    for name in PERF_KEEP:
        print(f"{name}_delta={delta(after_perf, before_perf, name)}")
    for name in REGS:
        print(f"{name}_delta={after_regs[name] - before_regs[name]}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
