#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Apply this repository's Zephyr patches after ``west update``."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATCH_DIR = ROOT / "patches" / "zephyr"


def west_zephyr_dir() -> Path | None:
    try:
        result = subprocess.run(
            ["west", "list", "zephyr", "-f", "{abspath}"],
            cwd=ROOT,
            check=False,
            capture_output=True,
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


def git(
    zephyr_dir: Path, args: list[str], env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(zephyr_dir), *args],
        check=False,
        capture_output=True,
        text=True,
        env=env,
    )


def patch_paths(patches: list[Path]) -> list[str]:
    """Every repository path a patch series reads or writes."""
    paths: set[str] = set()
    for patch in patches:
        for line in patch.read_text(encoding="utf-8").splitlines():
            if line.startswith(("--- a/", "+++ b/")):
                paths.add(line[6:])
    return sorted(paths)


def series_state(zephyr_dir: Path, patches: list[Path]) -> int | None:
    """Return how many leading patches the checkout already carries.

    The series is stacked: later patches may edit the same files as earlier
    ones, so a patch cannot be checked against the work tree in isolation.
    Instead, rebuild HEAD plus each prefix of the series in a throwaway index
    and compare the touched paths in the work tree against it. Returns None
    when the work tree matches no prefix (local edits or a moved Zephyr).
    """
    paths = patch_paths(patches)
    with tempfile.TemporaryDirectory() as tmp:
        env = {**os.environ, "GIT_INDEX_FILE": str(Path(tmp) / "index")}
        if git(zephyr_dir, ["read-tree", "HEAD"], env).returncode != 0:
            return None
        for applied in range(len(patches) + 1):
            if applied:
                patch = str(patches[applied - 1].resolve())
                if git(zephyr_dir, ["apply", "--cached", patch], env).returncode:
                    return None
            tracked = set(git(zephyr_dir, ["ls-files", "--", *paths], env).stdout.split())
            if any((zephyr_dir / p).exists() for p in paths if p not in tracked):
                continue
            if git(zephyr_dir, ["diff", "--quiet", "--", *paths], env).returncode == 0:
                return applied
    return None


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

    applied = series_state(zephyr_dir, patches)
    if applied is None:
        print(
            f"files touched by {PATCH_DIR.relative_to(ROOT)} match neither the "
            "Zephyr revision west checked out nor any prefix of the patch "
            f"series; restore them with 'git -C {zephyr_dir} checkout -- "
            + " ".join(patch_paths(patches))
            + "' and rerun",
            file=sys.stderr,
        )
        return 1

    for patch in patches[:applied]:
        print(f"already applied {patch.relative_to(ROOT)}")
    for patch in patches[applied:]:
        result = git(zephyr_dir, ["apply", str(patch.resolve())])
        if result.returncode != 0:
            print(f"cannot apply {patch.relative_to(ROOT)}", file=sys.stderr)
            print(result.stderr, file=sys.stderr)
            return result.returncode
        print(f"applied {patch.relative_to(ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
