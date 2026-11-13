#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Regenerate VexRiscvAxi4.v from the pinned submodule + bard0 patches.

Requires SBT + a JDK reachable via `sbt` on PATH. On Windows this project
runs sbt in WSL Ubuntu (JDK 21 + coursier sbt); native Windows sbt also
works if installed. If `sbt` is not on PATH the script tells you what to do.

Flow (all under a `try/finally` so the submodule is always reverted):

  1. Apply hardware/vexriscv_patches/*.patch to the pinned submodule.
  2. Run sbt runMain vexriscv.demo.VexRiscvAxi4WithIntegratedJtag.
  3. Strip the generation date from the Verilog header.
  4. Write the result to hardware/rtl/vexriscv/VexRiscvAxi4.v with LF
     line endings and UTF-8 (deterministic across OSes).
  5. Revert the submodule to its pinned state.

The Scala patches set everything else: the reset vector (0x9000_0000, DDR),
the cached window (0x9000_0000-0x97FF_FFFF only), the caches, the branch
predictor, the CSRs and the D-bus bridge's read ordering.
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SUBMODULE = REPO_ROOT / "external" / "VexRiscv"
PATCH_DIR = REPO_ROOT / "hardware" / "vexriscv_patches"
GEN_SRC = SUBMODULE / "VexRiscvAxi4.v"
OUT_DIR = REPO_ROOT / "hardware" / "rtl" / "vexriscv"
OUT_FILE = OUT_DIR / "VexRiscvAxi4.v"
SBT_VERSION = "1.10.11"


def run(cmd: list[str], cwd: Path, extra_env: dict | None = None) -> None:
    print(f"$ {' '.join(cmd)}  (in {cwd})", file=sys.stderr)
    subprocess.run(cmd, cwd=cwd, check=True, env=extra_env)


def apply_patches() -> list[Path]:
    applied: list[Path] = []
    for patch in sorted(PATCH_DIR.glob("*.patch")):
        run(["git", "apply", str(patch)], cwd=SUBMODULE)
        applied.append(patch)
    if not applied:
        raise RuntimeError(f"no *.patch files under {PATCH_DIR}")
    return applied


def revert_patches(applied: list[Path]) -> None:
    for patch in reversed(applied):
        subprocess.run(
            ["git", "apply", "--reverse", str(patch)],
            cwd=SUBMODULE, check=False,
        )


def sbt_regen() -> None:
    if shutil.which("sbt") is None:
        raise RuntimeError(
            "sbt not on PATH. On Windows, run this script from WSL Ubuntu "
            "with `source ~/.profile && python3 hardware/scripts/gen_vexriscv.py`."
        )
    env = None  # sbt inherits PATH/JAVA_HOME from the parent shell.
    # The submodule pins sbt 1.6.0, which cannot run on JDK 21; a newer sbt
    # builds it unchanged.
    run(
        ["sbt", f"-Dsbt.version={SBT_VERSION}",
         "runMain vexriscv.demo.VexRiscvAxi4WithIntegratedJtag"],
        cwd=SUBMODULE, extra_env=env,
    )


def patch_verilog(text: str) -> str:
    # Strip a SpinalHDL `// Date : ...` header comment, if this version emits
    # one, so the checked-in Verilog is byte-identical across regens
    # (SpinalHDL 1.13 writes the git hash instead).
    return re.sub(r"^// Date +: [^\n]*\n", "", text, count=1, flags=re.M)


def main() -> int:
    if not GEN_SRC.parent.exists():
        raise SystemExit(f"submodule missing: {SUBMODULE}")
    applied: list[Path] = []
    try:
        applied = apply_patches()
        sbt_regen()
        raw = GEN_SRC.read_text(encoding="utf-8", errors="strict")
        patched = patch_verilog(raw)
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        # newline='\n' + utf-8 -> deterministic LF output on every OS.
        with open(OUT_FILE, "w", encoding="utf-8", newline="\n") as f:
            f.write(patched)
        print(
            f"wrote {OUT_FILE} ({len(patched)} bytes)", file=sys.stderr,
        )
    finally:
        revert_patches(applied)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
