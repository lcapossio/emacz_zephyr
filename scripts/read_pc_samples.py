#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Arm and read the firmware's program-counter sampler over fcapz EJTAG-AXI.

Needs an image built with app/perf/pc_sample.conf and .overlay. ``arm``
starts a run; ``read`` prints the functions the busy samples landed in,
named from the ELF, and the callers of the leaf functions that take the
most samples (from ra, which is the caller while a leaf runs). ``--save``
keeps the per-function counts, ``hot-ld`` turns saved profiles into the
linker list of app/boards/<board>_hot_text.ld, and ``hot-check`` reports
what an image packed from that list.

  read_pc_samples.py --chain 4 arm
  ... run the load ...
  read_pc_samples.py --chain 4 read --elf build/zephyr/zephyr.elf --save rx.json
  read_pc_samples.py hot-ld --elf build/zephyr/zephyr.elf rx.json tx.json
  read_pc_samples.py hot-check --elf build/zephyr/zephyr.elf app/boards/mbv32_hot_text.ld

A sample that lands where interrupts come back on (an irq_unlock, the end
of a cache maintenance loop) stands for the time they were off, and one on
the first instruction of a cache line usually stands for a fetch stall.
"""

from __future__ import annotations

import argparse
import bisect
import collections
import json
import re
import sys
from pathlib import Path

from elftools.elf.elffile import ELFFile

sys.path.insert(0, str(Path(__file__).resolve().parent))

import fcapz_jtag

# Must match app/src/pc_sample.c and app/perf/pc_sample.overlay
PCS_ADDR = 0x9F800000
PCS_MAGIC = 0x50435331
HEADER_WORDS = 8
OFF_ARMED = 4
OFF_COUNT = 12
OFF_IDLE = 16
BURST = 15
# Must match the symbols hot-ld writes around the list
HOT_START = "__emz_hot_text_start"
HOT_END = "__emz_hot_text_end"


class Symbols:
    """Function symbols of an ELF, for address lookups."""

    def __init__(self, path: Path):
        funcs = []
        with path.open("rb") as f:
            symtab = ELFFile(f).get_section_by_name(".symtab")
            for sym in symtab.iter_symbols():
                if sym["st_info"]["type"] == "STT_FUNC" and sym["st_value"]:
                    funcs.append((sym["st_value"] & ~1, sym["st_size"], sym.name))
        funcs.sort()
        self.starts = [f[0] for f in funcs]
        self.funcs = funcs
        self.sizes = {name: size for _, size, name in funcs}

    def name(self, addr: int) -> str:
        i = bisect.bisect_right(self.starts, addr) - 1
        if i >= 0:
            start, size, name = self.funcs[i]
            if addr < start + max(size, 1):
                return name
        return f"0x{addr:08x}"


def arm(args: argparse.Namespace) -> int:
    bridge = fcapz_jtag.axi(args.tap, args.chain)
    try:
        magic = bridge.burst_read(args.addr, 1)[0]
        if magic != PCS_MAGIC:
            raise RuntimeError(f"no sampler at 0x{args.addr:08X} (magic 0x{magic:08X})")
        bridge.axi_write(args.addr + OFF_ARMED, 0)
        bridge.axi_write(args.addr + OFF_COUNT, 0)
        bridge.axi_write(args.addr + OFF_IDLE, 0)
        bridge.axi_write(args.addr + OFF_ARMED, 1)
    finally:
        bridge.close()
    print("armed")
    return 0


def read(args: argparse.Namespace) -> int:
    def op(axi):
        header = axi.burst_read(args.addr, HEADER_WORDS)
        if header[0] != PCS_MAGIC:
            raise RuntimeError(f"no sampler at 0x{args.addr:08X} (magic 0x{header[0]:08X})")
        count = min(header[3], header[2])
        words = []
        base = args.addr + HEADER_WORDS * 4
        for offset, span in fcapz_jtag.bursts(base, count * 2, BURST):
            words.extend(axi.burst_read(base + offset * 4, span))
        return header, words

    header, words = fcapz_jtag.read(args.tap, args.chain, op)
    armed, capacity, count, idle = header[1], header[2], min(header[3], header[2]), header[4]
    syms = Symbols(args.elf)
    pcs = words[0::2]
    ras = words[1::2]

    total = count + idle
    print(f"samples: {count} busy, {idle} idle"
          f" ({100.0 * count / total if total else 0:.1f}% busy)"
          f"{', still armed' if armed else ''}{', buffer full' if count >= capacity else ''}")
    if not count:
        return 0

    by_func = collections.Counter(syms.name(pc) for pc in pcs)
    if args.save:
        args.save.write_text(json.dumps(dict(by_func), indent=0) + "\n")
    print(f"\n{'share':>7} {'samples':>8}  function")
    for name, n in by_func.most_common(args.top):
        print(f"{100.0 * n / count:6.1f}% {n:8d}  {name}")

    callers = collections.defaultdict(collections.Counter)
    for pc, ra in zip(pcs, ras):
        callers[syms.name(pc)][syms.name(ra)] += 1
    print("\ncallers (by ra) of the top functions:")
    for name, n in by_func.most_common(args.callers):
        top = ", ".join(f"{c} {100.0 * k / n:.0f}%" for c, k in callers[name].most_common(4))
        print(f"  {name}: {top}")
    return 0


def hot_ld(args: argparse.Namespace) -> int:
    """Print the hottest functions of the saved profiles that fit the budget."""
    sizes = Symbols(args.elf).sizes
    weight: dict[str, float] = collections.defaultdict(float)
    for path in args.profiles:
        counts = json.loads(path.read_text())
        total = sum(counts.values())
        # each profile counts the same, whatever its sample count
        for name, n in counts.items():
            weight[name] += n / total

    names, used, unknown = [], 0, 0
    for name, _ in sorted(weight.items(), key=lambda kv: -kv[1]):
        size = sizes.get(name)
        if size is None:
            unknown += 1
            continue
        if used + size > args.budget:
            continue
        names.append(name)
        used += size
    covered = 100.0 * sum(weight[n] for n in names) / sum(weight.values())
    if unknown:
        print(f"{unknown} sampled names are not functions of this ELF", file=sys.stderr)
    # The sizes leave out alignment padding: hot-check measures the real span
    print(f"/* {len(names)} functions, {used} bytes, {covered:.0f}% of the samples */")
    print(f"{HOT_START} = .;")
    for name in names:
        print(f"*(.text.{name})")
    print(f"{HOT_END} = .;")
    return 0


def hot_check(args: argparse.Namespace) -> int:
    """Report the span an image packed and the listed functions left out of it."""
    listed = re.findall(r"\*\(\.text\.([^)\s]+)\)", args.list.read_text())
    marks: dict[str, int] = {}
    addrs: dict[str, list[int]] = collections.defaultdict(list)
    with args.elf.open("rb") as f:
        for sym in ELFFile(f).get_section_by_name(".symtab").iter_symbols():
            if sym.name in (HOT_START, HOT_END):
                marks[sym.name] = sym["st_value"]
            elif sym["st_info"]["type"] == "STT_FUNC":
                addrs[sym.name].append(sym["st_value"] & ~1)
    if len(marks) != 2:
        print(f"no {HOT_START}/{HOT_END} in {args.elf}: hot text is off or the list predates them")
        return 1

    start, end = marks[HOT_START], marks[HOT_END]
    # a renamed, inlined or cloned (.isra, .constprop) function matches nothing
    missing = [n for n in listed if not any(start <= a < end for a in addrs.get(n, []))]
    print(f"packed: 0x{start:08x}-0x{end:08x}, {end - start} bytes"
          f" (I-cache {args.icache} bytes)")
    print(f"listed functions packed: {len(listed) - len(missing)} of {len(listed)}")
    for name in missing:
        print(f"  not packed: {name}")
    return 0 if end - start <= args.icache and not missing else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--addr", type=lambda s: int(s, 0), default=PCS_ADDR)
    parser.add_argument("--tap", default="xc7a100t")
    parser.add_argument("--chain", type=int, default=3,
                        help="EJTAG-AXI chain: 3 for the MBV shell, 4 for the Vex")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("arm", help="clear the buffer and start recording")
    rd = sub.add_parser("read", help="read the buffer and print the profile")
    rd.add_argument("--elf", type=Path, required=True)
    rd.add_argument("--top", type=int, default=30)
    rd.add_argument("--callers", type=int, default=8)
    rd.add_argument("--save", type=Path, help="write the per-function counts as JSON")
    hl = sub.add_parser("hot-ld", help="linker list of the hottest functions")
    hl.add_argument("--elf", type=Path, required=True,
                    help="an image of the same code, for the function sizes")
    hl.add_argument("--budget", type=int, default=15360,
                    help="bytes of code to list (default 15 KiB, under a 16 KiB I-cache)")
    hl.add_argument("profiles", type=Path, nargs="+", help="JSON from read --save")
    hc = sub.add_parser("hot-check", help="what an image packed from a hot-text list")
    hc.add_argument("--elf", type=Path, required=True)
    hc.add_argument("--icache", type=int, default=16384, help="I-cache size in bytes")
    hc.add_argument("list", type=Path, help="the board's _hot_text.ld")
    args = parser.parse_args()
    return {"arm": arm, "read": read, "hot-ld": hot_ld, "hot-check": hot_check}[args.cmd](args)


if __name__ == "__main__":
    raise SystemExit(main())
