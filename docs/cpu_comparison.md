# MicroBlaze V vs VexRiscv-full — Arty A7-100T SoC comparison

Two CPU options for the emacZero + Zephyr SoC on the Arty A7-100T shell.
All numbers below are measured on the same host, same PHY (Intel I226-V on
Ethernet 2 @ 100 Mbps), and the same emacZero MAC and Zephyr firmware, with
both SoCs at 100 MHz. What differs is only the CPU macro and the AXI
plumbing around it.

Bitstream provenance (both built from emacZero ab5f217, the current pin):
- **mbv**: `build/vivado/arty_a7_100t_mbv/arty_a7_100t_mbv_wrapper.bit`
  (Oct 16, 2026 — MicroBlaze V, LMB BRAM + DDR, 100 MHz SoC)
- **vex**: `build/vivado/arty_a7_100t_vex/arty_a7_100t_vex_wrapper.bit`
  (Nov 6, 2026 — VexRiscv-full, upstream `master` `baf7dc82` plus the
  bard0 patches in `hardware/vexriscv_patches/`: 32 KiB I$, compressed
  instructions, 16 KiB write-through D$, DYNAMIC_TARGET branch predictor,
  earlyBranch, D$ refills that pass pending stores to other lines; R-slice
  on DBUS)

## Throughput (delivered rate)

UDP with 1472 B payloads through Zephyr sockets on the mainline emacZero
driver, measured with `scripts/run_perf_matrix.py`: caches on, cacheable
frame buffers, 20 ms RX budget, three runs of 20 s per load, median of the
three (range where they differ). RX is the board's sink count with
90 Mbit/s offered (`scripts/run_udp_accounting.py`), over the host's
sending time. TX is the board's `zsock_sendto` loop, unthrottled, counted
by the MAC and checked against the host (`scripts/run_tx_accounting.py
--rate-mbps 0`), which received every datagram of every run.

| Test | MBV | Vex |
|---|---|---|
| RX ceiling | 30.8 Mbit/s (29.50–31.03) | 34.5 Mbit/s (34.49–34.52) |
| TX single-direction | 22.85 Mbit/s | 23.04 Mbit/s |
| TX while RX takes 3 Mbit/s | 18.05 Mbit/s | 19.62 Mbit/s |
| Full duplex, TX / RX | 10.35 / 16.66 Mbit/s | 12.69 / 15.39 Mbit/s |

The build is word copies at any alignment (`patches/zephyr/0007`), the
reserved L2 header, cacheable frame buffers kept coherent by the DMA
driver, zero-copy TX (`0009`) and MAC counters left to the L2 (`0010`); on
MBV also the hottest 15 KiB of code packed at the start of `.text`. The
README's Throughput section covers each step and the variants (RX
checksum checked, the previous VexRiscv cores). Both build with
compressed instructions. Vex has no packed-code list: its 32 KiB I-cache
already holds most of the RX and TX paths (~32 KB together).

VexRiscv `master` has only a write-through D-cache: every store, stack
spills included, goes out to DDR, at most 7 at a time. On the 1.0.1 tag
(2018), which this project used until November 2026, the D-cache was
write-back, and the same firmware measured 30.3 Mbit/s RX and 16.0 TX the
same way. Upstream stopped tagging after 1.0.1. With the 16 KiB I-cache
of that time, `master` measured 22.2 Mbit/s RX and 14.2 TX; the bridge
patch, which lets refills pass pending stores to other lines, took RX to
24.7. The store traffic was not what held it back, though: 15 writes in
flight instead of 7 changed nothing. Instruction fetch was, as the same
measurements show:

| Vex I-cache | RX | TX | TX while RX takes 3 | Full duplex, TX / RX |
|---|---|---|---|---|
| 16 KiB | 24.7 | 14.22 | 10.71 | 5.53 / 15.02 |
| 16 KiB, compressed instructions | 28.6 | 17.50 | 14.03 | 8.04 / 15.37 |
| 32 KiB | 31.7 | 18.34 | 14.77 | 9.37 / 15.38 |
| 32 KiB, compressed instructions | 34.5 | 23.04 | 19.62 | 12.69 / 15.39 |

