#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

"""Fault one AXI DMA channel on a running board and check the driver recovers.

The profile build's control port accepts 'f' (fault S2MM) and 'F' (fault
MM2S): the driver posts a zero-length descriptor, which halts the channel with
DMAIntErr once the engine reaches it. The driver must report the error, rebuild
both channels, and carry traffic again with exact RX accounting and a working
TX path. Needs CONFIG_ETH_EMACZERO_PROFILE.
"""

from __future__ import annotations

import argparse
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

from read_perf_stats import read_stats

SCRIPTS = Path(__file__).resolve().parent


def control(args: argparse.Namespace, command: str) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((args.bind, 0))
        sock.settimeout(args.timeout)
        sock.sendto(command.encode("ascii"), (args.board, args.control_port))
        data, _addr = sock.recvfrom(2048)
    return data.decode("ascii", errors="replace").strip()


def send_udp(args: argparse.Namespace, duration: float) -> int:
    """Send sink traffic and return the data-packet count (the FIN is extra)."""
    out = subprocess.run(
        [sys.executable, str(SCRIPTS / "zperf_udp_client.py"), args.board,
         "--bind", args.bind, "--duration", str(duration), "--rate-mbps", "60",
         "--packet-size", "1472", "--fin-retries", "1", "--timeout", "0.5"],
        capture_output=True, text=True, check=False,
    ).stdout
    match = re.search(r"sent packets=(\d+)", out)
    if match is None:
        raise RuntimeError(f"zperf_udp_client produced no count:\n{out}")
    return int(match.group(1))


def stats(args: argparse.Namespace):
    # xsdb sometimes reports "target list is empty" when a JTAG session
    # opens right after the previous one closed; one retry after a pause
    # gets through.
    try:
        return read_stats(args.addr, args.tap, args.chain)
    except RuntimeError as exc:
        if "target list is empty" not in str(exc):
            raise
        time.sleep(2.0)
        return read_stats(args.addr, args.tap, args.chain)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--channel", choices=("rx", "tx"), default="rx")
    parser.add_argument("--addr", type=lambda s: int(s, 0), default=0x9FFFF000)
    parser.add_argument("--tap", default="xc7a100t")
    parser.add_argument("--chain", type=int, default=3)
    parser.add_argument("--board", default="192.168.137.200")
    parser.add_argument("--bind", default="192.168.137.1")
    parser.add_argument("--control-port", type=int, default=5002)
    parser.add_argument("--timeout", type=float, default=2.0)
    args = parser.parse_args()

    before = stats(args)
    reply = control(args, "f" if args.channel == "rx" else "F")
    print(f"inject_reply={reply}")
    if reply != "fault ret=0":
        print("result=FAIL (injection refused)")
        return 1

    # S2MM reaches the faulted descriptor only after every buffer posted
    # ahead of it has been filled, so push traffic through. The frames sent
    # around the halt are lost by design and not counted.
    if args.channel == "rx":
        send_udp(args, 1.0)
    time.sleep(0.5)
    faulted = stats(args)

    # Recovered: RX accounting exact again, and TX carries a control reply.
    sent = send_udp(args, 2.0)
    time.sleep(0.2)
    after = stats(args)
    tx_reply = control(args, "s")

    error_name = "dma_errors" if args.channel == "rx" else "tx_dma_error"
    checks = {
        "recovered_once": faulted.rx_dma_recoveries - before.rx_dma_recoveries == 1,
        "error_reported": getattr(faulted, error_name) > getattr(before, error_name),
        "rx_exact_after": after.sink_packets - faulted.sink_packets == sent + 1,
        "tx_after": bool(tx_reply),
        "pool_consistent": after.rx_owner_sum_bad == before.rx_owner_sum_bad,
    }
    print(f"{error_name}_delta={getattr(faulted, error_name) - getattr(before, error_name)}")
    print(f"rx_dma_recoveries_delta={after.rx_dma_recoveries - before.rx_dma_recoveries}")
    print(f"sent_after={sent} board_after={after.sink_packets - faulted.sink_packets}")
    for name, ok in checks.items():
        print(f"{name}={'ok' if ok else 'FAIL'}")
    passed = all(checks.values())
    print(f"result={'PASS' if passed else 'FAIL'}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
