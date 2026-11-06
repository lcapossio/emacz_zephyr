# VexRiscv submodule patches

The submodule at `external/VexRiscv` is pinned to upstream `master`
(`baf7dc82`, 2026-09-24; SpinalHDL 1.13). Upstream stopped tagging releases
after 1.0.1 (2018), which this project used until November 2026. The
`*.patch` files here are our local diffs on top of that pin.
`hardware/scripts/gen_vexriscv.py` applies them before running sbt and
reverts them again in a `finally` block, so a normal regen never leaves the
submodule dirty.

The generated Verilog (`hardware/rtl/vexriscv/VexRiscvAxi4.v`) is also
checked in, so a fresh clone builds without needing sbt at all. The
regenerator is only needed when the Scala config here changes. The
submodule pins sbt 1.6.0, which does not run on JDK 21; the script runs it
with a newer sbt (`-Dsbt.version`), which builds it unchanged.

To regenerate:

    # On Windows, do this from WSL Ubuntu (sbt + JDK live there):
    /c/Windows/System32/wsl.exe -d Ubuntu-24.04 -- \
        bash -c 'source ~/.profile && cd /mnt/c/Projects/emacz_zephyr && \
                 python3 hardware/scripts/gen_vexriscv.py'

## Patches

- `0001-bard0-emacz-shell-config.patch`, on the
  `VexRiscvAxi4WithIntegratedJtag` demo:
  - IBusCachedPlugin: `resetVector = 0x9000_0000` (DDR, where the loader
    stages `zephyr.bin`), prediction `STATIC` → `DYNAMIC_TARGET` with
    `historyRamSizeLog2 = 8`, `cacheSize` 4 KiB → 32 KiB, and
    `compressedGen` with the `injectorStage` it needs. Instruction fetch
    was Vex's bottleneck: on the Arty, the 32 KiB I-cache and compressed
    instructions together took UDP RX from 24.7 to 34.5 Mbit/s and TX from
    14.2 to 23.0 (README, Throughput). Zephyr images must then be built
    with the C extension, which `soc/bard0/vexriscv_axi/Kconfig` selects.
  - DBusCachedPlugin: `cacheSize` 4 KiB → 16 KiB.
  - StaticMemoryTranslatorPlugin: cache only 0x9000_0000-0x97FF_FFFF.
    Peripherals and the DMA memory at 0x9F00_0000 bypass the caches.
  - BranchPlugin: `earlyBranch = true` (pairs with the dynamic predictor).
  - CsrPlugin: `mtvecAccess = READ_WRITE` so Zephyr can install its own
    trap vector. The identity CSRs stay uninstalled and read as 0.

- `0002-bard0-cached-reads-bypass-writes.patch`
  - `DataCacheMemBus.toAxi4Shared` gains `cachedReadsBypassWrites`
    (default off, which leaves the stock logic). Stock, every read waits
    until all pending writes are acknowledged. With the write-through D-cache
    every store is a bus write, so each refill waits out the DDR write
    latency of the stores before it.
  - With the option on, the bridge keeps the line address of each pending
    write (up to `pendingWritesMax`, 7) and stalls a cached read only on a
    pending write to its own line. Uncached reads still wait for all of
    them. That keeps device ordering, and `cache.c`'s drain (one uncached
    read) still orders the stores before it.
  - A full write count (`pendingWritesMax` writes in flight) holds back
    only further writes; reads wait on their own hazard above. This
    measured no faster than holding back everything, nor did 15 writes in
    flight instead of 7, so the store traffic is not what limits this
    core here.
  - The cost: store -> load ordering to different lines is no longer kept
    on the bus, and FENCE, a no-op in this configuration, does not restore
    it. That is fine on this single-hart SoC with explicit cache maintenance.
    It is not fine for code that relies on FENCE to synchronise with
    another bus master through cached memory.
  - The demo top turns it on.

## What the upstream core provides without patches

The 1.0.1 pin needed two more patches, one of them a new plugin. Current
`master` makes them unnecessary:

- `FENCE` decodes as a no-op in DBusCachedPlugin (the core has no
  write-response tracking to wait for), and `FENCE.I` flushes the I-cache.
  1.0.1 trapped on both.
- The D-cache is write-through without write allocate, so it never holds
  data that memory lacks. 1.0.1's was write-back, and on that build
  back-to-back line cleans could be lost. The one cache-management
  instruction invalidates a line by index, or the whole cache with
  rs1 = x0; `soc/bard0/vexriscv_axi/cache.c` describes how Zephyr's cache
  API maps onto it.
- The core has a `softwareInterrupt` input, tied low in
  `hardware/rtl/vexriscv/vexriscv_full_axi_wrapper.v`.