Rates in Mbit/s, measured as above. Compressed instructions shrink the
code by a third: the RX path from ~22 KB to ~15 KB, RX and TX together
from ~47 KB to ~32 KB.

Before cacheable buffers (single 5 s runs, uncached frame buffers, the
VexRiscv 1.0.1 core of the time):

| Test | MBV | Vex |
|---|---|---|
| RX ceiling | 9.3 Mbit/s, ~790 frames/s | 9.4 Mbit/s, ~800 frames/s |
| TX single-direction | 8.9 Mbit/s | 11.5 Mbit/s |
| RX ceiling, word copies | 19.9 Mbit/s | 19.7 Mbit/s |
| TX, word copies | 15.6 Mbit/s | 15.9 Mbit/s |

*Word copies* is `app/perf/payload_align2.conf`, which aligns the app's
socket buffers with the payload so the socket copies run on words. With
uncached buffers memory latency set the RX ceiling, so it was the same on
both CPUs: the UDP payload starts 2 bytes off a word boundary, so the
socket's `memcpy` of each payload read uncached memory a byte at a time,
~1.07 ms for 1472 bytes out of ~1.25 ms per frame (probe on those builds:
~87k cycles on MBV at 81.25 MHz, ~107k on Vex at 100 MHz). With source and
destination at the same alignment the copy dropped to ~22k/27k cycles,
and from cached memory to ~3.5k/2.2k. TX copied into uncached buffers too,
a byte at a time unless aligned; Vex ran that byte-store loop ~30% faster,
and with word copies the two CPUs were level again.

Earlier revisions measured ~95 Mbit/s RX and ~91 Mbit/s TX on both CPUs.
Those numbers came from a driver-level interceptor that counted port-5001
frames without the network stack, and a TX bench that bypassed it, which
the mainline driver does not have.

## FPGA resource utilization

Both shells target `xc7a100tcsg324-1`. The SoC around the CPU (emacZero
MAC, MIG DDR3, axi_dma, axi_intc, axi_gpio × 6, uartlite, mtimer,
bram_ctrl, fcapz JTAG-AXI bridge, axi_interconnect × 3, smartconnect × 2)
is essentially identical between shells — the CPU is the sole macro-scale
difference, so the deltas below reflect CPU cost.

| Resource | MBV | Vex | Δ (vex − mbv) |
|---|---|---|---|
| Slice LUTs | 34,574 (54.53%) | 29,002 (45.74%) | **−5,572 (−16.1%)** |
| &nbsp;&nbsp;LUT as Logic | 28,991 (45.73%) | 23,271 (36.71%) | −5,720 (−19.7%) |
| &nbsp;&nbsp;LUT as Memory | 5,583 (29.38%) | 5,731 (30.16%) | +148 (+2.7%) |
| Slice Registers (FFs) | 45,885 (36.19%) | 29,534 (23.29%) | **−16,351 (−35.6%)** |
| F7 Muxes | 2,698 (8.51%) | 509 (1.61%) | −2,189 (−81.1%) |
| F8 Muxes | 1,339 (8.45%) | 227 (1.43%) | −1,112 (−83.0%) |
| BRAM Tile | 43 (31.85%) | 40.5 (30.00%) | **−2.5 tiles (−5.8%)** |
| &nbsp;&nbsp;RAMB36E1 | 41 | 37 | −4 |
| &nbsp;&nbsp;RAMB18E1 | 4 | 7 | +3 |
| DSPs | 4 (1.67%) | 4 (1.67%) | 0 |
| BUFGCTRL | 10 (31.25%) | 8 (25.00%) | −2 |
| MMCME2_ADV | 2 | 2 | 0 |
| PLLE2_ADV | 1 | 1 | 0 |

