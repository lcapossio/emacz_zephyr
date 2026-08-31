#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Run the repository's source linters with tools resolved from PATH."""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PYTHON_SOURCES = (
    "scripts/apply_zephyr_patches.py",
    "scripts/emacz_config.py",
    "scripts/lint.py",
    "scripts/run_arty_stress.py",
    "tests/test_apply_zephyr_patches.py",
    "tests/test_emacz_config.py",
    "tests/test_run_arty_stress.py",
)
C_SOURCES = (
    "app/src/provision.c",
    "app/src/provision.h",
    "drivers/ethernet/eth_emaczero.h",
)
POLICY_SOURCES = (
    "app/src/main.c",
    "app/src/provision.c",
    "app/src/provision.h",
    "drivers/ethernet/eth_emaczero.c",
    "drivers/ethernet/eth_emaczero.h",
    *PYTHON_SOURCES,
)


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise RuntimeError(f"required tool is not in PATH: {name}")
    return path


def run(command: list[str]) -> None:
    print("+ " + " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, check=True)


def check_source_policy() -> None:
    absolute_path = re.compile(r"(?:[A-Za-z]:[\\/]|/(?:home|Users|mnt)/)")
    for relative in POLICY_SOURCES:
        text = (ROOT / relative).read_text(encoding="utf-8")
        header = "\n".join(text.splitlines()[:8])
        if "SPDX-License-Identifier:" not in header:
            raise RuntimeError(f"missing SPDX header: {relative}")
        if "Copyright (c) 2026 Leonardo Capossio - bard0 design" not in header:
            raise RuntimeError(f"missing current author/year header: {relative}")
        match = absolute_path.search(text)
        if match is not None:
            raise RuntimeError(f"hardcoded absolute path marker {match.group()!r}: {relative}")


def main() -> int:
    try:
        check_source_policy()
        ruff = require_tool("ruff")
        clang_format = require_tool("clang-format")
        run([ruff, "check", *PYTHON_SOURCES])
        run([clang_format, "--dry-run", "--Werror", *C_SOURCES])
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"lint failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
