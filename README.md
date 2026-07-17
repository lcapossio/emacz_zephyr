# emacz_zephyr

emacz_zephyr integrates [emacZero](https://github.com/lcapossio/emacZero) with
the Xilinx/AMD Zephyr tree for an Arty A7-100T MicroBlaze V example design.

## Index

- [Features](#features)
- [Repository Layout](#repository-layout)
- [Setup](#setup)
- [Build](#build)
- [Host-configured IPv4](#host-configured-ipv4)
- [Arty A7-100T MicroBlaze V System](#arty-a7-100t-microblaze-v-system)
- [Hardware Integration Notes](#hardware-integration-notes)
- [Resource Usage and Frequency](#resource-usage-and-frequency)
- [Verification](#verification)
- [Author and License](#author-and-license)

## Features

- Uses `external/emacZero` as a git submodule.
- Uses `fcapz` as a git submodule for internal FPGA debug.
- Pins Zephyr to AMD/Xilinx `zephyr-amd` branch `xlnx_rel_v2026.1`.
- Provides an out-of-tree Zephyr Ethernet driver and devicetree binding for
  `bard0,emaczero`.
- Includes an Arty A7-100T MicroBlaze V example overlay for AMD Zephyr `mbv32`.
- Runs a host-configured Zephyr networking app with a high-rate UDP endpoint
  on port 5001 for receive-path testing; no deployment subnet is compiled into
  the board firmware.
- Keeps vendor-specific FPGA integration details behind the devicetree binding
  and hardware shell notes so future CPU/FPGA wrappers can be added cleanly.

## Repository Layout

- `external/emacZero/`: emacZero RTL, docs, and bare-metal software submodule.
- `fcapz/`: fpgacapZero debug cores and host tools submodule.
- `drivers/ethernet/`: native Zephyr emacZero Ethernet driver.
- `dts/bindings/ethernet/`: Zephyr devicetree binding.
- `app/`: minimal Zephyr bring-up application for the Arty A7 example.
- `hardware/rtl/clk_gen.v`: parent-project Arty 25 MHz clock generator variant
  for integrations that derive Ethernet reference clocking from the DDR MIG
  `ui_clk` instead of emacZero's standalone Arty clock source.
- `scripts/check_env.py`: portable Python environment check.
- `no_commit/BUGS.md`: local bug list required by the project rules.

## Setup

Install the Zephyr host dependencies and an AMD/Xilinx-compatible cross
compiler for the soft CPU instantiated in the FPGA design.

```sh
python scripts/check_env.py
west init -l .
west update
python scripts/apply_zephyr_patches.py
west zephyr-export
```

The patch step asks west for the absolute Zephyr project path, so it works
whether the manifest repository is the workspace root or a child checkout.
It falls back to `ZEPHYR_BASE` and conventional sibling/in-tree workspace
layouts. The tracked patches are required by the direct AXI DMA RX-ring path
used by the default app configuration. Re-run the same command after
`west update` if the Zephyr checkout is refreshed.

An explicit checkout can also be supplied without relying on workspace layout:

```sh
python scripts/apply_zephyr_patches.py --zephyr-dir /path/to/zephyr
```

Tools are searched in `PATH`. The current example targets MicroBlaze V through
AMD Zephyr's `mbv32` board, so a RISC-V cross compiler such as
`riscv64-unknown-elf-gcc` or the Zephyr SDK RISC-V toolchain must be available.

On Windows hosts, WSL is the recommended short build loop if the Windows Zephyr
SDK is incomplete:

```sh
python3 -m pip install --user --break-system-packages west pykwalify
export PATH="$HOME/.local/bin:$PATH"
export ZEPHYR_TOOLCHAIN_VARIANT=cross-compile
export CROSS_COMPILE=/usr/bin/riscv64-unknown-elf-
```

Use a Python virtual environment instead of `--break-system-packages` when
`python3-venv` is installed in WSL.

## Build

The example target is AMD Zephyr's MicroBlaze V board. The committed app is an
emacZero bring-up that enables Zephyr networking and the `bard0,emaczero`
driver while keeping Zephyr's UART console disabled. It prints raw UARTLite
breadcrumbs and emacZero CSR/RX counters on the normal Arty USB UART, and keeps
an AXI BRAM scratch heartbeat:

```sh
west build -b mbv32 app -- \
  -DZEPHYR_TOOLCHAIN_VARIANT=cross-compile \
  -DCROSS_COMPILE=/usr/bin/riscv64-unknown-elf-
```

The app registers this repository as a Zephyr extra module, so the local
driver, Kconfig, and devicetree binding are picked up automatically.

Use `--pristine` after devicetree or Kconfig changes:

```sh
west build --pristine -b mbv32 app -- \
  -DZEPHYR_TOOLCHAIN_VARIANT=cross-compile \
  -DCROSS_COMPILE=/usr/bin/riscv64-unknown-elf-
```

Build the Arty A7-100T MicroBlaze V hardware shell with Vivado:

```sh
python hardware/scripts/build_arty_a7_mbv.py
python hardware/scripts/build_arty_a7_mbv.py --synth --jobs 2
```

The first command generates and validates the block design. The second command
runs synthesis, implementation, bitstream generation, and writes an XSA. The
Zephyr bring-up flow avoids repeated bitstream rebuilds by loading the flat
`zephyr.bin` into DDR over fcapz USER3, then releasing MBV through the USER1
EIO reset bit.

```sh
python scripts/load_zephyr_bram.py \
  --file build-wsl-zephyr-ddr/zephyr/zephyr.bin \
  --addr 0x90000000 --chunk-words 16 --verify-words 16 --monitor 2
```

For first hardware bring-up, build the smaller bare-metal UART smoke ELF and
embed that instead of Zephyr:

```sh
python sw/baremetal/build_mbv_ejtaguart_smoke.py
python hardware/scripts/build_arty_a7_mbv.py --synth --jobs 2 \
  --elf build/baremetal/mbv_ejtaguart_smoke.elf
python hardware/scripts/monitor_fcapz_uart.py --program \
  build/vivado/arty_a7_100t_mbv/arty_a7_100t_mbv.runs/impl_1/arty_a7_100t_mbv_wrapper.bit
python scripts/load_zephyr_bram.py --file build/baremetal/mbv_ejtaguart_smoke.bin \
  --monitor 15 --send Q
```

The monitor filters the Xilinx hw_server target with `xc7a100t` and talks to
the fcapz EJTAG-UART core on BSCANE2 USER4. The BRAM loader keeps MBV reset
asserted through USER1 EIO while USER3 AXI writes and verifies BRAM, then
releases reset and clears the USER4 startup framing flag before monitoring.

## Arty A7-100T MicroBlaze V System

Use AMD's MicroBlaze V IP as the Zephyr CPU in the Arty A7-100T FPGA design.
The Zephyr board target is still named `mbv32`; this repository supplies the
Arty-specific application overlay that adds emacZero at `0x44a00000` on the AXI
bus, connects its interrupt to AXI INTC input 5, and connects its byte-wide
packet streams to Xilinx AXI DMA at `0x41e00000`.

Implemented FPGA shell blocks:

- MicroBlaze V 32-bit processor, RV32IMAC with Zicsr/Zifencei.
- AXI INTC at `0x41200000`.
- AXI Timer at `0x41c00000`.
- AXI UARTLite at `0x40600000`.
- 256 MiB DDR3 at `0x90000000` through the Arty A7 MIG, with MBV I/D caches
  enabled over the DDR window.
- Zephyr code/data/stack/heap in the lower 240 MiB of DDR.
- emacZero DMA descriptors and packet buffers in the upper 16 MiB of DDR at
  `0x9f000000`.
- 32 KiB LMB BRAM at CPU address `0x80000000`, with a reset-time debug-loader
  AXI alias at `0x80008000`.
- 32 KiB AXI BRAM at `0x80040000` retained as scratch/debug memory.
- fcapz EJTAG-AXI on BSCANE2 USER3 reaches both memory windows: the shared DMA
  BRAM directly, and the MBV LMB BRAM through the reset-time `0x80008000`
  AXI loader alias plus native BRAM-port mux. USER1 EIO selects the loader
  port only while MBV is held in reset.
- emacZero AXI-Lite CSR aperture at `0x44a00000`.
- Xilinx AXI DMA at `0x41e00000`, with MM2S/S2MM packet streams wired to
  emacZero and scatter-gather descriptors/buffers in DDR.
- fcapz EJTAG-UART on BSCANE2 USER4, bridged to AXI UARTLite for MBV console
  traffic.
- fcapz ELA on BSCANE2 USER1, probing reset, UART, interrupt, PHY reset, and a
  heartbeat counter for early hardware debug.

The older BRAM-only memory map was kept only as loader/debug scratch; runtime
software and packet buffers are now in DDR.

## Host-configured IPv4

The board does not have a fixed operational IPv4 address. On every boot it
uses a MAC-derived RFC 3927 bootstrap address only for provisioning. The host
tool discovers it across all active IPv4 adapters and assigns the address,
prefix, and optional gateway requested by the user:

```sh
python -m pip install psutil
python scripts/emacz_config.py discover
python scripts/emacz_config.py configure --ip 192.168.237.200 --prefix 24
python scripts/emacz_config.py configure --ip 10.20.30.40 --prefix 24 \
  --gateway 10.20.30.1
```

Use `--interface NAME` or `--bind HOST_IP` before the subcommand to restrict
discovery when desired. Boards sharing one Ethernet segment must have distinct
MAC addresses; select a discovered board with `--mac`. For example:

```sh
python scripts/emacz_config.py --interface "Ethernet 2" configure \
  --mac 02:00:00:00:00:01 --ip 192.168.237.200 --prefix 24
```

The tool uses ordinary portable UDP sockets: discovery/config requests are
IPv4 limited broadcasts on port 5004 and replies are sent to multicast group
`239.255.77.90` on the same port. This works without raw-socket, Npcap, or
administrator privileges. Messages include a CRC, transaction ID, target MAC,
and a short-lived offer token. The token prevents stale or accidental changes;
it is not authentication, so provisioning should remain on a trusted local
Ethernet segment. Configuration is intentionally runtime-only and must be
provided again after a board reboot.

The current committed Zephyr app enables emacZero device/interface
registration, reads the MAC CSRs directly, starts host-driven IPv4
provisioning, registers an application-owned high-rate UDP endpoint on port
5001, and brings up the AXI DMA-backed packet path. ARP, ICMP, and all other
traffic continue through the normal Zephyr network stack.
For profiling, the BRAM build currently provisions 64 emacZero RX DMA frame
buffers, 96 Zephyr RX packets, and 192 Zephyr RX net_buf fragments so the stack
can absorb longer zperf receive bursts before the driver runs out of buffers.
The app also sets a 12 KiB heap because AMD's Xilinx AXI DMA driver allocates
SG descriptor rings dynamically, and a 64-entry RX ring no longer fits in the
default 4 KiB heap.
The app also writes `0x5A455048` and an incrementing counter to the
linker-placed `emacz_scratch_heartbeat` variable from `main()` as a
UART-independent liveness proof. Use `nm` on the ELF to locate that symbol
instead of relying on a fixed scratch address that can collide with heap or DMA
descriptor placement.

The previous networking app required `CONFIG_TEST_RANDOM_GENERATOR=y` because
the current MBV32 Arty shell does not define a hardware entropy source and
Zephyr networking uses `sys_rand_get()` for DHCP/IPv6 timing. Restore that or a
real entropy driver when re-enabling DHCP/networking.

## Hardware Integration Notes

The Arty A7-100T is an FPGA board and does not include a hard CPU. Zephyr runs
only after the FPGA is programmed with the MicroBlaze V soft CPU design. The
Vivado generator in `hardware/scripts/build_arty_a7_mbv.py` creates the current
hardware shell and matches the `app/boards/mbv32.overlay` address map.

The debug console path is AXI UARTLite TX/RX through `fcapz_mbv_debug`, then
fcapz EJTAG-UART over USER4. This keeps early MBV bare-metal and Zephyr console
bring-up independent of the board USB UART while leaving the physical UART TX
pin connected for comparison.

The ELA probe sidecar for this debug wrapper is
`hardware/debug/mbv_fcapz.prob`.

emacZero exposes AXI-Lite CSRs plus AXI-Stream TX/RX packet ports. The FPGA
shell wires those packet streams to Xilinx AXI DMA: MM2S feeds emacZero TX,
S2MM receives emacZero RX, and the DMA SG/MM2S/S2MM masters reach the DMA AXI
BRAM through a full AXI4 data interconnect. MicroBlaze V and fcapz/debug use a
separate control interconnect for AXI-Lite peripherals and bridge into the DMA
fabric only when software/debug needs packet-buffer access.
The Zephyr driver initializes and controls the MAC, exposes Ethernet
statistics, validates the CSR version, and queues RX/TX buffers through the
Zephyr Xilinx AXI DMA driver when the `axistream-connected` devicetree property
is present. The RX path uses a worker thread fed by the DMA ISR, external
net_buf fragments for zero-copy packets into the Zephyr network stack, and a
copy fallback when the stack owns too many DMA buffers under overload. The test
configuration enables AXI DMA interrupt coalescing with threshold 4 and timeout
8.

The MBV shell enables emacZero `MII_DEBUG` in
`emaczero_axi_mii_wrapper`, keeping the MII RX/TX capture words, replay
counters, and pre-IOB TX debug pins live. The wrapper exposes those debug
registers in the emacZero AXI-Lite side windows used by
`scripts/read_perf_stats.py` and the four-point trace helpers.

The MicroBlaze V instance is configured at 100 MHz with RV32IMAC features
enabled through `C_USE_MULDIV=2`, atomics, compressed instructions,
interrupts, local I/D LMB, and separate AXI instruction/data ports.

Standalone Arty A7-100T top-level RTL diagram:

<a href="docs/architecture.svg">
  <img src="docs/architecture.svg" alt="emacZero Arty A7-100T top-level RTL">
</a>

The editable diagram source is [docs/architecture.json](docs/architecture.json).

## Resource Usage and Frequency

An integrated Arty A7-100T MicroBlaze V + emacZero + AXI DMA + fcapz debug
Vivado build completed with Vivado 2025.2 for `xc7a100tcsg324-1`. The routed
split-fabric design met timing at 100 MHz with `WNS = 0.022 ns`,
`TNS = 0.000 ns`, `WHS = 0.025 ns`, and `THS = 0.000 ns`.

Routed utilization:

- Slice LUTs: 28342 / 63400, 44.70%.
- Slice registers: 42725 / 126800, 33.69%.
- Block RAM tiles: 135 / 135, 100.00%.
- DSPs: 4 / 240, 1.67%.

## Verification

Short-loop checks:

```sh
python scripts/lint.py
python -m pytest tests/test_apply_zephyr_patches.py \
  tests/test_emacz_config.py tests/test_run_arty_stress.py -q \
  -p no:cacheprovider
python scripts/check_env.py
python hardware/sim/run.py
west build -b mbv32 app -- \
  -DZEPHYR_TOOLCHAIN_VARIANT=cross-compile \
  -DCROSS_COMPILE=/usr/bin/riscv64-unknown-elf-
```

`scripts/lint.py` resolves `ruff` and `clang-format` from `PATH` and fails
immediately if either tool is unavailable. CI runs the same lint and focused
host-tool tests. Local CMake/Ninja builds must use no more than half of the
host's logical CPUs; on a 16-thread host use `cmake --build BUILD_DIR
--parallel 8`.

A build-only test mirror lives at `tests/app_build/` so a separate `west build`
covers the same compile path as the app without polluting the in-tree build
directory:

```sh
west build -d build-app-build -b mbv32 tests/app_build -- \
  -DZEPHYR_TOOLCHAIN_VARIANT=cross-compile \
  -DCROSS_COMPILE=/usr/bin/riscv64-unknown-elf-
```

Verified on this host from WSL with GCC `riscv64-unknown-elf-gcc 13.2.0`:

```sh
export PATH="$HOME/.local/bin:$PATH"
west build -d build-wsl -b mbv32 app --pristine=always -- \
  -DZEPHYR_TOOLCHAIN_VARIANT=cross-compile \
  -DCROSS_COMPILE=/usr/bin/riscv64-unknown-elf-
```

The build produced `build-wsl/zephyr/zephyr.elf`. Link-time RAM use reported by
Zephyr was 123232 bytes out of the MBV32 board model's 2 GiB DDR region.

Vivado hardware build verified on this host:

```sh
python hardware/scripts/build_arty_a7_mbv.py --synth --jobs 2 \
  --elf build/baremetal/mbv_ejtaguart_smoke.elf
```

The build produced:

- `build/vivado/arty_a7_100t_mbv/arty_a7_100t_mbv.runs/impl_1/arty_a7_100t_mbv_wrapper.bit`
- `build/vivado/arty_a7_100t_mbv/arty_a7_100t_mbv.xsa`

The board was programmed over the connected Digilent JTAG cable after filtering
Vivado hardware devices by `xc7a100t`. The bare-metal smoke ELF booted from
BRAM and printed its banner and heartbeat on COM4:
`mbv fcapz ejtaguart smoke`, `uartlite=0x40600000`, and `beat ...`.
fcapz EJTAG-UART on USER4 enumerated as version `0x00044A55`; after resetting
the bridge on connect, USER4 transmit into UARTLite RX echoed through MBV as
`rx Q`. fcapz EJTAG-AXI on USER3 also accessed the AXI fabric: reading
UARTLite status at `0x40600008` returned `0x00000004`, and writing `0x41` to
UARTLite TX at `0x40600004` produced `A` on COM4. XSDB still sees the FPGA plus
`BSCAN JTAG at USER2` but not a MicroBlaze V CPU target behind MDM, and Zephyr
runtime plus the Ethernet packet path remain pending.

Zephyr emacZero bring-up was also verified on the board by loading the flat
binary into BRAM over fcapz USER3, releasing MBV reset through USER1 EIO, and
capturing the normal Arty USB UART on COM4:

```sh
west build -d build-wsl-zephyr-eth -b mbv32 app -- \
  -DZEPHYR_TOOLCHAIN_VARIANT=cross-compile \
  -DCROSS_COMPILE=/usr/bin/riscv64-unknown-elf-
python scripts/load_zephyr_bram.py \
  --file build-wsl-zephyr-eth/zephyr/zephyr.bin
riscv64-unknown-elf-nm build-wsl-zephyr-eth/zephyr/zephyr.elf | \
  grep emacz_scratch_heartbeat
python -m fcapz.cli --backend hw_server --tap xc7a100t.tap \
  axi-dump --chain 3 --addr <symbol-address> --count 2
```

After increasing the BRAM window, RX pools, and heap for profiling, the app
built to 359200 bytes of RAM usage out of 512 KiB with zperf enabled.
Hardware output on COM4 showed `MBV default iface ok`, emacZero VERSION
`0x0001454D`, CTRL `0x0000002B`, MAC `02:00:00:00:00:01`, IPv4
`192.168.137.200/24`, and RX frame/byte counters increasing with the Ethernet
cable connected. AXI reads over fcapz after Zephyr boot show both AXI DMA
channels configured with SG descriptor pointers in BRAM around `0x80017xxx`.
`net_if_up()` returns `0xFFFFFF88`, which is `-EALREADY` in this Zephyr libc
because the interface is already up by the time `main()` calls it.

Packet I/O was verified from Windows on host NIC `Ethernet 3` configured as
`192.168.137.1/24`:

```bat
ping -n 4 -w 1000 192.168.137.200
arp -a 192.168.137.200
```

The board replied to all four pings with 2-4 ms RTT, and ARP resolved
`192.168.137.200` to `02-00-00-00-00-01`. emacZero counters increased across
the test from TX `0x6`/RX `0xb` frames to TX `0xb`/RX `0x17` frames. USER4
JTAG-UART monitoring still reports overflow/framing errors for Zephyr UARTLite
writes, while the normal COM4 UART output is clean.

Older UDP receive testing used Windows host NIC `Ethernet 3` at
`192.168.137.1/24`, board IP `192.168.137.200`, zperf UDP server port 5001,
1064-byte UDP payloads, and the same already-routed bitstream with only
`zephyr.bin` reloaded into BRAM:

```bat
python scripts\zperf_udp_client.py 192.168.137.200 --bind 192.168.137.1 ^
  --port 5001 --rate-mbps 5 --duration 3 --packet-size 1064
```

With the zero-copy RX worker path, the paced sender reported 1762 packets sent
at 4.993 Mbit/s, and the Zephyr receiver reported 1761 packets, 0 lost, 1873704
bytes over 3.000 s, or 4.997 Mbit/s. A 4 Mbit/s run under the same conditions
also reported 0 lost packets. An overload run requested 8 Mbit/s but the Python
sender produced about 5.983 Mbit/s; zperf received 1256 packets, lost 1563, and
the board still answered ping afterward, showing the RX path no longer wedges
when overloaded.

Older MTU-sized UDP socket-sink testing exposed a roughly 10 Mbit/s ceiling.
Isolation runs showed that the MAC, RX gate, and direct AXI DMA S2MM ring were
clean at 95 Mbit/s when buffers were returned immediately, while constructing
and copying a Zephyr packet before returning each DMA buffer caused reserve
exhaustion, S2MM backpressure, and secondary BD/gate errors. Bounded zero-copy
alone did not fix it because the stack retained DMA buffers long enough to
consume the reserve.

The installed Windows iperf2 binary is `no_commit\tools\iperf2\iperf.exe`.
It reaches the board, but on this host it remains much burstier than the paced
Python sender; a 3 Mbit/s, 3 s, 1064-byte test reported only 520 Kbit/s in the
server report with heavy loss. Treat the paced zperf-compatible sender as the
current driver stress reference until the host iperf2 pacing/reporting mismatch
is understood.

Current DDR Ethernet firmware is built with `CONFIG_NET_ZPERF=n`. The reusable
MAC driver exposes a generic RX interceptor; the demo application uses it for
unicast UDP port 5001 and returns the DMA buffer immediately after endpoint
accounting. The same dispatcher queues port-5004 provisioning messages to an
application thread, so bootstrap does not depend on Zephyr accepting a packet
whose host and board initially occupy different subnets. Use the accounting
helper and treat `sink_packets_delta` / `sink_bytes_delta` plus zero error
deltas as the RX pass condition:

```bat
python scripts\run_udp_accounting.py --target 192.168.137.200 ^
  --bind 192.168.137.1 --rate-mbps 40 --duration 4 --packet-size 1472
```

The helper first checks the profile-control socket on UDP port 5002. If that
preflight times out, fix the host test context before blaming the board; on the
current Windows setup the same socket helpers may need the elevated context that
can access the board NIC.

For an automated, OS-independent acceptance run, use `run_arty_stress.py`.
It uses only Python's standard UDP sockets plus `psutil`: no JTAG, fcapz,
Npcap, raw socket, `ping` executable, or OS-specific command-line parsing is
required. It discovers and configures the board, selects the host address in
the requested subnet, takes portable before/after counter snapshots over UDP
port 5002, sends the load, requires the configured delivery percentage and
zero hardware/driver error deltas, and rediscovers the board afterward.

The default duration is 600 seconds, rate is 95 Mbit/s, payload is 1472 bytes,
and required delivery is 100%:

```sh
python -m pip install psutil
python scripts/run_arty_stress.py --interface enp3s0 \
  --board-ip 192.168.237.200
```

Interface names are supplied by the host OS (`enp3s0`, `en0`, `Ethernet 2`,
and so on). Use `--bind HOST_IP` instead of `--interface` when scripting a
known lab topology. `--duration`, `--rate-mbps`, `--packet-size`,
`--min-delivery-pct`, and `--mac` allow CI or multi-board setups to override
the strict defaults. The command exits nonzero on discovery/configuration
failure, board restart, loss, byte-accounting mismatch, any monitored
MAC/gate/DMA/driver error, or failed post-stress discovery.

DDR Ethernet line-rate testing on May 29, 2026 used the rebuilt DDR bitstream,
the current Zephyr DDR image, host NIC `Ethernet 3` at `192.168.137.1/24`, and
1472-byte UDP payloads. RX UDP sink runs passed at 80 Mbit/s requested
(`79.8 Mbit/s` sink payload), 95 Mbit/s requested (`94.8 Mbit/s` sink payload),
and 100 Mbit/s requested, where the sender naturally topped out at about
`95.9 Mbit/s` payload. All RX runs had zero MAC errors, gate drops, DMA errors,
RX allocation/submission failures, and UDP checksum errors. This is the
expected practical UDP payload ceiling for 100BASE-TX with MTU-sized packets.

The repaired application endpoint was revalidated on July 15, 2026 with the
host at `192.168.237.1/24` and 1472-byte payloads. Four-second requests at 10,
40, and 95 Mbit/s delivered respectively 3,397/3,397, 13,587/13,587, and
32,268/32,268 packets. The 95 Mbit/s run delivered 47,498,496 payload bytes at
94.950 Mbit/s. Every run had zero MAC errors, RX-gate drops, S2MM `tready`-low
cycles, DMA/BD errors, allocation failures, and refill starvation. This result
measures the application-owned port-5001 endpoint and the hardware/DMA ingress
path; it is not a claim that arbitrary Zephyr UDP sockets sustain line rate.

The same final firmware and portable runner then passed a continuous 600-second
95 Mbit/s test: `4,840,355 / 4,840,355` packets, `7,125,002,560` payload bytes,
`95.000 Mbit/s`, and `100.000000%` delivery. Deltas for sink errors, MAC
errors, bad/overflow gate drops, S2MM `tready`-low cycles, DMA errors, BD
errors, invalid frames, allocation failures, network submission failures, and
RX refill starvation were all zero. Post-stress board discovery also passed.

Board TX was also clean. The paced 95 Mbit/s request produced about
`82.8 Mbit/s` payload because of the board-side pacer, while unthrottled TX
delivered about `91.8 Mbit/s` by the host receive window with zero TX DMA
errors, zero TX error frames, and no store-forward backlog. The board's own TX
reply reports a larger payload rate because its accounting window does not map
directly to PHY wire time; use the host receive window for line-rate judgement.

Full-duplex testing ran a 95 Mbit/s host-to-board RX stream while the board
sent unthrottled TX back to the host. The board UDP sink received all
`48,401 / 48,401` RX packets (`71,246,272` bytes, `94.993 Mbit/s` payload) and
the host received `38,698` TX packets (`56,963,456` bytes, about
`92.5 Mbit/s` over the host receive window). The simultaneous run had zero MAC
RX errors, gate drops, DMA errors, RX failures, UDP checksum errors, TX DMA
errors, and TX error frames.

Standalone emacZero Arty A7-100T hardware sanity check, run with the board
connected over Digilent JTAG and the host NIC named `Ethernet 3` configured as
`192.168.137.1/24`:

```sh
python3 external/emacZero/fpga/arty_a7/scripts/run_hw_regression.py \
  --profile bidirectional-smoke \
  --board 192.168.137.200
```

The programmed standalone emacZero bitstream was
`external/emacZero/build_arty/arty_a7_top.bit`, built for
`xc7a100tcsg324-1` with timing met at `WNS = 0.129 ns`. The JTAG programming
helper used for this run filtered hardware devices by `PART == xc7a100t`
before programming. On this host, Windows Python could ping the board but did
not receive UDP replies; the same UDP tests passed from WSL. Test conditions
were Vivado hardware manager over the connected Digilent JTAG cable, board IP
`192.168.137.200`, host IP `192.168.137.1`, and the emacZero
`bidirectional-smoke` profile. Results:

- FPGA to host: 24626 / 24626 UDP packets, 91.81 Mbps, 0 gaps, 0 out-of-order.
- Host to FPGA: 29722 packets sent at 70.00 Mbps target; FPGA counted 29470
  packets and 43379840 bytes, 69.41 Mbps observed, 252 sequence gaps.

## Author and License

Author: Leonardo Capossio - [bard0 design](https://www.bard0.com) -
hello@bard0.com

This repository is licensed under Apache-2.0. The emacZero submodule carries
its own license in `external/emacZero/LICENSE`.
