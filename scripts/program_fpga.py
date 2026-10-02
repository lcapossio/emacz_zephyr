#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Program the Arty A7-100T with a shell bitstream through Vivado's hardware manager.

The default bitstream is the one hardware/scripts/build_arty_a7_<shell>.py
writes. Needs vivado on PATH and the board's JTAG cable connected.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PART = "xc7a100t"


def default_bitstream(shell: str) -> Path:
    top = f"arty_a7_100t_{shell}"
    return ROOT / "build" / "vivado" / top / f"{top}_wrapper.bit"


def program_tcl(bit: Path) -> str:
    return f"""\
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set devices [get_hw_devices -filter {{PART == "{PART}"}}]
if {{[llength $devices] != 1}} {{
    puts "ERROR: expected one {PART}, found [llength $devices]: $devices"
    exit 1
}}
set dev [lindex $devices 0]
current_hw_device $dev
refresh_hw_device $dev
set_property PROGRAM.FILE {{{bit.as_posix()}}} $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "PROGRAM_DONE $dev"
close_hw_target
disconnect_hw_server
close_hw_manager
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--shell", choices=("mbv", "vex"), required=True)
    parser.add_argument("--bit", type=Path, help="bitstream (default: the shell's build output)")
    args = parser.parse_args()

    bit = (args.bit or default_bitstream(args.shell)).resolve()
    if not bit.is_file():
        print(f"bitstream not found: {bit}", file=sys.stderr)
        return 1
    vivado = shutil.which("vivado")
    if vivado is None:
        print("vivado was not found in PATH", file=sys.stderr)
        return 1

    # connect_hw_server starts an hw_server that outlives Vivado and keeps
    # Vivado's working directory, so run from the build tree rather than
    # from a temporary directory that has to be deleted afterwards.
    workdir = ROOT / "build" / "vivado"
    workdir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tcl = Path(tmp) / "program.tcl"
        tcl.write_text(program_tcl(bit), encoding="utf-8")
        result = subprocess.run(
            [vivado, "-mode", "batch", "-nojournal", "-nolog", "-source", str(tcl)],
            cwd=workdir, capture_output=True, text=True, check=False,
        )
    if result.returncode != 0 or "PROGRAM_DONE" not in result.stdout:
        sys.stderr.write(result.stdout[-2000:] + result.stderr[-2000:])
        return 1
    print(f"programmed {bit.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
