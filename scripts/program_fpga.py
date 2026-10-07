#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Program a board with a shell bitstream through Vivado's hardware manager.

The default bitstream is the one the shell's build script writes
(hardware/scripts/build_arty_a7_<shell>.py, or build_zcu106.py --variant vex
for zcu106_vex). Needs vivado on PATH and the board's JTAG cable connected.
The ZCU106 R5 shell is not programmed here: its PL must come up together
with the PS, which scripts/load_zynqmp_r5.py does.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# shell -> (Vivado top, hw_device filter). On the ZCU106 the JTAG chain also
# holds the ARM DAP, so the FPGA is picked by name.
SHELLS = {
    "mbv": ("arty_a7_100t_mbv", 'PART == "xc7a100t"'),
    "vex": ("arty_a7_100t_vex", 'PART == "xc7a100t"'),
    "zcu106_vex": ("zcu106_vex", "NAME =~ xczu7*"),
}


def default_bitstream(shell: str) -> Path:
    top = SHELLS[shell][0]
    return ROOT / "build" / "vivado" / top / f"{top}_wrapper.bit"


def program_tcl(bit: Path, device_filter: str) -> str:
    return f"""\
open_hw_manager
connect_hw_server -allow_non_jtag
# open_hw_target alone opens only the first cable, and other boards may
# share the hw_server, so look for the device on every cable. A cable
# whose board is off fails to open, but stays open, and is skipped.
set filter {{{device_filter}}}
set found {{}}
foreach target [get_hw_targets] {{
    if {{[catch {{open_hw_target $target}}]}} {{
        catch {{close_hw_target $target}}
        continue
    }}
    foreach dev [get_hw_devices -quiet -of_objects $target -filter $filter] {{
        lappend found [list $target $dev]
    }}
    close_hw_target $target
}}
if {{[llength $found] != 1}} {{
    puts "ERROR: expected one device matching $filter, found [llength $found]: $found"
    exit 1
}}
lassign [lindex $found 0] target name
open_hw_target $target
set dev [get_hw_devices -of_objects $target $name]
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
    parser.add_argument("--shell", choices=sorted(SHELLS), required=True)
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
        tcl.write_text(program_tcl(bit, SHELLS[args.shell][1]), encoding="utf-8")
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
