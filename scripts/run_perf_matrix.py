#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Boot a shell and measure its UDP throughput the same way on every board.

After the board suite's boot and provisioning steps (run_board_suite.py),
the same loads run on every shell, so the numbers compare across boards
and image variants:

  rx@<rate>  UDP sink accounting with the host offering <rate> Mbit/s of
             payload (--rx-rates, default 20 and 90: past every soft-CPU
             shell's ceiling, and under the Arty's 100 Mbit/s link)
  tx         board UDP TX benchmark, unthrottled
  bidi       RX at --bidi-rx-mbps with the TX benchmark inside its window

Each measurement is appended to --out as one JSON line, tagged with
--label (e.g. "zcu106_vex dcache-off"), and the run ends with a summary.
"""

from __future__ import annotations

import argparse
import datetime
import json
import sys
from pathlib import Path

import emacz_config as config
import run_board_suite as suite

RX_KEYS = ("sink_payload_mbps", "host_to_sink_delivery_pct", "sent_pps", "sink_pps",
           "mac_rx_frames_delta", "eth_rx_errors_delta", "net_ipv4_drop_delta",
           "net_udp_drop_delta")
TX_KEYS = ("board_payload_mbps", "host_payload_mbps_board_window", "tx_frames_delta")


def values(lines: list[str], keys: tuple[str, ...]) -> dict[str, float]:
    found: dict[str, float] = {}
    for line in lines:
        name, sep, value = line.partition("=")
        if sep and name in keys:
            try:
                found[name] = float(value)
            except ValueError:
                pass
    return found


def rx_command(args: argparse.Namespace, shell: suite.Shell, rate: float,
               duration: float) -> list[str]:
    return [
        sys.executable, str(suite.SCRIPTS / "run_udp_accounting.py"), *suite.jtag_args(shell),
        "--addr", hex(shell.perf_stats), "--target", str(args.board_ip), "--bind", args.bind,
        "--rate-mbps", str(rate), "--duration", str(duration),
    ]


def measure_rx(args: argparse.Namespace, shell: suite.Shell, rate: float) -> dict[str, float]:
    log: list[str] = []
    suite.run(rx_command(args, shell, rate, args.rx_duration), log)
    return values(log, RX_KEYS)


def measure_tx(args: argparse.Namespace, shell: suite.Shell) -> dict[str, float]:
    log: list[str] = []
    suite.run(suite.tx_command(args, shell), log)
    return values(log, TX_KEYS)


def measure_bidi(args: argparse.Namespace, shell: suite.Shell) -> dict[str, float]:
    """As the suite's bidi step; nothing counts unless TX ran under RX load."""
    result = suite.run_bidi(args, shell)
    if result.error is not None:
        return {}
    return {**{f"rx_{k}": v for k, v in values(result.rx_log, RX_KEYS).items()},
            **{f"tx_{k}": v for k, v in values(result.tx_log, TX_KEYS).items()}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    suite.add_board_arguments(parser)
    parser.add_argument("--label", required=True, help="tag for this shell and image variant")
    parser.add_argument("--out", type=Path, default=suite.ROOT / "no_commit" / "perf_matrix.jsonl")
    parser.add_argument("--rx-rates", type=float, nargs="+", default=[20.0, 90.0])
    parser.add_argument("--rx-duration", type=float, default=5.0)
    parser.add_argument("--tx-duration", type=float, default=5.0)
    parser.add_argument("--bidi-rx-mbps", type=float, default=3.0)
    args = parser.parse_args()
    args.tx_rate_mbps = 0.0

    config.validate_config(args.board_ip, args.prefix, args.gateway)
    shell = suite.SHELLS[args.shell]
    print(f"shell={args.shell} label={args.label}", flush=True)
    if not args.skip_boot and not suite.boot(args, shell):
        print("boot failed")
        return 1
    if not suite.provision(args):
        return 1

    results: dict[str, dict[str, float]] = {}
    for rate in args.rx_rates:
        print(f"===== rx@{rate:g}", flush=True)
        results[f"rx@{rate:g}"] = measure_rx(args, shell, rate)
    print("===== tx", flush=True)
    results["tx"] = measure_tx(args, shell)
    print(f"===== bidi (rx@{args.bidi_rx_mbps:g})", flush=True)
    results["bidi"] = measure_bidi(args, shell)

    stamp = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("a", encoding="utf-8") as out:
        for test, metrics in results.items():
            out.write(json.dumps({"time": stamp, "label": args.label, "shell": args.shell,
                                  "image": str(args.image) if args.image else None,
                                  "test": test, **metrics}) + "\n")

    print("===== summary")
    complete = True
    for test, metrics in results.items():
        if test.startswith("rx@"):
            mbps = metrics.get("sink_payload_mbps")
            extra = f"delivery {metrics.get('host_to_sink_delivery_pct', float('nan')):.1f}%"
        elif test == "tx":
            mbps = metrics.get("board_payload_mbps")
            extra = ""
        else:
            mbps = metrics.get("tx_board_payload_mbps")
            extra = f"rx {metrics.get('rx_sink_payload_mbps', float('nan')):.2f} Mbit/s"
        complete &= mbps is not None
        shown = f"{mbps:.2f}" if mbps is not None else "n/a"
        print(f"{args.label:24} {test:10} {shown:>8} Mbit/s  {extra}")
    return 0 if complete else 1


if __name__ == "__main__":
    sys.exit(main())
