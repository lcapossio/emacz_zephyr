#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

"""Check host tools needed for emacZero Zephyr development."""

from __future__ import annotations

import shutil
import sys


REQUIRED_TOOL_GROUPS = (
    ("git",),
    ("python", "python3"),
    ("west",),
    ("cmake",),
    ("ninja",),
)

MBV32_TOOLCHAINS = (
    "riscv64-unknown-elf-gcc",
    "riscv64-xilinx-elf-gcc",
    "riscv64-zephyr-elf-gcc",
    "riscv32-unknown-elf-gcc",
)


def main() -> int:
    skip_toolchain = "--skip-toolchain" in sys.argv[1:]
    missing = [
        "/".join(group)
        for group in REQUIRED_TOOL_GROUPS
        if not any(shutil.which(tool) is not None for tool in group)
    ]
    if missing:
        print("Missing required tools in PATH: " + ", ".join(missing), file=sys.stderr)
        return 1

    available_toolchains = [tool for tool in MBV32_TOOLCHAINS if shutil.which(tool) is not None]
    if not skip_toolchain and not available_toolchains:
        print(
            "No supported MicroBlaze V RISC-V cross compiler found in PATH. "
            "Install or source the AMD/Xilinx, GNU RISC-V, or Zephyr SDK toolchain "
            "before building.",
            file=sys.stderr,
        )
        return 1

    print("Host tools OK")
    if available_toolchains:
        print("Detected cross compiler(s): " + ", ".join(available_toolchains))
    else:
        print("Toolchain check skipped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
