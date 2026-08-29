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
  3. Post-patch the generated Verilog:
       * resetVector 0x8000_0000 -> 0x9000_0000 (DDR base — no bootrom).
       * I/O predicate: cache ONLY 0x9000_0000-0x97FF_FFFF; peripherals at
         0x4xxx_xxxx and DMA memory at 0x9F00_0000 stay uncached. Applied
         to BOTH the fetch- and memory-mmu isIoAccess drivers — the
         DYNAMIC_TARGET config emits exactly two sites.
  4. Write the result to hardware/rtl/vexriscv/VexRiscvAxi4.v with LF
     line endings and UTF-8 (deterministic across OSes).
  5. Revert the submodule to its pinned state.

Everything the CsrPlugin needs (writable mtvec, RO-zero mhartid /
mvendorid / marchid / mimpid, RO misa) is configured natively in the
Scala patch — no string-patched CSR cases here.
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
    run(
        ["sbt", "-Djava.security.manager=allow",
         "runMain vexriscv.demo.VexRiscvAxi4WithIntegratedJtag"],
        cwd=SUBMODULE, extra_env=env,
    )


def patch_verilog(text: str) -> str:
    # 0) Strip the SpinalHDL-emitted `// Date : ...` header comment so the
    #    checked-in Verilog is byte-identical across regens; without this
    #    `git diff --exit-code` after a fresh regen would spuriously fail
    #    on the timestamp alone.
    text, n_date = re.subn(r"^// Date +: [^\n]*\n", "", text, count=1, flags=re.M)
    if n_date != 1:
        raise RuntimeError(f"Date header: stripped {n_date} lines, expected 1")

    # 1) resetVector 0x8000_0000 -> 0x9000_0000 (DDR base). CPU is held
    #    in reset from bitstream program-time via cpu_reset_gpio so fcapz
    #    can stage zephyr.bin to DDR before the first fetch.
    old = "IBusCachedPlugin_fetchPc_pcReg <= (32'b10000000000000000000000000000000);"
    new = (
        "IBusCachedPlugin_fetchPc_pcReg <= (32'b10010000000000000000000000000000);   "
        "// bard0: resetVector -> 0x9000_0000 (DDR direct)"
    )
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f"resetVector anchor: {n} hits, expected 1")
    text = text.replace(old, new, 1)

    # 2) I/O predicate: cache ONLY 0x9000_0000-0x97FF_FFFF. Applies to
    #    BOTH fetch- and memory-mmu isIoAccess drivers — DYNAMIC_TARGET
    #    emits exactly two sites. Signal numbering is auto-generated so
    #    match by shape, but assert an exact count so a future config
    #    change can't silently leave one bus caching peripherals/DMA.
    pat = re.compile(
        r"assign (_zz_\d+_) = \((_zz_\d+_)\[31 : 28\] == \(4'b1111\)\);"
    )

    def repl(m: re.Match) -> str:
        return (
            f"assign {m.group(1)} = ({m.group(2)}[31 : 27] != (5'b10010));   "
            f"// bard0: cache ONLY 0x9000_0000-0x97FF_FFFF; "
            f"DMA @ 0x9F00_0000 uncached"
        )

    text, n_iopred = pat.subn(repl, text)
    if n_iopred != 2:
        raise RuntimeError(
            f"I/O predicate: patched {n_iopred} site(s), expected exactly 2 "
            f"(DYNAMIC_TARGET emits one for I-bus and one for D-bus)"
        )
    print(f"I/O predicate: patched {n_iopred} site(s)", file=sys.stderr)
    return text


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
