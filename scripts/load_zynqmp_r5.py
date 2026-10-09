#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Boot a ZCU106 shell over JTAG: PL bitstream, FSBL, Zephyr on R5 #0.

xsdb puts the PS in JTAG boot mode and resets it, programs the PL, then
runs the Zynq MP FSBL that build_zcu106.py builds from the hardware design
on Cortex-R5 #0 (lockstep). The FSBL sets up the PS as on a normal boot:
psu_init, the DDR sized from the SODIMM's SPD, the TCM ECC, and, finding
the PL configured, the PS-PL isolation and PL reset. In JTAG boot mode it
then parks, and for the R5 shell xsdb loads zephyr.elf onto the same core.
The Vex shell (--shell zcu106_vex) uses the PS only for its DDR: the load
stops after the FSBL, with R5 #0 halted, and load_zephyr_bram.py then
writes the Vex image into that DDR through the PL's JTAG-AXI bridge.
The bitstream has to be in before the FSBL runs, so the order is fixed.
Every xsdb target is taken from the one JTAG cable whose PL is --tap, so
other boards on the same hw_server are never touched. Needs xsdb (Vivado
or Vitis bin) on PATH.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHELLS = ("zcu106_r5", "zcu106_vex")
ELF = ROOT / "build-zcu106-r5" / "zephyr" / "zephyr.elf"

# PS registers for JTAG boot (UG1085): CSU multiboot and the boot mode
# override in CRL_APB.BOOT_PIN_CTRL
CSU_MULTI_BOOT = 0xFFCA0010
CRL_APB_BOOT_PIN_CTRL = 0xFF5E0200
BOOT_MODE_JTAG = 0x0100
# CRL_APB.RST_LPD_TOP: R5 #0 and #1 (bits 0, 1) and the RPU AMBA
# interconnect (bit 2). The boot ROM leaves the RPU in reset in JTAG boot
# mode, and xsdb only resets a core whose interconnect is out of reset.
RST_LPD_TOP = 0xFF5E023C
RPU_CORE_RESETS = 0x3
RPU_AMBA_RESET = 0x4
# The FSBL sets bit 0 of PMU_GLOBAL.GLOB_GEN_STORAGE5 when it has finished
# (XFSBL_EXEC_COMPLETED, set in XFsbl_HandoffExit)
FSBL_DONE_REG = 0xFFD80044
FSBL_DONE_BIT = 0x1
FSBL_TIMEOUT_MS = 30000

# @NAME@ fields are filled in by xsdb_script()
XSDB_TEMPLATE = r"""
# The cable whose "PL" target is the expected part (a name prefix:
# xsdb names the ZCU106's xczu7ev "xczu7"). Another Zynq MPSoC on
# the same hw_server has PSU and R5 targets too.
proc board_cable {tap} {
    set cables {}
    foreach t [targets -target-properties] {
        if {[dict get $t name] eq "PL" && [dict exists $t jtag_device_name] &&
            [string match -nocase "$tap*" [dict get $t jtag_device_name]]} {
            lappend cables [dict get $t jtag_cable_ctx]
        }
    }
    if {[llength $cables] != 1} {
        error "expected one JTAG cable with a $tap PL, found [llength $cables]"
    }
    return [lindex $cables 0]
}

# Select the one target named like `pattern` on the board's cable.
# targets -set -filter keeps the current target when nothing matches, so
# the match is checked here.
proc select {pattern} {
    global cable
    set found {}
    foreach t [targets -target-properties] {
        if {[string match -nocase $pattern [dict get $t name]] &&
            [dict exists $t jtag_cable_ctx] && [dict get $t jtag_cable_ctx] eq $cable} {
            lappend found [dict get $t target_id]
        }
    }
    if {[llength $found] != 1} {
        error "expected one target named $pattern on $cable, found [llength $found]"
    }
    targets -set [lindex $found 0]
}

proc step {name body} {
    if {[catch {uplevel 1 $body} err]} {
        puts "ERROR: $name: $err"
        exit 1
    }
    puts "STEP $name"
}

step connect {
    @CONNECT@
    set cable [board_cable @TAP@]
    puts "CABLE $cable"
}
step jtag-boot {
    select PSU
    stop
    mwr @CSU_MULTI_BOOT@ 0
    mwr @BOOT_PIN_CTRL@ @BOOT_MODE_JTAG@
    rst -system
    after 2000
}
# fpga takes the device's top-level JTAG target, not its PL child
step fpga {
    select {PS TAP}
    fpga -file {@BIT@} -no-revision-check
}
# The RPU interconnect leaves reset with both cores held, then xsdb's R5
# reset releases R5 #0 on a branch to self in OCM, so nothing left in the
# TCMs runs before the image does
step fsbl {
    select PSU
    mwr @RST_LPD_TOP@ [expr {([mrd -value @RST_LPD_TOP@] | @RPU_CORE_RESETS@) & ~@RPU_AMBA_RESET@}]
    mwr @FSBL_DONE_REG@ [expr {[mrd -value @FSBL_DONE_REG@] & ~@FSBL_DONE_BIT@}]
    select *R5*#0
    rst -processor -clear-registers
    dow {@FSBL@}
    con
    select PSU
    set waited 0
    while {([mrd -value @FSBL_DONE_REG@] & @FSBL_DONE_BIT@) == 0} {
        if {$waited >= @FSBL_TIMEOUT_MS@} {
            error "the FSBL did not finish in @FSBL_TIMEOUT_MS@ ms"
        }
        after 100
        incr waited 100
    }
    select *R5*#0
    stop
}
"""

