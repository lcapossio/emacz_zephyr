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
  (Oct 11, 2026 — VexRiscv-full, 16 KiB I$/D$, DYNAMIC_TARGET branch
  predictor, earlyBranch, R-slice on DBUS)

## Throughput (delivered rate)

UDP with 1472 B payloads through Zephyr sockets on the mainline emacZero
driver, measured with `scripts/run_perf_matrix.py` (caches on, uncached
frame buffers). RX is the board's sink count with 90 Mbit/s offered for
5 s (`scripts/run_udp_accounting.py`); TX is the board's `zsock_sendto`
loop, unthrottled for 5 s, counted by the MAC and checked against the host
(`scripts/run_tx_accounting.py --rate-mbps 0`). *Word copies* is
`app/perf/payload_align2.conf`, which aligns the app's socket buffers with
the payload so the socket copies run on words.

| Test | MBV | Vex |
|---|---|---|
| RX ceiling | 9.3 Mbit/s, ~790 frames/s | 9.4 Mbit/s, ~800 frames/s |
| TX single-direction | 8.9 Mbit/s | 11.5 Mbit/s |
| RX ceiling, word copies | 19.9 Mbit/s | 19.7 Mbit/s |
| TX, word copies | 15.6 Mbit/s | 15.9 Mbit/s |

At the same clock the RX ceiling is the same on both CPUs, because memory
latency sets it. Frame buffers live in uncached DDR and the UDP payload
starts 2 bytes off a word boundary, so the socket's `memcpy` of each
payload reads uncached memory a byte at a time: ~1.07 ms for 1472 bytes on
both CPUs, out of ~1.25 ms per frame (probe on the earlier builds: ~87k
cycles on MBV at 81.25 MHz, ~107k on Vex at 100 MHz). With source and
destination at the same alignment the copy drops to ~22k/27k cycles, and
from cached memory to ~3.5k/2.2k. TX copies into uncached buffers too, a
byte at a time unless aligned; Vex runs that byte-store loop ~30% faster,
and with word copies the two CPUs are level again.

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
| Slice LUTs | 34,574 (54.53%) | 28,944 (45.65%) | **−5,630 (−16.3%)** |
| &nbsp;&nbsp;LUT as Logic | 28,991 (45.73%) | 23,193 (36.58%) | −5,798 (−20.0%) |
| &nbsp;&nbsp;LUT as Memory | 5,583 (29.38%) | 5,751 (30.27%) | +168 (+3.0%) |
| Slice Registers (FFs) | 45,885 (36.19%) | 29,419 (23.20%) | **−16,466 (−35.9%)** |
| F7 Muxes | 2,698 (8.51%) | 507 (1.60%) | −2,191 (−81.2%) |
| F8 Muxes | 1,339 (8.45%) | 227 (1.43%) | −1,112 (−83.0%) |
| BRAM Tile | 43 (31.85%) | 36 (26.67%) | **−7 tiles (−16.3%)** |
| &nbsp;&nbsp;RAMB36E1 | 41 | 32 | −9 |
| &nbsp;&nbsp;RAMB18E1 | 4 | 8 | +4 |
| DSPs | 4 (1.67%) | 4 (1.67%) | 0 |
| BUFGCTRL | 10 (31.25%) | 8 (25.00%) | −2 |
| MMCME2_ADV | 2 | 2 | 0 |
| PLLE2_ADV | 1 | 1 | 0 |

**Vex is the cheaper CPU on this Artix-7 target.** Despite carrying
16 KiB I$/D$ and a DYNAMIC_TARGET branch predictor, it uses ~16% fewer
LUTs, ~36% fewer FFs, ~16% fewer BRAM tiles, and dramatically fewer
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
| Setup WNS | +0.054 ns | +0.023 ns |
| Hold WHS | +0.013 ns | +0.050 ns |
| Failing endpoints | 0 | 0 |
| Total endpoints | 123,991 | 114,729 |

With the shared MIG config (`hardware/mig/arty_a7_100t_mig.prj`, PHY ratio
4:1 at 325 MHz DDR) `ui_clk` is 81.25 MHz. Until Oct 16, 2026 the MBV shell
ran its CPU and fabric directly on `ui_clk`; it now matches the Vex shell,
so the two compare at the same clock. Both setup margins are thin and move
with placement from build to build; both build scripts refuse to write a
bitstream with a negative routed WNS or WHS.

## Reproducing these numbers

Hardware:
- `python hardware/scripts/build_arty_a7_mbv.py --synth --jobs 2`
- `python hardware/scripts/build_arty_a7_vex.py --synth --jobs 2`

Program + boot (`<shell>` is `mbv` or `vex`; `<N>` is 3 for mbv, 4 for vex):
- `python scripts/program_fpga.py --shell <shell>`
- `python scripts/load_zephyr_bram.py --shell <shell>`

Provision IP (both, once booted):
- `python scripts/emacz_config.py --bind <host-ip> configure --ip 192.168.237.200 --prefix 24`

Bench (`python scripts/run_perf_matrix.py` runs the whole set):
- RX: `python scripts/run_udp_accounting.py --chain <N> --target 192.168.237.200 --bind <host-ip> --rate-mbps <rate> --duration 10`
- TX: `python scripts/run_tx_accounting.py --chain <N> --board 192.168.237.200 --bind <host-ip> --rate-mbps 0 --duration 5 --packet-size 1472`

## When to pick which

**Prefer VexRiscv-full for:**
- FPGA-area constrained designs (16% LUT / 36% FF savings)
- Bring-ups where JTAG-AXI DDR loading is available (vex boots from DDR
  via fcapz loader — no bootrom needed)
- Rebuild pipelines that already invoke sbt (`gen_vexriscv.py`)

**Prefer MicroBlaze V for:**
- Vivado-native flows that avoid the SpinalHDL/sbt build dependency
- Designs that want AMD's supported toolchain end-to-end
- LMB-BRAM boot (no external loader step)

**Neither, if the goal is RX throughput** — uncached-memory copies hold
both to the same ~800 frames/s at 100 MHz. Vex is ~30% faster on TX only
while the copies run byte by byte.
