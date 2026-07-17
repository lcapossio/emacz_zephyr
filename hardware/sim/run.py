#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

"""Compile and run hardware RTL simulations with iverilog + vvp.

Usage:
    python hardware/sim/run.py
    python hardware/sim/run.py axis_frame_error_drop
    python hardware/sim/run.py emaczero_rx_burst_backpressure_bug
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HW_RTL = ROOT / "hardware" / "rtl"
EMACZERO_RTL = ROOT / "external" / "emacZero" / "rtl"
SIM = ROOT / "hardware" / "sim"
TB = SIM / "tb"


@dataclass(frozen=True)
class Testbench:
    tb_file: Path
    rtl_sources: tuple[Path, ...]
    pass_text: str


TESTBENCHES = {
    "axis_frame_error_drop": Testbench(
        tb_file=TB / "tb_axis_frame_error_drop.v",
        rtl_sources=(
            HW_RTL / "axis_frame_error_drop.v",
        ),
        pass_text="AXIS-FRAME-ERROR-DROP: ALL TESTS PASSED",
    ),
    "emaczero_rx_burst_backpressure_bug": Testbench(
        tb_file=TB / "tb_emaczero_rx_burst_backpressure_bug.v",
        rtl_sources=(
            EMACZERO_RTL / "crc32.v",
            EMACZERO_RTL / "sync_fifo.v",
            EMACZERO_RTL / "eth_mac_tx.v",
            EMACZERO_RTL / "eth_mac_rx.v",
        ),
        pass_text="EMACZERO-RX-BURST-BACKPRESSURE-BUG: ALL TESTS PASSED",
    ),
}

DEFAULT_TESTBENCHES = tuple(TESTBENCHES)


def run_cmd(cmd: list[str], label: str) -> subprocess.CompletedProcess[str]:
    print(f"[sim] {label}: {' '.join(str(c) for c in cmd)}", flush=True)
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def print_output(result: subprocess.CompletedProcess[str]) -> None:
    if result.stdout:
        print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")


def compile_tb(name: str, tb: Testbench) -> Path | None:
    out_vvp = SIM / f"{name}_tb.vvp"
    cmd = [
        "iverilog",
        "-g2012",
        "-Wall",
        "-I",
        str(HW_RTL),
        "-I",
        str(EMACZERO_RTL),
        "-o",
        str(out_vvp),
        str(tb.tb_file),
        *[str(src) for src in tb.rtl_sources],
    ]
    result = run_cmd(cmd, f"compile {name}")
    print_output(result)
    if result.returncode != 0:
        print(f"[sim] FAILED: compile {name}")
        return None
    return out_vvp


def run_tb(name: str) -> bool:
    tb = TESTBENCHES[name]
    out_vvp = compile_tb(name, tb)
    if out_vvp is None:
        return False

    result = run_cmd(["vvp", str(out_vvp)], f"simulate {name}")
    print_output(result)

    passed = result.returncode == 0 and tb.pass_text in result.stdout
    if passed:
        print(f"[sim] PASS: {name}")
        return True

    print(f"[sim] FAILED: {name}")
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("testbench", nargs="*", help="testbench name(s) to run")
    args = parser.parse_args()

    SIM.mkdir(parents=True, exist_ok=True)

    requested = args.testbench or list(DEFAULT_TESTBENCHES)
    unknown = [name for name in requested if name not in TESTBENCHES]
    if unknown:
        print(f"Unknown testbench(es): {unknown}")
        print(f"Available: {list(TESTBENCHES)}")
        return 1

    failures: list[str] = []
    for name in requested:
        print(f"\n{'=' * 60}")
        print(f" Running: {name}")
        print(f"{'=' * 60}")
        if not run_tb(name):
            failures.append(name)

    print(f"\n{'=' * 60}")
    if failures:
        print(f"FAILED: {failures}")
        return 1

    print(f"All {len(requested)} hardware simulation target(s) matched expectations.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
