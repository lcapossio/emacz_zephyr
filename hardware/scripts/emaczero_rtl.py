# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""emacZero RTL file list, read from the submodule's own eth_mac_sys.f."""

from __future__ import annotations

from pathlib import Path

EMACZERO_DIR = Path("external") / "emacZero"
FILELIST = "rtl/eth_mac_sys.f"


def emaczero_rtl(repo_root: Path) -> list[str]:
    """Return eth_mac_sys sources as repo-relative POSIX paths, in .f order."""
    filelist = repo_root / EMACZERO_DIR / FILELIST
    files = []
    for line in filelist.read_text(encoding="utf-8").splitlines():
        entry = line.strip()
        if entry and not entry.startswith("#"):
            files.append((EMACZERO_DIR / entry).as_posix())
    if not files:
        raise RuntimeError(f"no sources listed in {filelist}")
    return files
