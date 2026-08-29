# VexRiscv submodule patches

The submodule at `external/VexRiscv` is pinned upstream. The `*.patch` files
here are our local diffs on top of that pin. `hardware/scripts/gen_vexriscv.py`
applies them before running sbt and reverts them again in a `finally` block,
so a normal regen never leaves the submodule dirty.

The generated Verilog (`hardware/rtl/vexriscv/VexRiscvAxi4.v`) is also
checked in, so a fresh clone builds without needing sbt at all. The
regenerator is only needed when the Scala config here changes.

To regenerate:

    # On Windows, do this from WSL Ubuntu (sbt + JDK live there):
    /c/Windows/System32/wsl.exe -d Ubuntu-24.04 -- \
        bash -c 'source ~/.profile && cd /mnt/c/Projects/emacz_zephyr && \
                 python3 hardware/scripts/gen_vexriscv.py'

## Patches

- `0001-bard0-widen-caches-dynamic-target.patch`
  - IBusCachedPlugin: `cacheSize` 4 KiB → 16 KiB, prediction `STATIC` →
    `DYNAMIC_TARGET` with `historyRamSizeLog2 = 8`.
  - DBusCachedPlugin: `cacheSize` 4 KiB → 16 KiB.
  - BranchPlugin: `earlyBranch = true` (pairs with the dynamic predictor).
  - CsrPlugin: `mtvecAccess = READ_WRITE` so Zephyr can install its own
    trap vector; hardware IDs (`mvendorid`/`marchid`/`mimpid`/`mhartid`)
    hardwired to 0 and `misa` `READ_ONLY` so Zephyr's identity CSR reads
    don't trap.

Together the cache/prediction changes lift RX throughput from ~67 Mbps
to line-rate ~95 Mbps on the Arty A7-100T shell (see the commit message
that introduced these patches for the full before/after bench table).
