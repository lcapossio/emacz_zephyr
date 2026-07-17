#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Apply this repository's Zephyr patches after ``west update``."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PATCH_DIR = ROOT / "patches" / "zephyr"


def west_zephyr_dir() -> Path | None:
    try:
        result = subprocess.run(
            ["west", "list", "zephyr", "-f", "{abspath}"],
            cwd=ROOT,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError:
        return None

    if result.returncode != 0 or not result.stdout.strip():
        return None
    return Path(result.stdout.strip()).resolve()


def find_zephyr_dir(explicit: Path | None = None) -> Path | None:
    if explicit is not None:
        return explicit.resolve() if explicit.is_dir() else None

    zephyr_base = os.environ.get("ZEPHYR_BASE")
    if zephyr_base:
        candidate = Path(zephyr_base)
        if candidate.is_dir():
            return candidate.resolve()

    candidate = west_zephyr_dir()
    if candidate is not None and candidate.is_dir():
        return candidate

    for candidate in (ROOT / "deps" / "zephyr", ROOT.parent / "deps" / "zephyr"):
        if candidate.is_dir():
            return candidate.resolve()
    return None


def git_apply(
    zephyr_dir: Path, args: list[str], patch: Path
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(zephyr_dir), "apply", *args, str(patch)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--zephyr-dir",
        type=Path,
        help="override Zephyr checkout (normally discovered through west)",
    )
    args = parser.parse_args()

    zephyr_dir = find_zephyr_dir(args.zephyr_dir)
    if zephyr_dir is None:
        print(
            "cannot locate the Zephyr checkout; run 'west update', set "
            "ZEPHYR_BASE, or pass --zephyr-dir",
            file=sys.stderr,
        )
        return 1

    patches = sorted(PATCH_DIR.glob("*.patch"))
    if not patches:
        print("no Zephyr patches found", file=sys.stderr)
        return 1

    for patch in patches:
        check = git_apply(zephyr_dir, ["--check"], patch)
        if check.returncode == 0:
            apply = git_apply(zephyr_dir, [], patch)
            if apply.returncode != 0:
                print(apply.stderr, file=sys.stderr)
                return apply.returncode
            print(f"applied {patch.relative_to(ROOT)}")
            continue

        reverse_check = git_apply(zephyr_dir, ["--reverse", "--check"], patch)
        if reverse_check.returncode == 0:
            print(f"already applied {patch.relative_to(ROOT)}")
            continue

        print(f"cannot apply {patch.relative_to(ROOT)}", file=sys.stderr)
        print(check.stderr, file=sys.stderr)
        return check.returncode or 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