# Zephyr on R5 #0, after the FSBL (the R5 shell only)
XSDB_R5_TEMPLATE = r"""
step r5-load {
    select *R5*#0
    rst -processor -clear-registers
    dow {@ELF@}
}
step r5-run { con }
"""

XSDB_DONE = """
puts LOAD_DONE
exit 0
"""


def xsdb_script(bit: Path, fsbl: Path, elf: Path | None, tap: str, url: str | None) -> str:
    """The xsdb boot script; without an ELF it ends after the FSBL."""
    fields = {
        "CONNECT": f"connect -url {url}" if url else "connect",
        "TAP": tap,
        "CSU_MULTI_BOOT": f"{CSU_MULTI_BOOT:#x}",
        "BOOT_PIN_CTRL": f"{CRL_APB_BOOT_PIN_CTRL:#x}",
        "BOOT_MODE_JTAG": f"{BOOT_MODE_JTAG:#x}",
        "RST_LPD_TOP": f"{RST_LPD_TOP:#x}",
        "RPU_CORE_RESETS": f"{RPU_CORE_RESETS:#x}",
        "RPU_AMBA_RESET": f"{RPU_AMBA_RESET:#x}",
        "FSBL_DONE_REG": f"{FSBL_DONE_REG:#x}",
        "FSBL_DONE_BIT": f"{FSBL_DONE_BIT:#x}",
        "FSBL_TIMEOUT_MS": str(FSBL_TIMEOUT_MS),
        "BIT": bit.resolve().as_posix(),
        "FSBL": fsbl.resolve().as_posix(),
    }
    script = XSDB_TEMPLATE
    if elf is not None:
        fields["ELF"] = elf.resolve().as_posix()
        script += XSDB_R5_TEMPLATE
    script += XSDB_DONE
    for name, value in fields.items():
        script = script.replace(f"@{name}@", value)
    return script


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--shell", choices=SHELLS, default="zcu106_r5",
                        help="hardware shell (default zcu106_r5)")
    parser.add_argument("--elf", type=Path,
                        help=f"Zephyr image for zcu106_r5 (default {ELF.relative_to(ROOT)})")
    parser.add_argument("--bit", type=Path,
                        help="bitstream (default: the shell's build_zcu106.py output)")
    parser.add_argument("--fsbl", type=Path,
                        help="FSBL (default: the one build_zcu106.py builds for the shell)")
    parser.add_argument("--tap", default="xczu7",
                        help="JTAG name of the board's FPGA (default xczu7, the ZCU106)")
    parser.add_argument("--hw-server", default=os.environ.get("HW_SERVER_URL"),
                        help="hw_server URL (default: a local one, or $HW_SERVER_URL)")
    args = parser.parse_args()
    build = ROOT / "build" / "vivado" / args.shell
    args.bit = args.bit or build / f"{args.shell}_wrapper.bit"
    args.fsbl = args.fsbl or build / f"{args.shell}_fsbl.elf"
    if args.shell == "zcu106_r5":
        args.elf = args.elf or ELF
    elif args.elf is not None:
        parser.error("--elf applies to --shell zcu106_r5; load_zephyr_bram.py loads the Vex")

    for name in ("elf", "bit", "fsbl"):
        path = getattr(args, name)
        if path is not None and not path.is_file():
            print(f"{name} not found: {path}", file=sys.stderr)
            return 1
    xsdb = shutil.which("xsdb")
    if xsdb is None:
        print("xsdb was not found in PATH", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        script = Path(tmp) / "load_r5.tcl"
        script.write_text(xsdb_script(args.bit, args.fsbl, args.elf, args.tap, args.hw_server),
                          encoding="utf-8")
        result = subprocess.run([xsdb, str(script)], capture_output=True, text=True,
                                check=False)
    for line in result.stdout.splitlines():
        if line.startswith(("STEP", "CABLE", "ERROR")):
            print(line)
    if result.returncode != 0 or "LOAD_DONE" not in result.stdout:
        sys.stderr.write(result.stderr[-3000:])
        return 1
    print(f"R5 #0 running {args.elf.name}" if args.elf else "PS ready, R5 #0 halted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