**Vex is the cheaper CPU on this Artix-7 target.** Despite carrying a
32 KiB I$, a 16 KiB D$ and a DYNAMIC_TARGET branch predictor, it uses ~16%
fewer LUTs, ~36% fewer FFs, ~6% fewer BRAM tiles, and dramatically fewer
F7/F8 wide-mux resources than MicroBlaze V, at the same clock (see Timing
below).
The BRAM saving is possible because vex's cache tag/data arrays pack
into RAMB36E1 primitives more efficiently than MicroBlaze V's LMB BRAM
controllers, which allocate per-word.

## Timing

Both bitstreams meet all user-specified timing constraints with the same
clocking: the CPU and SoC fabric on a 100 MHz `sys_clk` from the MMCM, and
MIG's `ui_clk` as a private downstream domain, crossed inside the DDR
SmartConnect.

| | MBV | Vex |
|---|---|---|
| CPU + SoC fabric clock | `sys_clk` **100 MHz** | `sys_clk` **100 MHz** |
| DDR UI clock | 81.25 MHz, isolated behind ddr_smartconnect CDC | same |
| Setup WNS | +0.054 ns | +0.062 ns |
| Hold WHS | +0.013 ns | +0.012 ns |
| Failing endpoints | 0 | 0 |
| Total endpoints | 123,991 | 114,797 |

With the shared MIG config (`hardware/mig/arty_a7_100t_mig.prj`, PHY ratio
4:1 at 325 MHz DDR) `ui_clk` is 81.25 MHz. Until Oct 16, 2026 the MBV shell
ran its CPU and fabric directly on `ui_clk`; it now matches the Vex shell,
so the two compare at the same clock. Both setup margins are thin and move
with placement from build to build: Vex variants with the same
DYNAMIC_TARGET earlyBranch pipeline closed between +0.022 and +0.369 ns.
Vex's worst path runs from the execute stage into the I-cache RAM address
(the earlyBranch redirect). Both build scripts refuse to write a bitstream
with a negative routed WNS or WHS.

## Reproducing these numbers

Hardware:
- `python hardware/scripts/build_arty_a7_mbv.py --synth --jobs 2`
- `python hardware/scripts/build_arty_a7_vex.py --synth --jobs 2`

Program + boot (`<shell>` is `mbv` or `vex`; `<N>` is 3 for mbv, 4 for vex):
- `python scripts/program_fpga.py --shell <shell>`
- `python scripts/load_zephyr_bram.py --shell <shell>`

Provision IP (both, once booted):
- `python scripts/emacz_config.py --bind <host-ip> configure --ip 192.168.237.200 --prefix 24`

Bench (`python scripts/run_perf_matrix.py` runs the whole set; the tables
above use `--rx-duration 20 --tx-duration 20`, three times):
- RX: `python scripts/run_udp_accounting.py --chain <N> --target 192.168.237.200 --bind <host-ip> --rate-mbps <rate> --duration 20`
- TX: `python scripts/run_tx_accounting.py --chain <N> --board 192.168.237.200 --bind <host-ip> --rate-mbps 0 --duration 20 --packet-size 1472`

## When to pick which

**Prefer MicroBlaze V for:**
- Full-duplex RX, where it stays 8% ahead of Vex
- Vivado-native flows that avoid the SpinalHDL/sbt build dependency
- Designs that want AMD's supported toolchain end-to-end
- LMB-BRAM boot (no external loader step)

**Prefer VexRiscv-full for:**
- RX throughput: 12% more than MBV at the same clock, TX level, and ahead
  on TX under RX load
- FPGA-area constrained designs (16% LUT / 36% FF savings)
- Bring-ups where JTAG-AXI DDR loading is available (vex boots from DDR
  via fcapz loader — no bootrom needed)
- Rebuild pipelines that already invoke sbt (`gen_vexriscv.py`)

Vex's D-cache is still write-through. A core with a write-back L1, such
as VexRiscv's successor VexiiRiscv, is untried here.
