# MicroBlaze V vs VexRiscv-full — Arty A7-100T SoC comparison

Two CPU options for the emacZero + Zephyr SoC on the Arty A7-100T shell.
All numbers below are measured on the same host, same PHY (Intel I226-V on
Ethernet 2 @ 100 Mbps), and the same emacZero MAC and Zephyr firmware.
What differs is only the CPU macro and the AXI plumbing around it.

Bitstream provenance:
- **mbv**: `build/vivado/arty_a7_100t_mbv/arty_a7_100t_mbv_wrapper.bit`
  (Aug 2, 2026 — MicroBlaze V, LMB BRAM + DDR)
- **vex**: `build/vivado/arty_a7_100t_vex/arty_a7_100t_vex_wrapper.bit`
  built by commit 088ac8f (Aug 30, 2026 — VexRiscv-full, 16 KiB I$/D$,
  DYNAMIC_TARGET branch predictor, earlyBranch, R-slice on DBUS)

## Throughput (delivered rate)

UDP with 1472 B payloads through Zephyr sockets on the mainline emacZero
driver. RX is the board's sink count over a 10 s window
(`scripts/run_udp_accounting.py`); TX is the board's `zsock_sendto` loop,
unthrottled, counted by the MAC and checked against the host
(`scripts/run_tx_accounting.py --rate-mbps 0`).

| Test | MBV | Vex |
|---|---|---|
| RX at 5 Mbit/s offered | 100% delivered, 0 errors | 100% delivered, 0 errors |
| RX ceiling | 8.5 Mbit/s, ~720 frames/s | 8.5 Mbit/s, ~720 frames/s |
| TX single-direction | 9.5 Mbit/s, 0 errors | 11.7 Mbit/s, 0 errors |

The RX ceiling is the same on both CPUs despite Vex's 23% faster clock,
because memory latency sets it. Frame buffers live in uncached DDR and the
UDP payload starts 2 bytes off a word boundary, so the socket's `memcpy`
of each payload reads uncached memory a byte at a time: measured at
~87k cycles on MBV and ~107k on Vex for 1472 bytes, ~1.07 ms on both, out
of ~1.39 ms per frame. With source and destination at the same alignment
the copy drops to ~22k/27k cycles, and from cached memory to ~3.5k/2.2k.
TX copies into uncached buffers too and gains a little from Vex's faster
core.

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
| Slice LUTs | 34,688 (54.71%) | 28,907 (45.59%) | **−5,781 (−16.7%)** |
| &nbsp;&nbsp;LUT as Logic | 29,103 (45.90%) | 23,156 (36.52%) | −5,947 (−20.4%) |
| &nbsp;&nbsp;LUT as Memory | 5,585 (29.39%) | 5,751 (30.27%) | +166 (+3.0%) |
| Slice Registers (FFs) | 46,199 (36.43%) | 29,451 (23.23%) | **−16,748 (−36.3%)** |
| F7 Muxes | 2,699 (8.51%) | 509 (1.61%) | −2,190 (−81.1%) |
| F8 Muxes | 1,339 (8.45%) | 227 (1.43%) | −1,112 (−83.0%) |
| BRAM Tile | 44 (32.59%) | 36 (26.67%) | **−8 tiles (−18.2%)** |
| &nbsp;&nbsp;RAMB36E1 | 41 | 32 | −9 |
| &nbsp;&nbsp;RAMB18E1 | 6 | 8 | +2 |
| DSPs | 4 (1.67%) | 4 (1.67%) | 0 |
| BUFGCTRL | 10 (31.25%) | 8 (25.00%) | −2 |
| MMCME2_ADV | 2 | 2 | 0 |
| PLLE2_ADV | 1 | 1 | 0 |

**Vex is the cheaper CPU on this Artix-7 target.** Despite carrying
16 KiB I$/D$ and a DYNAMIC_TARGET branch predictor, it uses ~17% fewer
LUTs, ~36% fewer FFs, ~18% fewer BRAM tiles, and dramatically fewer
F7/F8 wide-mux resources than MicroBlaze V — while also running its SoC
20% faster (see Timing below).
The BRAM saving is possible because vex's cache tag/data arrays pack
into RAMB36E1 primitives more efficiently than MicroBlaze V's LMB BRAM
controllers, which allocate per-word.

## Timing

Both bitstreams meet all user-specified timing constraints, but **they do
not run the CPU at the same frequency** — this matters when reading the
resource table above.

| | MBV | Vex |
|---|---|---|
| CPU + SoC fabric clock | `mig_ddr/ui_clk` **81.25 MHz** | `sys_clk` **100 MHz** |
| DDR UI clock | same 81.25 MHz domain (no CDC) | 81.25 MHz, isolated behind ddr_smartconnect CDC |
| Setup WNS | +0.630 ns | +0.187 ns |
| Hold WHS | +0.056 ns | +0.012 ns |
| Failing endpoints | 0 | 0 |
| Total endpoints | ~similar | 114,852 |

The MBV shell clocks the CPU and every AXI/AXI-Lite fabric directly from
MIG's `ui_clk`. With the shared MIG config (`hardware/mig/arty_a7_100t_mig.prj`,
PHY ratio 4:1 at 325 MHz DDR) that is 81.25 MHz. The Vex shell instead runs
a 100 MHz `sys_clk` from the MMCM and treats `ui_clk` as a private
downstream domain, crossing into it inside the DDR SmartConnect.

So Vex delivers the smaller footprint *and* a 23% higher core clock. Its
thinner setup margin is expected: widened caches + predictor + R-slice at
a shorter target period push routing harder on the CPU core.

## Reproducing these numbers

Hardware:
- `python hardware/scripts/build_arty_a7_mbv.py --synth --jobs 2`
- `python hardware/scripts/build_arty_a7_vex.py --synth --jobs 2`

Program + boot (`<shell>` is `mbv` or `vex`; `<N>` is 3 for mbv, 4 for vex):
- `python scripts/program_fpga.py --shell <shell>`
- `python scripts/load_zephyr_bram.py --shell <shell>`

Provision IP (both, once booted):
- `python scripts/emacz_config.py --bind <host-ip> configure --ip 192.168.237.200 --prefix 24`

Bench:
- RX: `python scripts/run_udp_accounting.py --chain <N> --target 192.168.237.200 --bind <host-ip> --rate-mbps <rate> --duration 10`
- TX: `python scripts/run_tx_accounting.py --chain <N> --board 192.168.237.200 --bind <host-ip> --rate-mbps 0 --duration 5 --packet-size 1472`

## When to pick which

**Prefer VexRiscv-full for:**
- FPGA-area constrained designs (16.7% LUT / 36% FF savings)
- Bring-ups where JTAG-AXI DDR loading is available (vex boots from DDR
  via fcapz loader — no bootrom needed)
- Rebuild pipelines that already invoke sbt (`gen_vexriscv.py`)

**Prefer MicroBlaze V for:**
- Vivado-native flows that avoid the SpinalHDL/sbt build dependency
- Designs that want AMD's supported toolchain end-to-end
- LMB-BRAM boot (no external loader step)

**Neither, if the goal is RX throughput** — uncached-memory copies hold
both to the same ~720 frames/s. Vex's faster core buys about 20% on TX.
