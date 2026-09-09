# emacz_zephyr

emacz_zephyr integrates [emacZero](https://github.com/lcapossio/emacZero) with
the AMD/Xilinx Zephyr tree for the Arty A7-100T, with two interchangeable
CPU options: AMD MicroBlaze V (`mbv32`) and SpinalHDL VexRiscv-full. Both
run the same Zephyr app and driver over the same emacZero MAC at 100 MHz.

- [Features](#features)
- [Repository Layout](#repository-layout)
- [Setup](#setup)
- [Build](#build)
- [Host-configured IPv4](#host-configured-ipv4)
- [Arty A7-100T SoC](#arty-a7-100t-soc)
- [Resource Usage and Frequency](#resource-usage-and-frequency)
- [MBV vs Vex comparison](#mbv-vs-vex-comparison)
- [Verification](#verification)
- [Author and License](#author-and-license)

## Features

- Out-of-tree Zephyr Ethernet driver and DT binding for `bard0,emaczero`.
- Arty A7-100T shells for two CPUs: AMD MicroBlaze V (`mbv32` board) and
  SpinalHDL VexRiscv-full (16 KiB I$/D$, DYNAMIC_TARGET branch predictor,
  earlyBranch, R-slice on DBUS). Same emacZero MAC + Zephyr fast-path on
  both.
- Direct AXI DMA S2MM RX ring with zero-copy handoff to the Zephyr stack and
  a copy fallback under overload.
- Optional per-region cycle instrumentation
  (`CONFIG_ETH_EMACZERO_R7_INSTRUMENTATION`, off by default).
- Application-owned high-rate UDP endpoint on port 5001 for line-rate RX
  testing, plus a normal Zephyr socket path for arbitrary traffic.
- Host-configured IPv4 — no deployment subnet baked into the firmware.
- `external/emacZero` and `fcapz` pulled in as git submodules; Zephyr is
  pinned to AMD/Xilinx `zephyr-amd` branch `xlnx_rel_v2026.1`.

## Repository Layout

- `external/emacZero/` — emacZero RTL, docs, and bare-metal SW submodule.
- `fcapz/` — fpgacapZero debug cores and host tools submodule.
- `drivers/ethernet/` — native Zephyr emacZero Ethernet driver.
- `dts/bindings/ethernet/` — Zephyr DT binding.
- `app/` — minimal Zephyr bring-up app for the Arty A7 example.
- `hardware/` — Vivado build script, RTL, XDC.
- `scripts/` — host tools (loader, provisioning, perf-stats, stress test).
- `no_commit/BUGS.md` — local bug list required by the project rules.

## Setup

```sh
python scripts/check_env.py
west init -l .
west update
python scripts/apply_zephyr_patches.py
west zephyr-export
```

The patch step asks west for the Zephyr checkout path (falls back to
`ZEPHYR_BASE`) and applies patches required by the direct AXI DMA RX-ring
path. Re-run after every `west update`.

A RISC-V cross compiler (`riscv64-unknown-elf-gcc` or the Zephyr SDK RISC-V
toolchain) must be on `PATH`. On Windows, WSL is the recommended build shell:

```sh
python3 -m pip install --user west pykwalify
export ZEPHYR_TOOLCHAIN_VARIANT=cross-compile
export CROSS_COMPILE=/usr/bin/riscv64-unknown-elf-
```

## Build

Firmware (AMD Zephyr `mbv32` board):

```sh
west build -b mbv32 app -- \
  -DZEPHYR_TOOLCHAIN_VARIANT=cross-compile \
  -DCROSS_COMPILE=/usr/bin/riscv64-unknown-elf-
```

Add `--pristine` after DT or Kconfig changes. The app registers this repo as
a Zephyr extra module, so the local driver/binding/Kconfig are picked up
automatically.

Hardware (Vivado):

```sh
# MicroBlaze V shell:
python hardware/scripts/build_arty_a7_mbv.py                     # BD only
python hardware/scripts/build_arty_a7_mbv.py --synth --jobs 2    # bitstream + XSA

# VexRiscv-full shell (regenerates VexRiscvAxi4.v via sbt on WSL):
python hardware/scripts/build_arty_a7_vex.py                     # BD only
python hardware/scripts/build_arty_a7_vex.py --synth --jobs 2    # bitstream + XSA
```

The bring-up flow avoids repeated bitstream rebuilds — load a flat
`zephyr.bin` into DDR over fcapz JTAG-AXI and release the CPU through EIO.

MicroBlaze V (fcapz USER3, chain 3):

```sh
python scripts/load_zephyr_bram.py \
  --file build-mbv-emac/zephyr/zephyr.bin \
  --addr 0x90000000
```

VexRiscv-full (fcapz USER3, chain 4):

```sh
python no_commit/vex_boot_zephyr.py \
  --file build-vex-emac/zephyr/zephyr.bin
```

## Host-configured IPv4

The board does not have a fixed IPv4 address. On every boot it uses a
MAC-derived RFC 3927 bootstrap for provisioning. The host tool discovers it
across all active IPv4 adapters and assigns the requested address:

```sh
python -m pip install psutil
python scripts/emacz_config.py discover
python scripts/emacz_config.py configure --ip 192.168.237.200 --prefix 24
```

Discovery uses ordinary UDP: broadcasts to port 5004, replies to multicast
`239.255.77.90:5004`. No raw sockets, Npcap, or admin required. Messages
include a CRC, transaction ID, target MAC, and a short-lived offer token;
this is not authentication — keep provisioning on a trusted segment.
Configuration is intentionally runtime-only and must be re-applied after a
reboot. Use `--interface NAME`, `--bind HOST_IP`, or `--mac` to disambiguate
when multiple boards or NICs are present.

The default app registers emacZero, brings up AXI DMA-backed RX/TX,
provisions IPv4 from the host, and installs a driver-level RX interceptor
for unicast UDP port 5001 that returns each DMA buffer immediately after
accounting. ARP, ICMP, port-5004 provisioning, and every other UDP port
continue through the normal Zephyr network stack.

## Arty A7-100T SoC

Two shells, one SoC. The peripheral map is identical between them; only the
CPU macro and its AXI plumbing change.

Shared SoC:

- 100 MHz `sys_clk`.
- 256 MiB DDR3 at `0x90000000` (Arty MIG). Zephyr code/data in the lower
  240 MiB; emacZero DMA buffers and SG descriptors in the upper 16 MiB at
  `0x9f000000`.
- AXI INTC `0x41200000`, AXI Timer `0x41c00000`, AXI UARTLite `0x40600000`.
- emacZero CSRs at `0x44a00000`, Xilinx AXI DMA at `0x41e00000`. MM2S feeds
  emacZero TX, S2MM receives RX.
- `axis_rx_stream_stats` at `0x41f00000` — AXI-Stream pass-through with
  AXI-Lite CSRs for observing TLAST/handshake stalls between the MII SAF and
  AXI DMA S2MM.
- Split-fabric AXI: CPU, fcapz/debug, and AXI-Lite peripherals live on a
  control interconnect; DMA SG/MM2S/S2MM reach DDR through a separate data
  interconnect and only bridge into the control fabric when SW/debug needs
  packet-buffer access.

MicroBlaze V shell (`hardware/scripts/build_arty_a7_mbv.py`, Zephyr board
target `mbv32`):

- MicroBlaze V RV32IMAC with Zicsr/Zifencei and I/D caches.
- fcapz EJTAG-AXI on BSCANE2 USER3 (chain 3), EJTAG-UART on USER4, ELA on
  USER1, EIO reset on USER1 chain 1.

VexRiscv-full shell (`hardware/scripts/build_arty_a7_vex.py`, same Zephyr
board target `mbv32`):

- SpinalHDL VexRiscv-full RV32IMA with `IBusCachedPlugin` (16 KiB I$,
  DYNAMIC_TARGET branch predictor, `historyRamSizeLog2=8`) and
  `DBusCachedPlugin` (16 KiB D$), `BranchPlugin(earlyBranch=true)`,
  `CsrPlugin` with `mtvecAccess=READ_WRITE`.
- AXI register slice on the CPU DBUS R-channel to break the CPU→xbar→I$
  combinational path — required for 100 MHz timing on Artix-7.
- fcapz EJTAG-AXI is one chain higher than MBV (chain 4 instead of 3)
  because Vex's own JTAG debug port sits ahead of it in the BSCAN chain.
  Host tools: `no_commit/vex_boot_zephyr.py` for boot,
  `no_commit/vex_set_ip.py` for provisioning.

Split-fabric AXI: MBV, fcapz/debug, and AXI-Lite peripherals live on a
control interconnect; DMA SG/MM2S/S2MM reach DDR through a separate data
interconnect and only bridge into the control fabric when SW/debug needs
packet-buffer access.

Standalone Arty A7-100T top-level RTL diagram:

<a href="docs/architecture.svg">
  <img src="docs/architecture.svg" alt="emacZero Arty A7-100T top-level RTL">
</a>

Editable source: [docs/architecture.json](docs/architecture.json).

## Resource Usage and Frequency

Vivado 2025.2 on `xc7a100tcsg324-1`, split-fabric build, both shells timing
MET at 100 MHz `sys_clk`.

| Resource | MBV | Vex | Δ (vex − mbv) |
|---|---|---|---|
| Slice LUTs | 34,688 (54.71%) | 28,909 (45.60%) | −5,779 (−16.7%) |
| Slice Registers | 46,199 (36.43%) | 29,460 (23.23%) | −16,739 (−36.2%) |
| BRAM Tiles | 44 (32.59%) | 36 (26.67%) | −8 (−18.2%) |
| DSPs | 4 (1.67%) | 4 (1.67%) | 0 |
| Setup WNS | +0.630 ns | +0.369 ns | — |

Vex is the cheaper CPU on this Artix-7 target despite carrying 16 KiB
I$/D$ and a DYNAMIC_TARGET branch predictor. Full breakdown, including
LUT-as-memory and F7/F8 wide-mux counts, is in
[docs/cpu_comparison.md](docs/cpu_comparison.md).

## MBV vs Vex comparison

Both CPUs saturate the 100 Mbps MII in both directions with zero drops.
Numbers below are delivered rate — the delta in Zephyr's `sink_packets`
from `emaczero_perf_stats` across the bench window, not iperf's offered
rate. Sender is `iperf.exe -c <board> -u -b <rate>M -t 5 -l 1472`.

| Test | MBV | Vex |
|---|---|---|
| RX single-direction | 96.0 Mbps, 0 drops | 94.5 Mbps, 0 drops |
| TX single-direction | 91.4 Mbps | 92.3 Mbps |
| RX+TX concurrent | 187.2 Mbps aggregate | 186.1 Mbps aggregate |
| % of 200 Mbps full-duplex | 93.6% | 93.1% |

At the network layer the two CPUs are indistinguishable on this SoC —
the workload is network-bound, not CPU-bound. Pick MBV for a
Vivado-native toolchain end-to-end, or Vex for the FPGA-area savings
above and a rebuild pipeline that uses SpinalHDL/sbt. See
[docs/cpu_comparison.md](docs/cpu_comparison.md) for the full
methodology, reproduction steps, and when-to-pick-which.

## Verification

Short-loop checks:

```sh
python scripts/lint.py
python -m pytest tests/test_apply_zephyr_patches.py \
  tests/test_emacz_config.py tests/test_run_arty_stress.py -q -p no:cacheprovider
python scripts/check_env.py
python hardware/sim/run.py
west build -b mbv32 app -- \
  -DZEPHYR_TOOLCHAIN_VARIANT=cross-compile \
  -DCROSS_COMPILE=/usr/bin/riscv64-unknown-elf-
```

`scripts/lint.py` resolves `ruff` and `clang-format` from `PATH`. Local
CMake/Ninja builds must use no more than half the host's logical CPUs.

Automated hardware acceptance (portable UDP, no JTAG/Npcap needed):

```sh
python -m pip install psutil
python scripts/run_arty_stress.py --interface "Ethernet 2" \
  --board-ip 192.168.237.200
```

Defaults are 600 s at 95 Mbit/s with 1472 B payloads and 100% delivery
required. Exits non-zero on any monitored MAC/gate/DMA/driver error delta.

### Throughput paths

The application registers a driver-level RX interceptor for unicast UDP
port 5001 (the "sink-bypass" fast path) and lets everything else go
through the normal Zephyr net stack. These two paths behave very
differently:

- **Sink-bypass (UDP :5001)**: line-rate on 100BASE-TX with zero MAC,
  RX-gate, S2MM `tready`-low, DMA/BD, allocation, or refill error
  deltas. Head-to-head numbers for MBV and Vex are in
  [MBV vs Vex comparison](#mbv-vs-vex-comparison).
- **Zephyr socket path (any other UDP port)**: saturates around
  ~12 Mbit/s. Driver overhead is only ~10.9% of the wall (measured via
  the gated R7 per-region counters); the remainder is Zephyr net-stack
  work on a single 100 MHz core. Reaching 25-30 Mbit/s through
  arbitrary sockets would require a stack rewrite or SMP. See
  `no_commit/BUGS.md` #33 for the analysis.

## Author and License

Author: Leonardo Capossio — [bard0 design](https://www.bard0.com) —
hello@bard0.com

This repository is licensed under Apache-2.0. The emacZero submodule carries
its own license in `external/emacZero/LICENSE`.
