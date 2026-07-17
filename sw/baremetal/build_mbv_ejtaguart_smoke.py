#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Build the MicroBlaze V bare-metal EJTAG-UART smoke ELF."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "build" / "baremetal"
ELF = OUT_DIR / "mbv_ejtaguart_smoke.elf"


def tool(name: str) -> str:
    found = shutil.which(name)
    if found is None:
        raise SystemExit(f"ERROR: {name} was not found in PATH")
    return found


def main() -> int:
    gcc = tool("riscv64-unknown-elf-gcc")
    size = shutil.which("riscv64-unknown-elf-size")
    objcopy = shutil.which("riscv64-unknown-elf-objcopy")

    src_dir = Path(__file__).resolve().parent
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    cmd = [
        gcc,
        "-march=rv32imac_zicsr_zifencei",
        "-mabi=ilp32",
        "-nostdlib",
        "-nostartfiles",
        "-ffreestanding",
        "-fno-builtin",
        "-Os",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-T",
        str(src_dir / "linker.ld"),
        str(src_dir / "start.S"),
        str(src_dir / "mbv_ejtaguart_smoke.c"),
        "-o",
        str(ELF),
    ]
    subprocess.check_call(cmd, cwd=ROOT)

    if objcopy:
        subprocess.check_call(
            [objcopy, "-O", "binary", str(ELF), str(ELF.with_suffix(".bin"))],
            cwd=ROOT,
        )
    if size:
        subprocess.check_call([size, str(ELF)], cwd=ROOT)

    print(f"built {ELF.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
