# MicroBlaze V vs VexRiscv-full — Arty A7-100T SoC comparison

Two CPU options for the emacZero + Zephyr SoC on the Arty A7-100T shell.
All numbers below are measured on the same host, same PHY (Intel I226-V on
Ethernet 2 @ 100 Mbps), and the same emacZero MAC + Zephyr fast-path
firmware. What differs is only the CPU macro and the AXI plumbing around
it.

Bitstream provenance:
- **mbv**: `build/vivado/arty_a7_100t_mbv/arty_a7_100t_mbv_wrapper.bit`
  (Aug 2, 2026 — MicroBlaze V, LMB BRAM + DDR)
- **vex**: `build/vivado/arty_a7_100t_vex/arty_a7_100t_vex_wrapper.bit`
  built by commit 088ac8f (Aug 30, 2026 — VexRiscv-full, 16 KiB I$/D$,
  DYNAMIC_TARGET branch predictor, earlyBranch, R-slice on DBUS)

## Throughput — apples-to-apples (delivered rate)

Sender: `iperf.exe -c 192.168.237.200 -B 192.168.237.1 -u -b <rate>M -t 5 -l 1472 -p 5001`.
RX "delivered" is the delta in `sink_packets` from Zephyr's `emaczero_perf_stats`
across the bench window — NOT iperf's offered rate. TX is
`no_commit/run_tx_accounting.py --rate-mbps 0 --duration 5 --packet-size 1472`
(unthrottled). Concurrent runs iperf + tx bench simultaneously.

| Test | MBV | Vex (fixed, 088ac8f) |
|---|---|---|
| RX single-direction | **96.0 Mbps** delivered, 0 drops anywhere | **94.5 Mbps** delivered, 0 drops anywhere |
| TX single-direction | **91.4 Mbps**, 99.88% host-received, 0 errors | **92.3 Mbps**, 99.87% host-received, 0 errors |
| RX+TX concurrent | RX 95.8 + TX 91.4 = **187.2 Mbps** aggregate | RX 94.7 + TX 91.4 = **186.1 Mbps** aggregate |
| % of 200 Mbps full-duplex | **93.6%** | **93.1%** |

Both CPUs saturate the 100 Mbps MII in both directions with zero drops at
`mac_rx_err`, `gate_dropped_bad_frames`, `gate_dropped_overflow_frames`,
or `tx_dma_error`. On this SoC composition the two CPUs are
indistinguishable at the network layer — the workload is
network-bound, not CPU-bound.

Historical bench numbers that suggested vex or mbv had a large edge over
the other were measurement artifacts: either the Python
`send_fast_sink` sender was host-side capped near 66 Mbps (making both
look slow), or the reported number was iperf's OFFERED rate rather than
the board-delivered rate. Once both are read from
`sink_packets` deltas with an iperf sender, they converge at ~94-96 Mbps
RX / ~91-92 Mbps TX / ~186-187 Mbps aggregate.

## FPGA resource utilization

Both shells target `xc7a100tcsg324-1`. The SoC around the CPU (emacZero
MAC, MIG DDR3, axi_dma, axi_intc, axi_gpio × 6, uartlite, mtimer,
bram_ctrl, fcapz JTAG-AXI bridge, axi_interconnect × 3, smartconnect × 2)
is essentially identical between shells — the CPU is the sole macro-scale
difference, so the deltas below reflect CPU cost.

| Resource | MBV | Vex | Δ (vex − mbv) |
|---|---|---|---|
| Slice LUTs | 34,688 (54.71%) | 28,909 (45.60%) | **−5,779 (−16.7%)** |
| &nbsp;&nbsp;LUT as Logic | 29,103 (45.90%) | 23,158 (36.53%) | −5,945 (−20.4%) |
| &nbsp;&nbsp;LUT as Memory | 5,585 (29.39%) | 5,751 (30.27%) | +166 (+3.0%) |
| Slice Registers (FFs) | 46,199 (36.43%) | 29,460 (23.23%) | **−16,739 (−36.2%)** |
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
F7/F8 wide-mux resources than MicroBlaze V, all at the same 100 MHz sys_clk.
The BRAM saving is possible because vex's cache tag/data arrays pack
into RAMB36E1 primitives more efficiently than MicroBlaze V's LMB BRAM
controllers, which allocate per-word.

## Timing

Both bitstreams meet all user-specified timing constraints at 100 MHz
sys_clk.

| | MBV | Vex |
|---|---|---|
| Setup WNS (sys_clk) | +0.630 ns | +0.369 ns |
| Hold WHS (sys_clk) | +0.056 ns | +0.019 ns |
| Failing endpoints | 0 | 0 |
| Total endpoints | ~similar | 114,839 |

MBV has slightly more setup headroom; vex is tighter but still MET. The
vex margin is thinner because widened caches + predictor + R-slice push
routing harder on the CPU core.

## Reproducing these numbers

Hardware:
- `python hardware/scripts/build_arty_a7_mbv.py --synth --jobs 2`
- `python hardware/scripts/build_arty_a7_vex.py --synth --jobs 2`

Program + boot:
- **MBV**: `vivado -mode batch -source no_commit/program_current_mbv_simple.tcl`,
  then `python no_commit/load_zephyr_bram.py --file build-mbv-emac/zephyr/zephyr.bin --addr 0x90000000 --chain 3`
- **Vex**: `vivado -mode batch -source no_commit/program_current_vex_simple.tcl`,
  then `python no_commit/vex_boot_zephyr.py --file build-vex-emac/zephyr/zephyr.bin`

Provision IP (both, once booted):
- `python no_commit/vex_set_ip.py 192.168.237.200 --prefix 24 --chain <3-for-mbv|4-for-vex>`

Bench:
- RX: `no_commit/tools/iperf2/iperf.exe -c 192.168.237.200 -B <host-ip> -u -b 95M -t 5 -l 1472 -p 5001`,
  then diff `sink_packets` from `python no_commit/read_perf_stats.py --chain <N> --all`
- TX: `python no_commit/run_tx_accounting.py --board 192.168.237.200 --bind <host-ip> --chain <N> --rate-mbps 0 --duration 5 --packet-size 1472 --skip-profile-check`

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

**Neither, if the goal is throughput** — the two are indistinguishable
on this SoC at 100 Mbps line rate. Any perceived difference is a
measurement bias; verify both with `sink_packets` deltas before drawing
a conclusion.
