# emacZero Zephyr Performance Plan

The current 1472-byte UDP receive ceiling is about 8 Mbit/s, or roughly
680 packets/s. On a 100 MHz MicroBlaze V-class core that is about 147k cycles
per packet, which is too high to explain as ordinary packet-copy or checksum
cost. Treat the present limit as a stall/drop/ownership bug until counters prove
otherwise.

## Near-Term Debug Order

1. Remove hot-path logging, printk, and UART output from measurement builds.
   UART at 115200 baud can cap throughput if any per-packet line leaks out.
2. Cross-check `k_cycle_get_32()` against `k_uptime_get()` over about
   30 seconds, then trust or fix the clock before interpreting cycles/packet.
3. Add BRAM-resident counters and read them after a run. Do not report
   per-packet data over UART or logs during the measurement window.
4. Replace zperf with a minimal UDP `recvfrom()` byte-counter sink. This
   distinguishes zperf consumer overhead from driver/net-stack loss.
5. Use the counters to find the packet-disappearance point: MAC, DMA callback,
   driver RX worker, `net_recv_data()`, socket receive, or buffer return.
6. Investigate the RX128 wedge before further pool tuning. A larger ring should
   provide headroom; if it wedges, suspect buffer ownership or return paths.
7. Only after the stall/drop path is understood, tune DMA batching and then
   cache/performance-mode settings.

## Optimizations To Keep

- Keep the performance build quiet: no periodic UART status loop and no zperf
  status callbacks during the measurement path.
- Keep RX zero-copy into Zephyr `net_buf` fragments so packet payloads are not
  copied before the socket boundary.
- Keep RX worker priority above ordinary application work.
- Use DMA interrupt coalescing and drain/refill bursts where the AMD DMA API
  allows it.
- Keep IPv6, TCP, UDP checksum verification, traffic classes, and unused
  logging disabled for UDP socket throughput tests.
- Prefer BRAM pool growth only after counters show buffer starvation; do not
  blindly increase descriptors while the RX128 ownership bug is unresolved.

## Target

For a 100 Mbps-style target with 1472-byte UDP payloads, the useful payload
ceiling is about 95 Mbit/s. A Zephyr socket path may not reach that, but it
should be well above 8 Mbit/s once stalls, logging, and buffer-return bugs are
removed.

## First Counter Results

Test conditions: Arty A7 100T MBV shell, 100 MHz core clock, 512 KiB BRAM,
emacZero RX64 ring, AMD AXI DMA interrupt threshold/timeout 32, 1472-byte UDP
payloads to port 5001, host at `192.168.137.1`, board at `192.168.137.200`.
The app was the minimal socket `recvfrom()` sink, not zperf.

At a requested 8.4 Mbit/s for 5 seconds, the host sent 3567 data packets and
the sink counted 3567 packets / 5,250,624 bytes. Driver counters showed no
RX allocation failures and no `net_recv_data()` failures. This clears the old
8.4 Mbit/s zperf wall as a zperf/logging/consumer artifact, not a MAC or DMA
drop point.

At a requested 20 Mbit/s for 5 seconds, the host sent 8492 data packets. The
driver saw about 8500 RX frames, but `rx_alloc_pkt_fail` and
`rx_refill_no_free` rose by thousands, while the sink only counted about 2947
additional packets. This is the next real bottleneck: RX packet/pool/socket
backlog pressure. Fix this before changing cache or rebuilding hardware.

The next optimization pass should focus on socket drain pressure and pool
return behavior: tighter RX batching, lower socket/sink overhead, verified
socket queue drop counters, and the unresolved RX128 wedge. Cache and broader
hardware tuning stay behind those items.

## Residency Counter Results

The driver now records pool high-water, zero-copy buffer dwell time, dwell
histogram buckets, and Zephyr UDP/IPv4 receive/drop stats into
`emaczero_perf_stats`. The measured residency interval is from the driver
zero-copy handoff into Zephyr to the external `net_buf` destroy callback that
returns the RX buffer.

RX64 at 8.4 Mbit/s is healthy with the quiet sink: host sent 3567 data packets,
the UDP stat and sink both counted 3567, and there were no RX allocation or
refill failures. Zero-copy dwell was almost entirely in the 1-5 ms bucket, with
a max dwell of about 2.4 ms. This confirms the old zperf wall was not a MAC/DMA
limit.

RX64 at 20 Mbit/s hits the real cliff. From the 8.4 Mbit/s baseline to the
20 Mbit/s run, the host sent 8492 packets, but the sink/UDP stat advanced by
only about 2837. The driver reported about 5546 RX packet allocation failures,
about 8492 refill-no-free events, and the pool high-water pegged at 64/64.
The dwell tail shifted badly: roughly 1750 returned buffers lived longer than
100 ms, with max dwell around 161 ms. This is not normal compute cost; buffers
are resident downstream long enough to starve DMA refill.

RX128 is not statically broken. With `CONFIG_ETH_EMACZERO_RX_BUFFER_COUNT=128`,
larger Zephyr RX pools, and about 445 KiB / 512 KiB BRAM used, the board was
stable at idle, answered 10/10 pings, and handled a 1 Mbit/s trickle without
allocation failures. It also handled 8.4 Mbit/s cleanly.

RX128 still fails under the 20 Mbit/s load, but differently: the CPU heartbeat
continues while ping stops. The MAC byte counter advances by about the full
stream, but DMA/driver RX callbacks barely advance after the failure. AXI DMA
S2MM status while wedged was `0x001E0019`, consistent with the receive DMA side
being halted/error-stopped rather than the CPU dying. So RX128 is not a simple
descriptor-count bug; it is load-triggered DMA/refill/ownership failure made
more likely by long packet residency and tight BRAM headroom.

Current conclusion: the immediate 20 Mbit/s blocker is downstream RX buffer
residency causing pool starvation. RX128 exposes a second, independent
refill/ownership bug: AXI DMA S2MM status `0x001E0019` decodes as halted,
scatter-gather enabled, and DMA internal error, with an interrupt threshold
status of `0x1e`. Treat that as the DMA engine fetching a bad or stale receive
BD/buffer after the refill path hits pressure, not as a normal starvation
stall.

The next controlled test is sink scheduling. The measured build ran the UDP
sink at priority 1 while the emacZero RX worker runs at priority 0. In Zephyr,
lower numeric priority is higher priority, so the consumer draining the socket
was below the driver handoff path. Run one RX64 20 Mbit/s test with the sink at
priority -1 and the same bitstream. If the dwell tail collapses, the socket
queue was holding buffers. If it does not, split the dwell counter at the
driver-to-`net_recv_data()` boundary and then fix the RX128 refill-on-empty
ownership bug.

## Sink Priority Test

Test conditions stayed the same as the RX64 residency run, except the UDP sink
thread priority was raised from 1 to -1. The board remained alive after the
run. The host sent 8492 1472-byte UDP packets in 5 seconds. Driver
zero-copy submissions reached 6426, and the sink received 3581 packets /
5,271,232 bytes.

The priority change removed the long residency tail: there were no RX packet
allocation failures, no `net_recv_data()` failures, and max zero-copy dwell
fell to about 1.25 ms. The dwell histogram moved entirely under 5 ms. This
proves the earlier 161 ms dwell / pool starvation result was mostly scheduler
backpressure from a lower-priority socket consumer.

The new loss point is inside Zephyr packet processing, not the RX pool.
The missing packets after driver handoff are almost exactly explained by
Zephyr statistics: `processing_error` 2618, IPv4 drops 221, and UDP drops 5.
The next build adds pre-stack raw-frame classification counters in the driver
so we can tell whether frames are already malformed before `net_recv_data()` or
whether Zephyr is rejecting otherwise valid frames because of packet metadata.

## Pre-Stack Classifier Results

The classifier build keeps the same RX64, quiet sink, 20 Mbit/s, 1472-byte UDP
conditions and adds raw Ethernet/IP/UDP counters immediately before
`net_recv_data()`. With DMA interrupt threshold/timeout still at 32, the host
sent 8492 packets. The driver reported 6411 zero-copy submissions. Of those,
only 3745 looked like UDP packets to port 5001 before Zephyr saw them. The
driver also saw 2645 frames with a destination MAC not matching the board,
broadcast, or multicast, and 2647 frames with a non-IPv4/non-ARP EtherType.
Those bad pre-stack counters match Zephyr's `processing_error` count, so the
packets are malformed or stale before the Zephyr L2/IP/socket path.

A diagnostic threshold-1 build used
`CONFIG_DMA_XILINX_AXI_DMA_INTERRUPT_THRESHOLD=1` and
`CONFIG_DMA_XILINX_AXI_DMA_INTERRUPT_TIMEOUT=1` with the same bitstream and
traffic. It did not improve the failure shape: 6416 zero-copy submissions,
3746 UDP-to-5001 pre-stack frames, 2645 destination-other frames, and 2646
type-other frames. This mostly rules out interrupt coalescing cleanup as the
primary cause.

Current conclusion: after the sink-priority fix, the remaining 20 Mbit/s
limit is below Zephyr's network stack. DMA/RX buffer ownership is sometimes
handing the driver buffers that do not contain the expected Ethernet frame.
Next debug should capture a compact sample of the first bad frame header and
length/status, then inspect the AXI DMA descriptor/refill path for stale
descriptor status, duplicate buffer ownership, or an RX stream framing issue.

## Bad Header Sample

The version-5 sample build captured the first malformed pre-stack header. The
bad sample length was 56 bytes and DMA status was 0. The first 16 bytes were:

```text
ff ff 00 e0 4c 68 00 76 08 06 00 01 08 00 06 04
```

That is not random memory. It looks like a normal ARP frame shifted left by
four bytes. A canonical ARP Ethernet frame would start with six destination
MAC bytes, six source MAC bytes, EtherType `08 06`, and then ARP fields
`00 01 08 00 06 04`. The captured bytes look like the first four Ethernet
bytes are missing and the packet begins at byte 4 of the frame.

This sharpens the diagnosis: the current 20 Mbit/s loss is probably an RX
stream/DMA framing or alignment problem, not Zephyr socket overhead, not RX
pool residency, and not interrupt coalescing. The next hardware/software
boundary check should probe `M_AXIS` into S2MM around `tvalid/tready/tlast`
and confirm that the first beat of each frame is accepted exactly once. Also
audit any AXI-Stream width/keep conversion in the emacZero-to-DMA path, because
a missing first 32-bit word matches the captured failure pattern.

## ELA Hardware Capture

An fcapz ELA probe was wired onto the emacZero RX AXI-stream boundary feeding
AXI DMA S2MM. The trigger was `rx_bad_header`, derived from the stream header
checker, while sampling `m_axis_tdata`, `tvalid`, `tready`, `tlast`, `tsof`,
and emacZero's `m_axis_terror`.

The captured fault is not a DMA descriptor formatting issue. The trigger cycle
decoded as:

```text
tvalid=1 tready=1 tlast=1 tsof=0 terror=1 rx_bad_header=1
```

The next accepted frame began immediately after with `tsof=1`, but the first
accepted bytes were only:

```text
02 00 00 00
```

The important new fact is `m_axis_terror=1` on the bad frame. emacZero is
explicitly marking the outgoing AXI-stream frame as errored, but AXI DMA S2MM
does not consume that sideband in this design. The DMA therefore writes a
partial/invalid frame into memory and reports a normal completion to the
driver. That matches the software observation: DMA status 0 with a malformed
Ethernet header.

Root cause to fix next: the RX MAC path can emit errored frames under
downstream backpressure, likely because the internal RX FIFO overflows before
the full frame and CRC decision are known. Since the DMA path cannot retract
bytes already written, the hardware boundary must either become store-and-
forward for RX frames before DMA, or add an error-aware frame-drop stage before
S2MM that buffers until `tlast` and only releases known-good frames.

## Bug A Containment

Implemented `axis_frame_error_drop` in the Arty wrapper between emacZero RX
`M_AXIS` and AXI DMA S2MM. It buffers one complete byte-wide AXI-stream frame,
forwards only frames that reach `tlast` without `terror`, and drops errored
frames before DMA can write partial/corrupt data into memory. This is the
correctness fix for the missing AXI DMA error-sideband problem.

The direct simulation `tb_axis_frame_error_drop` passes:

```text
AXIS-FRAME-ERROR-DROP: ALL TESTS PASSED
```

## Bug B Reproducer

Added `tb_emaczero_rx_burst_backpressure_bug` as the executable Bug B target.
It sends a clean 1514-byte Ethernet frame through `eth_mac_tx` into
`eth_mac_rx`, briefly deasserts RX `tready` mid-frame, and fails if the clean
frame raises `m_axis_terror` or the Ethernet header shifts.

The initial emacZero RX path failed this test:

```text
FAIL: clean frame raised m_axis_terror under backpressure
EMACZERO-RX-BURST-BACKPRESSURE-BUG: TESTS FAILED
```

The fix was to raise `eth_mac_rx`'s default AXIS output FIFO depth from
256 bytes to 1024 bytes. The PHY cannot be backpressured, so a tiny byte-wide
RX FIFO can turn ordinary DMA stalls into FIFO overflow, which then raises
`m_axis_terror` on otherwise clean traffic. The system wrapper still keeps the
2048-byte store-and-forward error-drop stage in front of DMA, so full-frame
correctness does not depend on the MAC-internal FIFO being a complete MTU.
With the larger internal stall buffer, the Bug B reproducer now passes:

```text
EMACZERO-RX-BURST-BACKPRESSURE-BUG: ALL TESTS PASSED
```

This fixes the simulated Bug B pressure case. Bug A's DMA-facing error-drop
gate remains useful as a correctness guard for real CRC/PHY errors and for any
future overflow cases beyond the FIFO's buffering envelope.

## Board Retest After Bug B

The fixed bitstream programmed and minimal Zephyr still boots on the Arty A7
100T. The first DMA-enabled Zephyr networking image did not reach `main()`.
A no-DMA overlay, with emacZero still present, did reach `main()`, read the
MAC registers, assigned `192.168.137.200/24`, and started the UDP sink. That
isolated the boot failure to the Xilinx AXI DMA device init path.

The local AMD/Xilinx Zephyr DMA driver enabled both DMA IRQs during
`dma_xilinx_axi_dma_init()`, before `dma_configure()` had assigned
`channel_regs` and descriptor rings. On this design that can take an early
DMA interrupt into an ISR with uninitialized channel state. The tested local
fix connects IRQs at init, but enables the per-channel IRQ in `dma_start()`
after the channel has been configured. The patch is captured in
`patches/zephyr/0001-xilinx-axi-dma-enable-irqs-after-start.patch`.

With that patch applied to the local Zephyr checkout, the cleaned DMA-enabled
image reaches:

```text
MBV Zephyr emacZero main
EMZ VER=0x0001454D
MBV ipv4 192.168.137.200/24
MBV udp sink port 5001
```

Board ping after the BRAM load replied 3/4 packets, with the first packet
timing out and the remaining replies at 12 ms, 3 ms, and 97 ms. This proves
the post-Bug-B hardware and DMA-enabled Zephyr path are alive again; it is not
yet a throughput or packet-loss closure.

## Post-Bug-B Throughput Split

The valid traffic source for the current board setup is WSL. Windows Python
UDP sends did not reliably reach Ethernet 3 even when ping worked; the board
mostly saw unrelated broadcast UDP. WSL UDP reached the board and should be
used for the next measurements.

With `CONFIG_NET_IPV4_MTU=1500` and `CONFIG_ETH_EMACZERO_RX_DMA_POST_COUNT=63`,
an 8.4 Mbit/s, 1472-byte UDP run sent 3567 packets from the host. The board
sink received about 3090-3140 packets, or roughly 7.3 Mbit/s. The Zephyr stack
is not the loss point in this run: `rx_net_recv_fail=0`, `dma_errors=0`,
`net_udp_recv` matches the sink, `processing_error=0`, and the maximum
stack-owned RX buffer count stayed at 1.

A controlled before/after counter delta showed:

```text
host packets       3567
MAC RX frames     +3217
DMA callbacks     +3147
UDP sink packets  +3139
MAC RX overflow   +359
MAC RX errors     +21
```

So the remaining loss is primarily hardware-front-end backpressure, not Zephyr
socket residency. The MAC-internal RX FIFO still overflows under host bursts
and DMA/backpressure stalls. The store-and-forward `axis_frame_error_drop`
correctly prevents errored frames from reaching DMA, but it also makes the RX
path more sensitive to bursts because the non-backpressureable PHY must be
absorbed by upstream buffering while downstream drains/refills.

The next hardware experiment raised `eth_mac_rx`'s default AXIS output FIFO
from 1024 bytes to 2048 bytes. A 4096-byte experiment did not place because the
current 512 KiB BRAM system already uses essentially all Arty A7 100T block RAM:
the routed 2048-byte build reports 135 / 135 block RAM tiles used. Any larger
hardware RX elasticity now has to be an explicit memory trade: reduce MBV BRAM,
remove debug BRAM, or redesign the buffering so it buys more with the same RAM.

After changing the RX FIFO depth, the focused simulations still pass:

```text
EMACZERO-RX-BURST-BACKPRESSURE-BUG: ALL TESTS PASSED
AXIS-FRAME-ERROR-DROP: ALL TESTS PASSED
```

The 2048-byte bitstream programmed and Zephyr booted, but the board throughput
did not materially improve. In a WSL 8.4 Mbit/s run, the host sent 3567
packets and the sink received 3091 packets. The useful counter deltas were:

```text
host packets       3567
MAC RX frames     +3216
DMA callbacks     +3097
UDP sink packets  +3091
MAC RX overflow   +356
MAC RX errors     +72
```

This is almost the same loss shape as the 1024-byte build. The 2048-byte routed
build also has a timing violation (`WNS=-0.296 ns`), so it is only a diagnostic
image, not a closure candidate.

The conclusion is that simply doubling the MAC RX FIFO is not enough. Either
the downstream `axis_frame_error_drop`/DMA path can hold `mac_rx_tready` low for
longer than one extra frame, or the remaining loss is caused by a narrower
backpressure point that the larger MAC FIFO does not address. The next best
hardware debug is to expose or capture:

- error-drop `good_frames`, `dropped_bad_frames`, and `dropped_overflow_frames`
- cycles where `mac_rx_tvalid=1` and `mac_rx_tready=0`
- cycles where DMA-facing `m_axis_tvalid=1` and `m_axis_tready=0`
- `eth_mac_rx` FIFO overflow pulses aligned with those ready stalls

If the ELA shows `axis_frame_error_drop` is blocking the MAC while draining a
good frame, replace it with a two-slot/ping-pong store-and-forward gate so it
can accept the next frame while DMA drains the previous one. If the DMA-facing
stall dominates, free BRAM and add a larger post-MAC/pre-DMA elastic buffer, or
move to a wider AXI-stream path so drain time is not byte-serial.

## Smoking-Gun Measurement Pass

Before another optimization build, the hardware now exposes the single-slot
error-drop gate as a read-only AXI-Lite debug page at emacZero offset `0x100`.
Zephyr copies those values into `emaczero_perf_stats` version 8 so the normal
`no_commit/read_perf_stats.py` path can read them after a traffic run.

The debug page is:

```text
0x100 gate magic                  0x45525a47
0x104 good frames forwarded
0x108 bad frames dropped on terror
0x10c gate-local overflow drops
0x110 drain samples
0x114 drain cycles total
0x118 drain cycles max
0x11c drain < 50 us
0x120 drain 50-100 us
0x124 drain 100-200 us
0x128 drain 200-500 us
0x12c drain >= 500 us
```

The histogram measures the time from when a complete good frame enters the
gate's drain state until that frame's `tlast` is accepted by AXI DMA. At the
100 MHz system clock, the bucket boundaries are 5k, 10k, 20k, and 50k cycles.

Interpretation for the next board run:

- `dropped_bad_frames` near zero means Bug B is mostly hidden/silent and the
  visible loss is MAC FIFO overflow/backpressure.
- `dropped_bad_frames` rising means Bug B still contributes independently and
  must be chased after the backpressure fix.
- drain samples mostly below 100 us means a two-slot ping-pong gate should
  cover 100 Mbps MTU traffic.
- a fat tail above 200 us means AXI DMA occasionally stalls; ping-pong helps
  but the DMA-side latency still needs attention.
- steady drain above 120 us means the DMA drain path is the bottleneck, not the
  single-slot gate alone.

The focused simulations still pass after adding the counters:

```text
AXIS-FRAME-ERROR-DROP: ALL TESTS PASSED
EMACZERO-RX-BURST-BACKPRESSURE-BUG: ALL TESTS PASSED
```

## Gate Drain Measurements

Test conditions: Arty A7 100T MBV shell, 100 MHz system clock, 512 KiB BRAM,
diagnostic gate-counter bitstream, Zephyr `emaczero_perf_stats` version 8,
`CONFIG_NET_IPV4_MTU=1500`, `CONFIG_ETH_EMACZERO_RX_DMA_POST_COUNT=63`,
1472-byte UDP payloads from WSL to board port 5001. The useful Zephyr image was
the quiet minimal UDP sink with the sink thread at priority -1.

At a requested 8.4 Mbit/s for 5 seconds, WSL sent 3567 packets. The board
accepted 3153 additional good gate frames and the sink received 3142 packets,
or about 7.4 Mbit/s of UDP payload. The important deltas were:

```text
host packets                 3567
gate good frames            +3153
gate bad-frame drops          +19
gate-local overflow drops     +65
MAC RX overflow              +342
DMA callbacks               +3153
UDP sink packets            +3142
drain samples               +3153
drain <50 us                 +689
drain 50-100 us               +52
drain 100-200 us             +110
drain 200-500 us             +296
drain >=500 us              +2006
drain total cycles     304,978,030
average drain          ~96,726 cycles/frame, ~967 us/frame
```

At a requested 20 Mbit/s for 5 seconds, WSL sent 8492 packets. The board still
accepted only about the same number of good gate frames, so useful throughput
stayed near 7.4 Mbit/s. The important deltas relative to the 8.4 Mbit/s ending
baseline were:

```text
host packets                 8492
gate good frames            +3153
gate bad-frame drops          +99
gate-local overflow drops   +1360
MAC RX overflow             +3948
DMA callbacks               +3159
UDP sink packets            +3140
drain samples               +3153
drain <50 us                 +128
drain 50-100 us                +1
drain 100-200 us               +0
drain 200-500 us              +25
drain >=500 us              +2999
drain total cycles     457,478,236
average drain         ~145,100 cycles/frame, ~1.451 ms/frame
```

This collapses the current failure surface. The Zephyr socket path is not the
dominant ceiling in these runs: once the sink priority was fixed, RX dwell was
short, `net_recv_data()` stayed healthy, and the sink matched the DMA callback
rate for accepted frames. The hard limit is that the single-slot
store-and-forward gate can only drain about 630 frames/s into AXI DMA S2MM.

That is far too slow for a byte-wide 100 MHz AXI-stream datapath. A 1514-byte
frame should drain in roughly 15 us if `s_axis_s2mm_tready` stays high, and a
100 Mbps MTU stream presents a frame about every 120 us. The measured
967-1451 us/frame drain means AXI DMA is deasserting `tready` for long windows.
The resulting backpressure overflows the non-backpressureable MAC/PHY RX side.

The ping-pong gate remains the right architectural guard against normal DMA
jitter, but it is not sufficient by itself with millisecond-scale drain time.
Two 2 KiB slots only cover one extra MTU frame; at the measured 20 Mbit/s drain
rate the system would need many slots just to postpone the same overflow. The
next fix should therefore target S2MM readiness/descriptor service first:

- inspect whether the Zephyr Xilinx AXI DMA API path is effectively servicing
  one RX frame at a time despite a large SG ring;
- capture or count DMA-facing `tvalid && !tready` windows with ELA to confirm
  the gate histogram directly at the stream boundary;
- read AXI DMA S2MM status and, if needed, descriptor indices/status after a
  run to distinguish descriptor starvation, interrupt cleanup latency, and bus
  contention;
- only after S2MM drain is mostly below 120 us, add a two-slot or small
  multi-slot error-drop gate as a cheap burst/jitter cushion.

Bug B is still present but no longer poisons software packets. The gate dropped
19 bad frames at 8.4 Mbit/s and 99 at 20 Mbit/s, so the upstream corruption or
overflow path still fires under pressure. It should stay open, but the dominant
20 Mbit/s loss is currently MAC RX overflow caused by DMA-side backpressure.

## DMA Register And ELA Follow-Up

An ignored helper, `no_commit/read_axi_dma_regs.py`, now reads the AXI DMA
register block and selected SG descriptors through fcapz EJTAG-AXI. After the
gate-drain tests, S2MM was alive rather than wedged:

```text
S2MM DMACR    0x20207003
S2MM DMASR    0x00200008  SGINCL, IRQTHRESHSTS=32
S2MM CURDESC  advancing slowly through the RX BD ring
S2MM TAILDESC posted behind CURDESC in the circular ring
```

This is different from the earlier RX128 failure (`DMASR=0x001E0019`, halted
with internal error). The current RX64 performance problem is an active SG DMA
path that drains too slowly, not a stopped DMA engine.

Selected RX descriptors around `CURDESC` and `TAILDESC` were armed with valid
buffer addresses and control values such as `0x0c0005ea`, which corresponds to
a 1514-byte buffer with SOF/EOF bits set by the generic Zephyr Xilinx AXI DMA
driver. Descriptors immediately outside the current owned window can have
`control=0`, which is expected after ISR cleanup and before the emacZero refill
path re-posts them.

A live register sample during a 20 Mbit/s run showed S2MM pointers moving only
slowly while traffic continued. Because fcapz EJTAG-AXI itself arbitrates onto
the same AXI fabric, this host-side polling can perturb the bus and should not
be treated as a precise timing measurement. It is still consistent with the
gate histogram: the DMA is not starved of descriptors, but its stream-side
readiness is intermittent.

The on-chip ELA was also run during 20 Mbit/s traffic with the current probe
map. Captures such as `no_commit/ela_dma_stall_bit.json` show long windows
where the DMA-facing RX stream has `tvalid=1` while `tready=0`
(`dma_rx_axis_stall=1`), with accepted bursts separated by stall windows. The
summary's trigger bookkeeping did not show the expected trigger bit, so this
capture should be treated as supporting evidence rather than final ELA closure.
The next ELA build should make the stall counter and trigger less ambiguous,
ideally by exposing a wider `tvalid && !tready` run counter and a dedicated
capture trigger bit that is also latched into the sample stream.

Current narrowed hypothesis: the shared BRAM/AXI memory system is creating
large per-frame S2MM readiness gaps. The Zephyr Xilinx AXI DMA driver does
use a one-buffer `dma_reload()` / `dma_start()` API shape, and that is still
not the receive-ring architecture we want. However, live S2MM register and BD
reads show the DMA is not simply starved for descriptors: it is running with
valid descriptors still posted ahead of the current descriptor. That shifts
the primary suspicion toward the hardware memory topology: MBV instruction
fetch, MBV data accesses, AXI DMA S2MM writes, AXI DMA SG descriptor reads and
writebacks, and fcapz debug traffic all arbitrate through the same 32-bit AXI
BRAM path. The hardware shell also has MBV I/D LMB disabled and the BRAM
controller configured as single-port. The next structural fix should reduce
that memory contention, ideally by moving MBV code/data onto LMB or a separate
CPU-local BRAM while keeping DMA descriptors and packet buffers in
AXI-visible BRAM.

## AMD AXI DMA Driver Audit

The local AMD/Xilinx Zephyr driver does allocate an SG descriptor ring, but the
RX path does not use it as a permanently owned Ethernet receive ring. The
driver's `dma_xilinx_axi_dma_config_reload()` path explicitly calls the helper
as a "one-block-at-a-time transfer":

```text
dma_reload()
  -> dma_xilinx_axi_dma_transfer_block()
       writes one descriptor at current_transfer_start_index

dma_start()
  -> tail_descriptor = current_transfer_start_index++
  -> writes TAILDESC to that one newly posted descriptor
```

The emacZero driver maps each RX buffer post onto that API shape:

```text
first RX buffer:
  dma_config(... block_count=1, num_sg_descriptors=RX_BUFFER_COUNT ...)
  dma_start()

every later RX buffer:
  dma_reload(... rx->bytes, sizeof(rx->bytes))
  dma_start()
```

So the current system is "SG-enabled" but not "persistent-ring driven." During
initial refill it posts many descriptors by repeatedly writing one descriptor
and updating `TAILDESC`. During steady-state buffer return it repeats the same
per-buffer `dma_reload()` / `dma_start()` sequence. Completion cleanup also
clears each completed descriptor's `control` and `status` before the callback,
so a descriptor is not reusable by hardware until software writes it again.

This matches the board data: changing interrupt threshold from 32 to 1 did not
change the measured drain wall, because the expensive part is not IRQ entry
itself. The path still has a per-frame descriptor service dependency before
S2MM can keep accepting the next good frame.

The emacZero perf struct is now version 9 and adds counters for this exact API
shape:

```text
rx_dma_config_calls
rx_dma_reload_calls
rx_dma_start_calls
rx_dma_config_fail
rx_dma_reload_fail
rx_dma_start_fail
```

The Zephyr-only v9 run confirmed the API shape, but also showed it is not the
whole story. At 20 Mbit/s for 5 seconds:

```text
host packets                 8492
gate good frames            +3033
gate bad-frame drops         +217
gate-local overflow drops   +1263
MAC RX overflow             +4030
DMA callbacks               +3109
UDP sink packets            +3025
rx_refill_queued            +3109
rx_refill_no_free           +3002
rx_dma_config_calls            +0
rx_dma_reload_calls         +3109
rx_dma_start_calls          +3109
rx_dma_*_fail                  +0
drain samples               +3033
drain >=500 us              +2865
drain total cycles     452,219,150
average drain         ~149,100 cycles/frame, ~1.49 ms/frame
```

This confirms one reload/start pair per completed RX buffer. But the post-run
DMA state remained healthy:

```text
S2MM DMACR    0x20207003
S2MM DMASR    0x00200008  (SGINCL, no error, not halted)
S2MM CURDESC  0x80030780
S2MM TAILDESC 0x800306c0
BD control    0x0c0005ea
BD status     0x00000000
```

In other words, the driver has descriptors posted, the DMA channel is not in an
error state, and the ring still contains ready BDs. The millisecond drain
therefore should not be explained as simple descriptor starvation. A custom
emacZero-owned persistent RX BD ring may still remove software overhead and
make ownership cleaner, but it is unlikely to turn a 1.49 ms hardware drain
into a line-rate drain by itself. The next best experiment is a hardware memory
split: enable MBV LMB or otherwise move instruction/data traffic away from the
AXI BRAM path used by the DMA packet buffers and SG descriptors, then rerun
the same v9 counter test without changing the Ethernet software.

## DMA Threshold-1 Retest

A Zephyr-only image was rebuilt with the same diagnostic bitstream and:

```text
CONFIG_ETH_EMACZERO_RX_DMA_POST_COUNT=63
CONFIG_DMA_XILINX_AXI_DMA_INTERRUPT_THRESHOLD=1
CONFIG_DMA_XILINX_AXI_DMA_INTERRUPT_TIMEOUT=1
CONFIG_NET_IPV4_MTU=1500
```

The image booted from BRAM and reported the same `emaczero_perf_stats` address,
`0x8002bec0`. S2MM was live with `DMASR=0x00010008`
(`SGINCL`, `IRQTHRESHSTS=1`).

At a requested 20 Mbit/s for 5 seconds, WSL sent 8492 packets. The deltas from
the post-boot baseline were:

```text
host packets                 8492
gate good frames            +3056
gate bad-frame drops         +266
gate-local overflow drops   +1253
MAC RX overflow             +3965
DMA callbacks               +3105
UDP sink packets            +3049
drain samples               +3056
drain <50 us                 +131
drain 50-100 us                +0
drain 100-200 us               +8
drain 200-500 us              +71
drain >=500 us              +2846
drain total cycles     447,643,412
average drain         ~146,480 cycles/frame, ~1.465 ms/frame
```

This is essentially the same ceiling as the threshold-32 run. Reducing the DMA
interrupt threshold/timeout does not fix the S2MM readiness gap. The loss is
therefore not primarily caused by interrupt coalescing waiting too long before
the driver refills descriptors. The next useful change is not another Kconfig
threshold sweep; it is a structural DMA-side experiment, such as bypassing the
generic reload/start path with an emacZero-owned persistent RX BD ring, or
changing the hardware path so the DMA-facing stream/memory write service time
is not millisecond-scale.

## LMB / DMA-BRAM Split Experiment

The first CPU/DMA memory split uses two 256 KiB BRAM regions:

```text
0x80000000..0x8003ffff  256 KiB MBV local LMB BRAM
                         Zephyr code, data, stack, heap, net packets

0x80040000..0x8007ffff  256 KiB AXI BRAM
                         AXI DMA packet buffers, AXI DMA SG descriptors,
                         emacZero fixed perf page at 0x8007f000
```

The Zephyr image fits the local LMB region:

```text
RAM used          202,960 B / 256 KiB = 77.42%
_image_ram_end    0x800318d0
DMA stats page    0x8007f000
```

The AXI DMA driver was patched locally to allow an external SG descriptor
allocator. The emacZero driver overrides that allocator and places SG
descriptors plus RX/TX packet buffers in the DMA-visible AXI BRAM window. This
keeps normal CPU code/data traffic off the DMA memory path. There is no bulk
copy between local LMB and DMA BRAM for RX zero-copy buffers; the CPU still
touches the DMA buffers directly when Zephyr owns a received packet, but
instruction fetches, stack traffic, and normal data live in LMB.

Vivado generated a bitstream and Zephyr booted on the board, but the routed
build is not timing clean:

```text
WNS -0.050 ns, TNS -0.151 ns, 3 failing sys_clk endpoints
Worst setup path: AXI UART decode -> fcapz EJTAG-AXI response FIFO reset
```

The board smoke test proved the split is functional. After programming the
bitstream, the fixed stats page at `0x8007f000` reported:

```text
magic/version          valid, version 9
cycles_per_sec         100,000,000
rx_pool_size           64
idle gate samples      23
idle gate drain <50us  23
idle drain total       2,899 cycles across 23 frames
```

That is a major change from the old idle/shared-BRAM behavior: the simple
drain path can now be microsecond-scale.

The 20 Mbit/s UDP run still does not hold throughput:

```text
host sent packets              8,492
sink packets                   3,152
sink bytes                 4,639,744
MAC RX overflow                5,281
gate good frames               3,188
gate bad-frame drops              13
gate-local overflow drops         48
gate drain samples             3,188
gate drain <50us               3,138
gate drain >=500us                50
gate drain max cycles      6,348,292  (~63.5 ms)
gate drain total cycles  320,402,706
rx_dwell <1ms                  3,188
rx_dwell max cycles           31,316  (~313 us)
rx_dma_reload_calls            3,250
rx_dma_start_calls             3,251
rx_dma_*_fail                      0
```

Conclusion: the memory split removed the constant millisecond-scale drain cost,
but not the burst starvation failure. Most frames drain quickly; a small number
of very long S2MM-not-ready gaps dominate the run and cause thousands of MAC
FIFO overflows. Since RX dwell is entirely below 1 ms and the stack-owned high
water is only 1, this is not the old socket residency problem. The next
investigation should target the source of the rare long RX DMA service gaps:
DMA SG refill cadence, the Zephyr generic DMA reload/start path, AXI DMA
internal queue behavior, or a hidden memory/fabric arbitration tail.

## Silent Output Control Test

A follow-up Zephyr-only image added `CONFIG_ETH_EMACZERO_RAW_UART=n`, which
compiles the application raw UARTLite status writes into no-ops. The test image
also used the existing console/log-disabled performance config and the same
RX post count of 63. Vivado was not re-synthesized or re-implemented; the
routed checkpoint was reopened and a new bitstream was written after replacing
only the staged MicroBlaze V ELF.

The silent image booted with no EJTAG-UART text, and the baseline counters
matched the previous image:

```text
stats page             0x8007f000, valid version 9
cycles_per_sec         100,000,000
idle gate samples      23
idle gate drain <50us  23
idle drain total       2,899 cycles across 23 frames
```

The same 20 Mbit/s UDP run produced essentially the same loss shape:

```text
host sent packets              8,492
sink packets                   3,152
sink bytes                 4,639,744
MAC RX overflow                5,243
gate good frames               3,182
gate bad-frame drops              49
gate-local overflow drops         49
gate drain samples             3,182
gate drain <50us               3,132
gate drain >=500us                50
gate drain max cycles      6,379,156  (~63.8 ms)
gate drain total cycles  319,953,476
rx_dwell <1ms                  3,182
rx_dwell max cycles           31,371  (~314 us)
rx_dma_reload_calls            3,244
rx_dma_start_calls             3,245
rx_dma_*_fail                      0
```

This rules out the obvious UART/logging explanation for the 63 ms tail. The
app's direct UART status path is silent, Zephyr's normal UART device remains
disabled, and the drain distribution is unchanged. The next step should be
hardware/CPU correlation rather than more output suppression: trigger ELA on a
long `s_axis_s2mm_tready` low interval and capture RX gate state, DMA stream
handshake, DMA interrupt/refill pulses, and CPU-side ISR/refill activity.

## LMB Threshold-1 and v10 Callback-Gap Test

The LMB split was retested with:

```text
CONFIG_ETH_EMACZERO_RAW_UART=n
CONFIG_ETH_EMACZERO_RX_DMA_POST_COUNT=63
CONFIG_DMA_XILINX_AXI_DMA_INTERRUPT_THRESHOLD=1
CONFIG_DMA_XILINX_AXI_DMA_INTERRUPT_TIMEOUT=1
```

Changing the interrupt threshold/timeout after the LMB split did not change
the failure shape:

```text
host sent packets              8,492
sink packets                   3,112
MAC RX overflow                5,142
gate good frames               3,144
gate bad-frame drops             190
gate-local overflow drops         49
gate drain samples             3,144
gate drain <50us               3,095
gate drain >=500us                49
gate drain max cycles      6,350,649  (~63.5 ms)
gate drain total cycles  311,714,224
rx_dwell <1ms                  3,144
rx_dma_*_fail                      0
```

Post-run AXI DMA state again showed S2MM live, SG enabled, no error bits:

```text
S2MM DMACR    0x01017003
S2MM DMASR    0x00010008  (SGINCL, IRQTHRESHSTS=1)
S2MM CURDESC  0x80059ac0 -> later snapshots advanced
S2MM TAILDESC 0x80059a00 -> later snapshots advanced
```

Descriptor snapshots around current/tail showed valid `control=0x0c0005ea`,
valid buffer pointers in the DMA BRAM window, and `status=0` for the posted
BDs around the active window. The engine is not halted or in a hard descriptor
error state after the run.

Perf stats version 10 added software-side timing counters:

```text
dma_callback_gap_cycles_max
dma_callback_gap_ge_1ms
rx_refill_cycles_max
rx_refill_cycles_ge_1ms
rx_refill_queued_max
```

The v10 threshold-1 run produced:

```text
host sent packets              8,492
sink packets                   3,089
MAC RX overflow                5,133
gate good frames               3,125
gate bad-frame drops             225
gate-local overflow drops         47
gate drain <50us               3,076 / 3,125
gate drain >=500us                49 / 3,125
gate drain max cycles      6,348,083  (~63.5 ms)
dma_callback_gap_ge_1ms           73  (baseline before UDP was 12)
rx_refill_cycles_max          74,019  (~740 us, from initial 63-buffer post)
rx_refill_cycles_ge_1ms            0
rx_refill_queued_max              63
rx_dwell <1ms                  3,125
```

This refines the theory. The long stalls are not caused by the driver's refill
function spending milliseconds blocked: no refill call exceeded 1 ms. Instead,
the DMA completion stream itself has long gaps; the count of callback gaps over
1 ms rises by about the same order as the gate's long-drain events. The system
appears to alternate between normal fast operation and periods where S2MM stops
completing frames even though software eventually has buffers available and the
post-run DMA registers show no hard error.

Current best theory: the generic Zephyr Xilinx AXI DMA SG API usage leaves the
S2MM engine with only a shallow hardware-usable descriptor runway, even though
the emacZero driver thinks 63 buffers are DMA-owned. Under burst traffic the
hardware-visible runway periodically empties; during that empty interval
`s_axis_s2mm_tready` drops, the RX gate cannot drain, and the MAC FIFO
overflows. Because refill calls are short and successful, the bug is likely in
descriptor/tail ownership semantics or AXI DMA internal SG fetch/update
behavior, not in CPU time spent inside `emz_refill_dma_rx()`.

The next high-value proof is an ELA trigger on a long S2MM `tready` low window,
capturing `s_axis_s2mm_tvalid/tready/tlast`, the RX gate state, AXI DMA IRQ,
and a hardware pulse on software `dma_reload()` / `dma_start()` / refill
events if exposed. The likely fix remains an emacZero-owned persistent RX BD
ring that keeps a true hardware descriptor runway independent of per-packet
Zephyr DMA API cadence.

## Direct RX Descriptor Ring

The AXI DMA driver audit confirmed the software-architecture mismatch. The
Zephyr Xilinx AXI DMA path uses the generic DMA API as a transactional
one-block-at-a-time interface: `dma_reload()` fills the descriptor at
`current_transfer_start_index`, and each `dma_start()` advances that index and
writes one new `TAILDESC`. That is not the right ownership model for streaming
Ethernet RX.

The emacZero driver now has a Kconfig-gated direct RX ring path:
`CONFIG_ETH_EMACZERO_RX_DIRECT_RING=y`. In this mode emacZero owns the AXI DMA
S2MM SG ring directly, keeps TX on Zephyr's generic DMA API, connects the RX
DMA interrupt itself, and records direct-ring counters such as
`rx_bd_hw_completed`, `rx_bd_refilled`, `rx_bd_tail_updates`, and
`rx_bd_available_min`. The old generic RX DMA path remains buildable for A/B
testing by leaving the Kconfig option disabled.

This does not bypass the Zephyr network stack. The packet path is still:

```text
emacZero MAC
  -> AXI-Stream error-drop gate
  -> AXI DMA S2MM
  -> emacZero-owned RX BD ring
  -> Zephyr net_pkt / net_buf
  -> Zephyr Ethernet L2
  -> Zephyr IPv4 / UDP
  -> Zephyr socket recvfrom()
```

Only the generic Zephyr DMA API is bypassed on the receive hot path. That API
models transactional transfers (`dma_reload()` / `dma_start()` / callback),
while streaming Ethernet RX needs a persistent descriptor ring of pre-posted
packet buffers. Having the Ethernet driver own the RX BD ring is the normal
architecture for high-throughput network drivers; the OS networking stack still
receives packets through its normal `net_pkt` / `net_buf` interface.

The first board run used the existing implemented Arty A7-100T MBV bitstream,
with only the Zephyr ELF injected into BRAM. Test conditions: 100 MHz MBV,
256 KiB LMB code/data at `0x80000000`, 256 KiB DMA AXI BRAM at `0x80040000`,
64 RX buffers, 63 posted RX descriptors, quiet 1472-byte UDP sink, host sending
to board `192.168.137.200:5001`.

At requested 20 Mbit/s for 5 seconds, the host sent 8492 packets and the sink
received 8486 packets / 12,491,392 bytes. Hardware flow counters were healthy:
`mac_rx_err_overflow=0`, `gate_drain_ge_500us=0`, `gate_drain_cycles_max=1515`,
`rx_bd_hw_completed=8525`, and all generic RX DMA API counters stayed zero.
The old 63 ms DMA starvation tail is gone.

The same source tree was A/B tested with the direct-ring Kconfig disabled and
the old generic RX DMA path enabled, using the same implemented design and a
fresh ELF-injected bitstream. At the same requested 20 Mbit/s for 5 seconds,
the old path received only 3152 UDP sink packets / 4,639,744 bytes, reported
`mac_rx_err_overflow=5250`, `gate_drain_ge_500us=50`,
`gate_drain_cycles_max=6352802`, `dma_callback_gap_ge_1ms=67`, and
`rx_dma_reload_calls=3240`. That is the direct before/after proof that the
Zephyr generic RX DMA API path was the 20 Mbit/s blocker.

At requested 30 Mbit/s for 5 seconds, the host sent 12738 packets and the sink
received 12696 packets / 18,688,512 bytes. Again,
`mac_rx_err_overflow=0`, `gate_drain_ge_500us=0`, and `rx_bd_errors=0`.
The remaining packet loss was dominated by 44 `gate_dropped_bad_frames`, which
is Bug B (`terror` on otherwise expected traffic) becoming visible after the
DMA starvation fix.

At requested 40 Mbit/s and 50 Mbit/s, the sink plateaued near 13.4k packets
per 5 seconds, and MAC/gate overflow returned. At 40 Mbit/s the gate reported
1656 overflow drops, with most drain samples in the 200-500 us bucket. At
50 Mbit/s the gate reported 2993 overflow drops and 22 samples above 500 us.
So the direct RX ring moved the design from "not clean at 20 Mbit/s" to
"clean around 30 Mbit/s, overflow around 40 Mbit/s."

Current conclusion: the direct RX descriptor ring fixed the software ownership
problem and removed the catastrophic DMA completion gaps. The next bottleneck
is the single-slot store-and-forward error-drop gate plus the residual Bug B
`terror` source. Next hardware step is a 2-4 slot ping-pong/multi-slot
error-drop gate so one frame can drain to DMA while the next frame is accepted
from emacZero. In parallel, keep probing Bug B by correlating `terror` with
RX FIFO occupancy/backpressure inside emacZero.

## DMA TREADY During Gate Drain

Stats version 12 added three gate counters:
`gate_drain_tready_low_cycles`, `gate_drain_tready_low_cycles_max`, and
`gate_drain_tready_low_samples`. These count cycles where the error-drop gate
is actively presenting data to AXI DMA S2MM (`m_axis_tvalid=1`) but S2MM
deasserts `tready`.

The v12 board test used the direct RX ring image, 64 RX buffers, 63 posted
descriptors, 100 MHz MBV, LMB code/data, DMA BRAM packet buffers, and a quiet
1472-byte UDP sink. Timing for this diagnostic bitstream is not signoff-clean:
WNS was -0.091 ns and TNS was -0.171 ns on 4 endpoints, so treat the numbers
as diagnostic rather than final characterization.

At idle/broadcast traffic the new counter was zero:

```text
gate_drain_samples                  20
gate_drain_cycles_total           2044
gate_drain_cycles_max              285
gate_drain_tready_low_cycles         0
```

At requested 40 Mbit/s for 5 seconds, the host sent 16984 packets and the
sink received 13959 packets / 20,547,648 bytes. The discriminator result was:

```text
gate_drain_samples              13,989
gate_drain_cycles_total    374,585,182
gate_drain_cycles_max           35,878
gate_drain_200_500us            10,687
gate_drain_tready_low_cycles 353,433,523
gate_drain_tready_low_cycles_max 34,363
gate_drain_tready_low_samples 353,433,523
mac_rx_err_overflow              1,538
gate_dropped_overflow_frames     1,350
gate_dropped_bad_frames            325
```

So about 94% of the high-rate gate drain time is downstream DMA backpressure,
not just fill/drain accounting inside the single-slot gate. This changes the
next fix slightly: a multi-slot gate is still the right next RTL change because
it gives the MAC side enough elasticity to ride through DMA between-BD stalls,
but a strict 2-slot ping-pong is likely marginal. Build a 4-slot
store-and-forward gate first, then rerun 40/50 Mbit/s. If overflow remains
with four slots, the next target is S2MM service cadence/memory arbitration,
not more single-frame gate tuning.

## DMA Stream Width Experiment

The v12 `tready` discriminator made the next speed lever sharper. At requested
40 Mbit/s, about 94% of the gate drain window was spent with AXI DMA S2MM
deasserting stream `tready`. The Vivado shell audit found that the DMA memory
side was already 32-bit with 16-beat bursts, but the S2MM AXI-stream input was
still configured as an 8-bit stream:

```text
CONFIG.c_m_axi_s2mm_data_width 32
CONFIG.c_s_axis_s2mm_tdata_width 8
CONFIG.c_s2mm_burst_size 16
CONFIG.c_include_s2mm_dre 0
```

That is a poor shape for a BRAM-backed packet path: a 1472-byte UDP packet
arrives at the DMA as roughly 1514 byte beats instead of roughly 379 32-bit
beats, and the measured drain time shows the DMA is not absorbing those byte
beats continuously at the expected 100 MHz stream rate.

The next hardware experiment widens only the DMA-facing receive stream. The
MAC and `axis_frame_error_drop` remain byte-native, then a new
`axis_pack8_to_32` stage packs good frames into 32-bit little-endian AXI-stream
beats with `TKEEP` on the final partial word. The Vivado AXI DMA S2MM stream
configuration is changed to 32-bit and the wrapper connects the full
`M_AXIS`/`S_AXIS_S2MM` interface instead of individual loose pins.

Focused pre-build checks passed:

```text
AXIS-PACK8-TO-32: ALL TESTS PASSED
AXIS-FRAME-ERROR-DROP: ALL TESTS PASSED
Vivado block-design validation: passed with S_AXIS_S2MM connected
```

Expected result: if the byte-wide stream was the dominant source of S2MM
backpressure, `gate_drain_tready_low_cycles` and average gate drain time should
drop materially at 40 Mbit/s, giving a larger speed boost than adding more
single-slot gate elasticity. If the counter remains high, the next bottleneck
is below the stream width boundary: AXI DMA M_AXI write utilization, AXI BRAM
controller acceptance, or interconnect arbitration.

The diagnostic bitstream built and programmed, but timing did not close:

```text
WNS -0.317 ns, TNS -21.802 ns, 274 failing endpoints
```

The 40 Mbit/s board test used the same direct RX ring Zephyr image, 64 RX
buffers, 63 posted RX descriptors, LMB code/data, DMA BRAM packet buffers, and
a quiet 1472-byte UDP sink. The host sent 16984 packets in 5 seconds and the
sink received 13917 packets / 20,485,824 bytes. The measured drain wall did
not materially improve:

```text
gate_drain_samples              13,926 delta
gate_drain_cycles_total    359,798,012 delta
gate_drain_cycles_max           36,177
gate_drain_tready_low_cycles 338,712,312 delta
mac_rx_err_overflow              1,457
gate_dropped_overflow_frames     1,291
gate_dropped_bad_frames            484
```

That is still about 94% `tready`-low during drain, so the byte-wide S2MM stream
was not the considerable-speed lever. The packer is functionally valid, but it
does not move this wall. The next measurement should move one level lower:
instrument or expose AXI DMA `M_AXI_S2MM` write-channel utilization
(`awvalid/awready`, `wvalid/wready`, burst lengths, and write-response stalls)
and the AXI BRAM controller acceptance rate. If `WVALID && WREADY` utilization
is low while the RX gate is blocked, the bottleneck is inside AXI DMA's
internal stream-to-memory service. If `WVALID` is high but `WREADY` is low,
the bottleneck is the BRAM controller/interconnect path.

One warning from this diagnostic image: the post-run direct-ring accounting
showed `rx_bd_available_current=0xffffffff` and many `rx_bd_errors` without
S2MM hard error bits (`DMASR=0x00010008`). Treat this bitstream as a diagnostic
only until timing is fixed and the direct-ring BD accounting is rechecked.

This experiment was reverted from the hardware build path before the dual-port
BRAM test. The next trusted bitstream returns to the byte-wide S2MM stream and
changes only the DMA-visible memory service path.

## Dual-Port DMA BRAM Experiment

The DMA-visible packet/descripor BRAM already used a true-dual-port block RAM
primitive, but the AXI BRAM controller was configured as single-port:

```text
CONFIG.SINGLE_PORT_BRAM 1
bram_ctrl/BRAM_PORTA -> bram/BRAM_PORTA
```

That means CPU reads of RX packet buffers, AXI DMA S2MM packet writes, AXI DMA
SG descriptor reads/writebacks, and fcapz debug reads all shared the same
controller BRAM port. Since the current loss signature is S2MM `tready` low
while the DMA is trying to drain frames, this is now the highest-value
configuration fix.

The active hardware generator now enables the AXI BRAM controller's dual-port
BRAM mode and connects both physical memory ports:

```text
CONFIG.SINGLE_PORT_BRAM 0
bram_ctrl/BRAM_PORTA -> bram/BRAM_PORTA
bram_ctrl/BRAM_PORTB -> bram/BRAM_PORTB
```

This is not yet a hard split into separate CPU and DMA AXI slave ports; it is
the AXI BRAM controller using both BRAM ports internally. If that reduces
`gate_drain_tready_low_cycles` at 40/50 Mbit/s, then BRAM controller service
was a meaningful part of the wall. If it does not, the next step is explicit
M_AXI_S2MM write-channel utilization counters or a topology with independent
CPU/DMA BRAM controllers on separate block RAM ports.

The dual-port BRAM-controller bitstream did not close timing, but was still
tested to keep the performance signal moving. Vivado's managed
`write_bitstream` step crashed after route, so the routed checkpoint was opened
in a fresh batch session and `write_bitstream` completed successfully. The
recovered bitstream programmed on the Arty A7-100T and booted Zephyr: the
board answered ping, fcapz EJTAG-UART reported version `0x00044A55`, and the
stats block reported version 12 with a 100 MHz cycle counter.

At requested 20 Mbit/s for 5 seconds, WSL sent 8492 1472-byte UDP packets to
`192.168.137.200:5001`. The board sink received 8465 packets /
12,460,480 bytes:

```text
mac_rx_frames                  +8500
gate_good_frames               +8472
gate_dropped_bad_frames          +28
gate_dropped_overflow_frames      +0
mac_rx_err_overflow               +0
gate_drain_lt_50us             +8472
gate_drain_ge_500us               +0
gate_drain_tready_low_cycles      +0
dma_errors                        +0
rx_bd_errors                      +0
sink_packets                   +8465
```

So dual-port BRAM-controller access makes the 20 Mbit/s case clean. The
remaining loss at 20 Mbit/s is the gate's `terror` bad-frame drop path, not
S2MM backpressure.

At requested 40 Mbit/s for 5 seconds, WSL sent 16984 packets and the sink
received 14657 packets / 21,575,104 bytes:

```text
mac_rx_frames                   +15971
gate_good_frames                +14665
gate_dropped_bad_frames           +285
gate_dropped_overflow_frames     +1021
mac_rx_err_overflow              +1222
gate_drain_lt_50us               +1985
gate_drain_50_100us               +415
gate_drain_100_200us             +2074
gate_drain_200_500us            +10191
gate_drain_tready_low_cycles +331699921
dma_errors                          +0
rx_bd_errors                    +13938
sink_packets                    +14657
```

Conclusion: the dual-port BRAM controller is a real improvement, but not the
full high-rate fix. It eliminates the 20 Mbit/s S2MM backpressure wall, while
40 Mbit/s still spends most drain time with DMA not accepting stream data and
overflows the single-slot gate/MAC. The next performance work is still a
multi-slot frame gate plus M_AXI/S2MM service instrumentation.

Timing did not close for reasons outside the Ethernet RX data path. The final
routed summary was `WNS=-0.159 ns`, `TNS=-9.767 ns`, with 134 failing
`sys_clk` setup endpoints. `eth_rx_clk` and `eth_tx_clk` both meet timing. The
worst path starts in the AXI interrupt controller/IPIF dphase timer, crosses
AXI interconnect ready logic, and ends in the fcapz EJTAG-AXI response FIFO
reset/write logic. It is route-dominated and has 10 logic levels. Methodology
also reports many TIMING-17 critical warnings for fcapz EJTAG-AXI registers
whose clock pins are not reached by a timing clock. This points at fcapz/JTAG
debug constraints and the debug AXI master/interconnect cone, not the
emacZero RX datapath.

Update: adding a Xilinx AXI register slice between the fcapz EJTAG-AXI debug
master and the main AXI interconnect (`debug/M_AXI -> debug_axi_slice ->
axi_ic/S02_AXI`) closed the route-dominated debug AXI ready path. The normal
Vivado build completed with final routed timing clean: `WNS=0.054 ns`,
`TNS=0.000 ns`, and 0 failing setup/hold/pulse-width endpoints. Per-clock
setup WNS was `sys_clk=0.054 ns`, `eth_rx_clk=32.349 ns`, and
`eth_tx_clk=33.875 ns`. Bitgen completed successfully and regenerated the XSA.

## Four-Slot Gate Board Run

The next hardware image changed the RX error-drop gate from one store-and-
forward slot to four slots and kept the timing fix above. Because code/data now
live in LMB BRAM, the old post-bitstream fcapz AXI BRAM loader cannot update
the Zephyr image: fcapz's AXI master receives `AXI resp=3` when writing
`0x80000000`. For LMB code, the Zephyr ELF must be staged into the Vivado MBV
IP before bitgen. The build was therefore run as:

```text
python hardware/scripts/build_arty_a7_mbv.py --synth --jobs 1 \
  --elf build-wsl-zephyr-lmb-dma-silent-thr1-direct/zephyr/zephyr.elf
```

The routed build completed and bitgen integrated the ELF. The resulting board
image answered ping at `192.168.137.200` with 0/4 loss and 1-2 ms RTT. DMA
registers showed Zephyr had configured both channels:

```text
MM2S DMACR=0x01017003 DMASR=0x0001000a
S2MM DMACR=0x01017003 DMASR=0x00010008
```

One operational trap: sandboxed UDP traffic was blocked by the host firewall
rule `codex_sandbox_offline_block_outbound`. Ping and TCP probes still worked,
but sandboxed Python/iperf UDP did not increment the `Ethernet 3` TX counters.
All UDP performance points below were therefore run outside the sandbox.

With the 4-slot gate active, the previous gate/DMA backpressure wall is gone.
At both low-rate and 30 Mbit/s MTU-sized UDP, the gate reported:

```text
gate_dropped_overflow_frames   0
gate_drain_tready_low_cycles   0
gate_drain_ge_500us            0
gate_drain_cycles_max       3029 cycles
```

The new limiting fault is upstream bad-frame generation (`terror`). A 30 Mbit/s
MTU run sent 13,333 UDP datagrams from the host; the MAC saw the traffic, but
most frames were marked bad before the gate:

```text
rx_frames                    +13549
gate_good_frames               +538
gate_dropped_bad_frames      +13011
gate_dropped_overflow_frames     +0
gate_drain_tready_low_cycles     +0
```

A 5 Mbit/s MTU run showed the same shape:

```text
rx_frames                     +2426
gate_good_frames               +529
gate_dropped_bad_frames       +1897
gate_dropped_overflow_frames     +0
```

A 5 Mbit/s run with 100-byte UDP datagrams did not add bad-frame drops, so the
current Bug B signature is size/load dependent: long frames trigger emacZero RX
`terror`, while the downstream 4-slot gate and S2MM drain path have headroom.

Current conclusion: the 4-slot gate is doing its job. The performance wall has
moved from DMA/gate backpressure to upstream frame corruption inside the
emacZero RX path. The next high-value work is an ELA/simulation target around
the emacZero RX FIFO/CDC/width path, triggered on `terror=1`, with emphasis on
MTU frames and back-to-back receive conditions.

## MII RX FIFO Bug B Fix Candidate

RTL audit moved the Bug B suspect from the downstream AXI DMA path into
`mii_if.v`. The MII receive CDC path is store-and-forward: it writes a full
MII-received frame into an async FIFO, toggles frame availability at EOF, and
only then replays the frame into `eth_mac_rx` in the 100 MHz system clock
domain. The synthesis FIFO is byte-wide (`WRITE_DATA_WIDTH=10`: EOF, error,
and 8 data bits), so the previous depth of 2048 entries is 2048 bytes, not
1024 bytes. That should fit a standard MTU frame, but the implementation still
had a correctness hole: XPM FIFO `wr_en` was not gated by `full`, and the XPM
`overflow` output was ignored. Any full-write event could silently drop bytes;
`eth_mac_rx` would later see only an FCS mismatch and assert `terror`.

The active fix candidate makes this path defensive and observable:

```text
mii_if RX FIFO depth:       2048 -> 4096 byte entries
FIFO write enable:          rx_wr_en -> rx_wr_en && !rx_wr_full && !rst_busy
full-write handling:        latch into GMII-side RX error for the frame
new gate-page CSR counters:  mii_rx_fifo_full_frames
                             mii_rx_fifo_full_writes
                             mii_rx_fifo_overflow_pulses
                             mii_rx_fifo_wr_level_max
```

Fast checks completed before any long implementation build:

```text
Icarus syntax: mii_if       pass
Icarus syntax: eth_mac_sys  pass
Vivado BD generation        pass
```

The next board test should run the same ELF-staged Vivado build as the 4-slot
gate run, because LMB code cannot be patched after bitgen via fcapz AXI. Test
conditions to repeat:

```text
ping 192.168.137.200
iperf2 UDP, Ethernet 3, outside sandbox/firewall block:
  5 Mbit/s, 1472-byte UDP payload
  30 Mbit/s, 1472-byte UDP payload
  5 Mbit/s, 100-byte UDP payload
```

Expected result if this is the root cause: `gate_dropped_bad_frames` collapses
for MTU-sized UDP. If `mii_rx_fifo_full_*` increments, the counter confirms the
original overflow mechanism. If bad-frame drops remain while the new FIFO
counters stay zero and `mii_rx_fifo_wr_level_max` stays comfortably below 4096,
then the next target is not capacity/full handling but an RX byte-order,
CRC/FCS, or MII nibble assembly issue.

Board result: the FIFO-full mechanism was not the root cause. On the
ELF-staged bitstream, 5 Mbit/s MTU UDP still added 1900 bad-frame drops, while
all new FIFO full/overflow counters stayed at zero. The 100-byte UDP control
added no bad-frame drops. A falling-edge MII input sample experiment also did
not move the number.

The expanded size-bucket counters exposed the sharper clue: bad MTU frames were
classified as short fragments, while good MTU frames landed in the 1024-1518
bucket. So the MAC is not receiving full corrupted MTU frames; it is receiving
early-terminated fragments whose FCS naturally fails. A 1024-cycle post-EOF
delay did not fix the issue and shifted the fragments even shorter, so the
current candidate is the XPM FWFT handshake itself: the replay side now uses
the FIFO `data_valid` output as the condition for consuming `rx_rd_data`,
instead of treating `!empty` as equivalent to valid data. The post-EOF delay is
back to 8 cycles while this handshake fix is tested. The XPM feature bit for
`data_valid` is bit 12, so the RX FIFO uses `USE_ADV_FEATURES="1200"`: existing
prog-empty telemetry plus `data_valid`.

## AXI Fabric Split

The Vivado shell now separates the control and packet data planes instead of
using one 6-master/7-slave AXI interconnect for everything.

The new topology is two-level:

```text
MicroBlaze V M_AXI_IP/M_AXI_DP + fcapz debug
    -> ctrl_axi_ic
        -> UARTLite / timer / INTC / GPIO / emacZero CSR / AXI DMA CSR
        -> bridge master into dma_axi_ic for CPU/debug packet-BRAM access

AXI DMA M_AXI_SG + M_AXI_MM2S + M_AXI_S2MM
    -> dma_axi_ic
        -> AXI BRAM controller true-dual-port BRAM
```

This keeps the SGDMA descriptor/data ports on a full AXI4 fabric with the AXI
BRAM controller as the only normal target, while still preserving the necessary
CPU/debug path to packet buffers. The split should reduce control-plane
coupling and make timing/performance evidence easier to interpret: DMA masters
no longer arbitrate through the same fan-out fabric as UART/timer/interrupt/GPIO
CSR traffic, and any CPU packet-buffer access is explicit through the bridge
into the DMA BRAM fabric.

Fast validation result: the no-synthesis Vivado BD generation path completed
and `validate_bd_design` passed with this split fabric. Vivado assigned
`bram_ctrl/S_AXI/Mem0` into the MicroBlaze V data/instruction spaces, fcapz
debug space, and all three AXI DMA address spaces, confirming that the bridge
preserves software/debug access to packet BRAM while the SGDMA masters reach it
through `dma_axi_ic`.

Full routed build result: the split-fabric bitstream built successfully with
the direct-ring Zephyr ELF staged into MBV BRAM. Final timing was clean:

```text
WNS  0.022 ns
TNS  0.000 ns
WHS  0.025 ns
THS  0.000 ns
0 setup/hold/pulse-width failing endpoints
```

Routed utilization is now tight on block RAM:

```text
Slice LUTs       28,342 / 63,400  = 44.70%
Slice registers  42,725 / 126,800 = 33.69%
Block RAM tiles     135 / 135     = 100.00%
DSPs                  4 / 240     = 1.67%
```

Board bring-up after programming with XSDB:

```text
ping 192.168.137.200: 3/3 replies, 0% loss, 1-2 ms RTT
AXI DMA S2MM: running, SG enabled, CURDESC/TAILDESC in DMA BRAM window
PHY: link up
emacZero CSR/gate: readable over fcapz EJTAG-AXI
```

The BRAM-resident Zephyr perf page read back all zeros because this ELF was
built with `CONFIG_ETH_EMACZERO_PROFILE=n`; the emacZero hardware CSR counters
were used for the performance check instead.

Performance result: the split fabric is not currently the limiter. At requested
5/20/30/40/50 Mbit/s with 1472-byte UDP payloads, the 4-slot RX gate reported
zero overflow drops, zero S2MM `tready`-low cycles, and a max drain of only
3029 cycles. However, almost all UDP frames were rejected as bad frames before
the DMA path:

```text
5 Mbit/s, 1472-byte UDP, 5 s:
  host sent 2224 datagrams
  gate_good_frames +518
  gate_dropped_bad_frames +1905
  gate_dropped_overflow_frames +0

20 Mbit/s, 1472-byte UDP, 5 s:
  host sent 8894 datagrams
  gate_good_frames +521
  gate_dropped_bad_frames +8574
  gate_dropped_overflow_frames +0

30 Mbit/s, 1472-byte UDP, 5 s:
  host sent 13353 datagrams
  gate_good_frames +469
  gate_dropped_bad_frames +13084
  gate_dropped_overflow_frames +0
```

The bad frames are still classified mostly in the 128-255 byte bucket while
good MTU frames land in the 1024-1518 bucket. The MII FIFO full/overflow and
replay-gap counters stayed at zero. Current conclusion: the split AXI fabric
and 4-slot gate are healthy, but the active emacZero RX replay/FCS candidate
has not fixed Bug B and appears to make the bad-frame path fire even for the
100-byte high-packet-rate control. The next work should stay inside emacZero RX
frame replay/termination/FCS timing, not the AXI DMA or BRAM fabric.

## Frame Forensics Plan

The next debug step is to stop inferring where frames change shape and expose
the last completed frame at each RX boundary:

| Boundary | Added signal | Question answered |
| --- | --- | --- |
| PHY/MII ingress | `mii_rx_last_len`, `mii_rx_word0..3` | Did the PHY-facing MII capture see the expected frame length and header bytes? |
| MII FIFO replay to GMII | `mii_rx_replay_last_len`, `mii_rx_replay_word0..3`, `mii_rx_replay_eof_count` | Did store-and-forward replay shorten, shift, or corrupt the frame before the MAC? |
| MAC RX classifier | `mac_rx_last_len`, `mac_rx_last_flags`, `mac_rx_stat_count` | Did the MAC classify the same replayed frame as FCS/alignment/overflow/oversize error? |

These are CSR-readable on the emacZero debug aperture at `0x44a00160` through
`0x44a00198`, so the board test can compare the MII ingress length/header, the
GMII replay length/header, and the MAC classification after a single UDP sweep
without adding hot-path logging.

## Timing-Fixed Forensics Build

The frame-forensics build initially missed timing on the emacZero MAC RX path:
the captured destination-MAC compare drove the RX FIFO write-enable fanout in
the same 100 MHz cycle. The fix registers the RX FIFO push bundle
(`push_en/data/last/err/sof`) before the `sync_fifo` write port.

Full routed rebuild with the direct-ring Zephyr ELF staged into BRAM now meets
timing:

```text
WNS  0.141 ns
TNS  0.000 ns
WHS  0.011 ns
THS  0.000 ns
0 setup/hold/pulse-width failing endpoints
```

Board retest after programming the clean bitstream:

```text
ping 192.168.137.200: 3/3 replies, 0% loss, 1-2 ms RTT
AXI DMA S2MM: running, SG enabled, not halted
emacZero gate: 0 bad-frame drops, 0 overflow drops, 0 S2MM tready-low cycles
```

Large-frame ICMP also passes through the hardware path cleanly:

```text
ping -l 1472 -n 10 192.168.137.200:
  10/10 replies, 0% loss, 2 ms RTT
  rx_size_1024_1518 +10
  gate_dropped_bad_frames +0
  gate_dropped_overflow_frames +0
  mii_rx_fifo_overflow_pulses +0
```

The UDP performance sweep is not a valid throughput measurement on this run.
The Windows host reports thousands of UDP datagrams sent, but the emacZero MAC
counter sees only one short frame for the 100-byte case and zero frames for the
1472-byte case. A hand-written Python UDP sender bound to `192.168.137.1`
likewise leaves `rx_frames` unchanged, while ICMP immediately increments the
same counters. Current conclusion: the timing-fixed FPGA image is alive and
large-frame-clean, but the host UDP traffic-generation path is not currently
putting UDP frames onto Ethernet 3 toward the board. Resolve host-side UDP
delivery or capture before using UDP numbers as FPGA performance data.

Follow-up isolation found two separate effects:

```text
Sandboxed UDP:
  blocked by host policy; MAC counters do not increment.

Outside-sandbox UDP:
  reaches the MAC immediately.
```

The outside-sandbox Windows `iperf.exe` length sweep reproduces the bad-frame
path, but a Python zperf-compatible sender produces good MAC frames; its stats
request times out because the staged Zephyr image is the quiet UDP sink build
with `CONFIG_NET_ZPERF=n`, not a zperf server. The full emacZero simulation
suite still passes locally, including CRC32, MII store-forward, MII loopback,
MAC RX backpressure/byte0, and UDP iperf sink coverage.

Current interpretation: the previous "UDP sees zero frames" result was a
sandbox/test-environment problem. The remaining board-performance problem is
the already-open RX bad-frame path, currently reproduced most clearly with
outside-sandbox Windows `iperf.exe`; it should be debugged with a trusted
traffic source or host-side capture so host-tool artifacts are separated from
real emacZero `terror` events.

## 40 Mbit/s Cliff, Revisited

With the profile block read from the correct reserved DMA-memory address
(`0x8007b000` for the current `0x80040000 + 0x0003c000` DMA window), WSL
traffic gives a cleaner story than the earlier Windows `iperf.exe` runs:

```text
30 Mbit/s, 1472-byte UDP, 3 s:
  sink_packets +7629
  gate_dropped_bad_frames +23
  gate_dropped_overflow_frames +0
  gate_drain_tready_low_cycles +0

40 Mbit/s, 1472-byte UDP, 3 s:
  sink_packets +7669
  gate_dropped_bad_frames +134
  gate_dropped_overflow_frames +1196
  gate_drain_tready_low_cycles +270464597
```

The direct RX ring is not running out of descriptors in this run:
`rx_bd_available_min` stays at 1, refill never takes 1 ms, and dwell remains
below 1 ms. The failure is the DMA-facing stream stalling while the CPU is
also reading packet buffers from the AXI BRAM window.

The hardware shell previously used a true-dual-port BRAM primitive behind one
AXI BRAM controller. That is still one AXI slave path, so CPU/debug reads,
DMA S2MM writes, DMA MM2S reads, and DMA SG descriptor traffic all arbitrate
before reaching the BRAM. The next hardware change splits that into two AXI
BRAM controllers on the same true-dual-port RAM:

```text
CPU/debug AXI  -> bram_ctrl_cpu -> BRAM_PORTA
AXI DMA data/SG -> bram_ctrl_dma -> BRAM_PORTB
```

Both address spaces still map the packet memory at `0x80040000`, but DMA and
CPU accesses now enter the RAM through independent BRAM ports.

The dual-controller bitstream built and met timing:

```text
WNS  0.155 ns
TNS  0.000 ns
WHS  0.022 ns
THS  0.000 ns
```

Board sanity after programming was clean: 3/3 ICMP replies and live profile
counters. The isolated 40 Mbit/s WSL run improved but did not remove the wall:

```text
host sent packets                 10190
sink_packets                       8440  (~33.1 Mbit/s payload)
gate_dropped_bad_frames             157
gate_dropped_overflow_frames         799
gate_drain_200_500us               8024
gate_drain_tready_low_cycles  263229302
rx_bd_errors                       8032
rx_refill_cycles_ge_1ms               0
rx_dwell_ge_100ms                     0
```

So the single AXI BRAM controller was a contributor, not the root cause. The
remaining cliff is still the AXI DMA S2MM stream interface deasserting
`tready` for most MTU frames at 40 Mbit/s. Descriptor refill and Zephyr buffer
residency are not the limiting path in this run.

Next measurement: expose AXI DMA `M_AXI_S2MM` write-channel counters or ELA
probes (`AWVALID/AWREADY/AWLEN`, `WVALID/WREADY/WLAST`, `BVALID/BREADY`) so
we can separate "DMA is not issuing writes" from "the downstream BRAM path is
not accepting writes." Without that split, additional BRAM topology or stream
format changes are guesses.

## S2MM/SG Stall ELA Result

The S2MM payload write tap was added between `axi_dma/M_AXI_S2MM` and
`dma_axi_ic`, then a second tap was added on `axi_dma/M_AXI_SG`. The fcapz ELA
was repacked to 32 bits because wider samples either missed timing in the debug
readback path or produced unreliable high-half samples on the host.

Timing-clean instrumented builds:

```text
S2MM-only 32-bit ELA:
  WNS  0.108 ns
  TNS  0.000 ns

S2MM + SG 32-bit ELA:
  WNS  0.171 ns
  TNS  0.000 ns
```

The S2MM-only 40 Mbit/s capture showed the stall is not downstream BRAM
backpressure:

```text
dma_rx_axis_tvalid=1
dma_rx_axis_tready=0
s2mm_awvalid=0
s2mm_wvalid=0
s2mm_w_stall=0
```

The SG-visible capture narrowed it further. During the captured stall window,
the DMA stream input stayed stalled while both AXI masters were idle:

```text
dma_stall_samples              481
stall_no_s2mm_wvalid           481
s2mm_w_stall                     0
s2mm_write_active                0
sg_read_active                   0
sg_write_active                  0
```

Post-run AXI DMA registers were still healthy: S2MM `DMASR=0x00010008`
(`SGINCL`, not halted, no error bits), with `CURDESC/TAILDESC` in the packet
BRAM window. Software counters still show direct-ring RX is active and not
descriptor-starved: `rx_dma_config_calls=0`, `rx_dma_reload_calls=0`,
`rx_dma_start_calls=0`, `rx_bd_available_min=1`, and refill/dwell stay below
1 ms.

A Zephyr-only cleanup changed S2MM RX descriptors to program `control` with
the receive buffer length only, instead of also setting TX-style SOF/EOF bits.
That is the more conservative descriptor format, but it did not change the
40 Mbit/s cliff:

```text
gate_dropped_overflow_frames       ~809
gate_drain_200_500us              ~8038
gate_drain_tready_low_cycles  ~263.6M
sink_packets                      ~8437
```

Current conclusion: the remaining limiter is inside the Xilinx AXI DMA S2MM
stream front end, not the payload AXI write channel, SG descriptor bus, Zephyr
buffer residency, or descriptor refill. It accepts the start of a frame, then
internally deasserts `S_AXIS_S2MM_TREADY` for hundreds of microseconds while no
observable S2MM or SG AXI transaction is active.

Best next speed fix: add a deep AXI-stream elastic FIFO between the 4-slot
error-drop gate and AXI DMA S2MM. The FIFO should absorb the DMA's internal
`tready` gaps so the 4-slot frame gate can keep draining completed frames. If
that does not scale, the architectural replacement is a custom RX
stream-to-BRAM writer owned by the emacZero driver instead of AXI DMA S2MM.

The first elastic FIFO build used an 8192-byte byte-wide FIFO and failed
placement because the Arty A7-100T design was already at the BRAM36 limit:
the build required 136 RAMB36/FIFO sites and the part has 135. The next trial
uses a 4096-byte FIFO. That should fit by saving roughly one RAMB36 compared
with the 8192-byte build and is still large enough to test the observed
40 Mbit/s failure mode: a 500 us S2MM `tready` gap at 40 Mbit/s corresponds to
about 2500 bytes of incoming frame data.

The 4096-byte FIFO build fit and met timing (`WNS=0.110 ns`, `WHS=0.013 ns`,
`134/135` BRAM36/FIFO tiles). Initial board tests showed ping still works, but
the 30 Mbit/s WSL UDP control exposed a different pre-MAC loss point:

```text
WSL sender, 30 Mbit/s target, 1472-byte UDP, 3 s:
  sender packets              7643
  sink_packets                2101
  gate_dropped_overflow          0
  gate_drain_tready_low_cycles   0
  mii_rx_replay_eof_count     7791
  mac_rx_stat_count           2184
  mii_rx_replay_gap_frames    5639
```

That localizes the missing frames to the emacZero MII replay path before the
MAC stats/gate/DMA path. The likely synthesis-only bug is using XPM FIFO
`data_valid` as a continuous word-available signal in FWFT mode. The active
fix makes replay use `!rx_rd_empty && !rx_rd_rst_busy`, matching the
non-synthesis FIFO model and preventing `gmii_rx_dv` gaps within a replayed
frame.

The word-valid fix made the 30 Mbit/s control clean again:

```text
WSL sender, 30 Mbit/s target, 1472-byte UDP, 3 s:
  sender packets              7643
  sink_packets                7638
  mii_rx_replay_gap_frames       0
  gate_dropped_overflow          0
  gate_drain_tready_low_cycles   0
```

At 40 Mbit/s, replay gaps still returned before MAC/gate/DMA became the only
limiter. The active follow-up increases the post-EOF replay visibility delay
from 255 sysclk cycles (~2.55 us) to 4095 cycles (~41 us). This keeps replay
below the 100 Mbps MTU frame period while giving the async FIFO read side
enough time to expose the full completed frame and EOF marker under burst load.

The 4095-cycle replay delay build also met timing (`WNS=0.071 ns`) and reduced
the 40 Mbit/s pre-MAC replay problem from thousands of gaps to a small residual:

```text
WSL sender, 40 Mbit/s target, 1472-byte UDP, 3 s:
  sender packets                 10190
  sink_packets                    8435
  mii_rx_replay_gap_frames          23
  gate_dropped_bad_frames          241
  gate_dropped_overflow_frames     745
  gate_drain_200_500us            7801
  gate_drain_tready_low_cycles 256624438
```

Conclusion from this run: the replay path is no longer the main limiter. The
4 KB FIFO after the 4-slot gate fills and backpressures the gate because the
AXI DMA S2MM stream front end is still not accepting frames quickly enough on
average. This is not a small jitter tail that a modest BRAM FIFO can hide. The
next throughput step is architectural: either find and eliminate the AXI DMA
per-frame service gap, or replace S2MM RX with an emacZero-owned stream-to-BRAM
writer that writes packet bytes and completion metadata directly into the
driver-owned RX ring.

## S2MM Descriptor Snapshot Correction

The follow-up ELA capture added slow EJTAG-AXI snapshots of S2MM registers and
nearby descriptors while triggering on `S_AXIS_S2MM_TVALID &&
!S_AXIS_S2MM_TREADY` during the same 40 Mbit/s MTU test. The stream-side ELA
still showed a real stall with no payload or SG AXI activity:

```text
dma_stall_samples        449
stall_no_s2mm_wvalid     449
s2mm_w_stall               0
s2mm_write_active          0
sg_read_active             0
sg_write_active            0
```

The descriptor snapshots changed the interpretation. During and after the
stall, S2MM reported `DMASR=0x0001000a` or `0x00010008` (`SGINCL`,
`IRQTHRESHSTS=1`, sometimes `IDLE`) and the sampled `CURDESC`, next BD, and
`TAILDESC` all contained status `0x8c0005ea`. For S2MM receive descriptors
that decodes as complete + SOF + EOF + 1514 bytes, with no BD error bits.

That means the DMA is not obviously refusing a clean pending descriptor. In the
captured state it had reached descriptors that were already complete, so the
published hardware tail was not far enough ahead. The software counters match
that story better than the earlier "DMA internal service gap" theory:

```text
rx_irq_count              7943
rx_bd_hw_completed        7946
rx_bd_refilled            8009
rx_bd_tail_updates        7947
rx_poll_completed_max        2
rx_refill_no_free        15847
rx_bd_no_free            15846
rx_free_current              1
rx_dma_fifo_current         63
rx_owner_sum_current        64
```

The new working theory is ring service starvation, not intrinsic AXI DMA
slowness: S2MM reaches the published tail because the driver is not observing,
recycling, and republishing completed BDs quickly or reliably enough under the
40 Mbit/s packet cadence. One specific ISR hazard was found in the direct-ring
path: it polled completed BDs first and acknowledged DMASR afterward. At high
rate, that can clear a completion IRQ that arrived during the poll/refill
window, leaving S2MM parked at tail until another interrupt source fires.

The next Zephyr-only experiment is therefore:

1. Acknowledge the S2MM IRQ status before descriptor polling.
2. Disable S2MM delay interrupts for the direct-ring RX path.
3. Force immediate IOC threshold 1 for direct-ring RX.
4. Retest 30/40 Mbit/s and inspect whether `rx_poll_completed_max`,
   `rx_refill_no_free`, `gate_drain_tready_low_cycles`, and
   `gate_dropped_overflow_frames` move.

If this does not move the wall, the next code-side suspect is the completion
service model itself: drain more completed BDs from a high-priority poll loop
or replace interrupt-per-completion service with an explicit NAPI-style poller
that runs until the hardware ring has clean pending descriptors ahead of
`TAILDESC`.

The IRQ-ack experiment built cleanly with the rebuilt Zephyr ELF embedded:

```text
WNS  0.071 ns
TNS  0.000 ns
WHS  0.028 ns
THS  0.000 ns
BRAM 134 / 135 tiles
```

The source-configured S2MM direct-ring DMACR after boot was `0x00015003`:
running, IOC IRQ enabled, error IRQ enabled, IRQ threshold 1, and delay IRQ
disabled. The 30 Mbit/s MTU control stayed clean:

```text
WSL sender, 30 Mbit/s target, 1472-byte UDP, 3 s:
  sender packets                 7643
  sink_packets                   7638
  gate_dropped_overflow_frames      0
  gate_drain_tready_low_cycles      0
  rx_bd_errors                      0
```

The 40 Mbit/s wall did not move:

```text
WSL sender, 40 Mbit/s target, 1472-byte UDP, 3 s:
  sender packets                    10190
  sink packet delta                  8117
  gate_dropped_overflow delta         978
  gate_drain_tready_low delta  266874660
  rx_poll_completed_max                 2
```

A live S2MM-only threshold-32/no-delay test (`DMACR=0x00205003`) confirmed
that batching completion interrupts works (`rx_poll_completed_max=32`), but
also did not remove the wall:

```text
WSL sender, 40 Mbit/s target, 1472-byte UDP, 3 s:
  sender packets                    10190
  sink packet delta                  8255
  gate_dropped_overflow delta         893
  gate_drain_tready_low delta  268842379
  rx_poll_completed_max                32
```

Conclusion: late IRQ acknowledgement and per-packet interrupt rate are not the
primary limiter. The consistent signature is that the driver keeps only one
free RX buffer (`rx_free_current=1`) while 63 buffers remain DMA-posted, and
the DMA/gate still runs out of accepted stream progress at 40 Mbit/s. The next
useful experiment should either (a) stop posting the entire pool so software
keeps a real free reserve for immediate reposts, or (b) add explicit hardware
visibility into how many posted BDs are pending vs complete ahead of CURDESC.
If neither path changes the wall, the custom RX stream-to-BRAM writer becomes
the clean architectural fix.

The post-count-48 experiment moved the idle pool accounting exactly as intended
but did not move throughput. With the clean build, baseline counters showed
`rx_bd_available_current=16`, `rx_free_current=16`, `rx_dma_fifo_current=48`,
and no refill no-free events. The 30 Mbit/s control remained clean:

```text
WSL sender, 30 Mbit/s target, 1472-byte UDP, 3 s:
  sender packets                 7643
  sink_packets                   7628
  gate_dropped_overflow_frames      0
  gate_drain_tready_low_cycles      0
```

The 40 Mbit/s wall still reproduced:

```text
WSL sender, 40 Mbit/s target, 1472-byte UDP, 3 s:
  sender packets                    10190
  sink packet delta                  8115
  gate_dropped_overflow delta         962
  gate_drain_tready_low delta  267030105
  rx_bd_available_current             16
  rx_refill_no_free delta          ~16084
```

An ELA + descriptor snapshot on the post-count-48 image captured the same
stall state:

```text
dma_stall_samples        449
stall_no_s2mm_wvalid     449
s2mm_write_active          0
sg_read_active             0
sg_write_active            0
DMACR                 0x00015003
DMASR                 0x0001000a  (IDLE, SGINCL, IRQTHRESHSTS=1)
CUR/NEXT/TAIL status  0x8c0005ea  (complete + SOF + EOF + 1514 bytes)
```

That rules out the "not enough free reserve" variant of the refill theory.
The DMA is still reaching a completed published tail and going idle while
traffic is waiting at its stream input. At this point the bounded options are:

1. Change the RX service model so completed descriptors are consumed and
   republished independently of the Zephyr packet path, with a high-priority
   NAPI-style poller that runs whenever S2MM is idle or an IRQ fires.
2. Replace AXI DMA S2MM RX with a small emacZero-owned stream-to-BRAM writer
   and completion ring. This removes the opaque AXI DMA tail/idle behavior
   from the hot path entirely.

The second option is now the more direct performance path. It also gives exact
frame ownership semantics: the hardware writer owns packet buffers until it
pushes a completion entry, and the driver returns buffers explicitly after
Zephyr releases them.

## fcapz Dynamic LMB Loader

The LMB split no longer requires embedding every Zephyr ELF into the Vivado
bitstream. The hardware shell now adds a reset-time loader path:

```text
fcapz USER3 EJTAG-AXI -> ctrl_axi_ic -> lmb_loader_ctrl
                                     -> lmb_bram_mux loader side
USER1 EIO debug_reset_req -----------> lmb_bram_mux select_loader

normal run:
  dlmb_cntlr -> lmb_bram_mux CPU side -> lmb_bram/BRAM_PORTB

reset/load:
  lmb_loader_ctrl -> lmb_bram_mux loader side -> lmb_bram/BRAM_PORTB
```

The invariant is simple: fcapz asserts USER1 EIO to hold MBV reset before
writing `0x80000000`; while that reset bit is high, the mux grants the loader
AXI BRAM controller access to LMB BRAM port B. When reset is released, DLMB
owns the port again. The shared DMA BRAM path at `0x80040000` is unchanged and
remains directly reachable through `bram_ctrl_cpu`.

Board proof on May 21, 2026:

```text
Programmed xc7a100t_0 with no-ELF bitstream:
  build/vivado/arty_a7_100t_mbv/arty_a7_100t_mbv_wrapper.bit

fcapz AXI smoke, MBV held in reset:
  0x80000000 readback 0x46434150 0x4C4D4230 0x12345678 0xA5A55A5A
  0x80040000 readback 0x46434150 0x444D4130 0x87654321 0x5A5AA5A5

Dynamic Zephyr reload:
  loaded 75684 bytes to 0x80000000 with --chunk-words 16
  verified first 16 words
```

Timing/resource result for this no-ELF loader bitstream:

```text
100 MHz system clock
Timing met
  setup slack 0.062 ns
  hold slack  0.017 ns
Utilization
  LUTs 29350 / 63400
  registers 43892 / 126800
  BRAM tiles 134 / 135
  DSPs 4 / 240
```

This changes the Zephyr debug loop materially: keep the hardware bitstream
fixed while iterating on Zephyr, then use `no_commit/load_zephyr_bram.py` to
patch the LMB image dynamically over fcapz instead of using `--elf` and
rebuilding the FPGA image.

## RX Ring Accounting Fix and New Ceiling

Follow-up board testing on May 21, 2026 supersedes the earlier conclusion that
AXI DMA S2MM itself must be replaced immediately. The post-count-64 experiment
made the real software bug visible: `rx_bd_available_current` wrapped to
`0xffffffff`, which means the direct RX ring's posted-descriptor accounting
was being incremented and decremented from multiple contexts without a single
ownership lock.

The direct-ring driver now serializes the RX BD ring state with
`rx_direct_lock`. The protected state is:

```text
rx_bd_refill_index
rx_bd_consume_index
rx_bd_tail_index
rx_bd_posted
rx_bd_buffer[]
rx_dma_inflight
S2MM TAILDESC publication
```

The practical result is that the impossible underflow is gone. With
`CONFIG_ETH_EMACZERO_RX_DMA_POST_COUNT=48`, a 30 Mbit/s WSL UDP run with
1472-byte UDP payloads delivered 7635 of 7643 sent packets to the sink with:

```text
gate_dropped_overflow_frames delta 0
gate_drain_tready_low_cycles delta 0
rx_bd_available_current      16
rx_free_current              16
rx_dma_fifo_current          48
rx_owner_sum_current         64
rx_bd_errors delta           0
rx_refill_no_free delta      0
```

The same image still hit the 40 Mbit/s wall. The ring no longer corrupts
itself, but the 16-buffer free reserve is transiently exhausted before the RX
worker returns buffers:

```text
40 Mbit/s requested, 1472-byte UDP payloads
sent packets                   10190
sink_packets delta              8440
gate_dropped_overflow_frames     798
gate_drain_tready_low_cycles 265263715
rx_bd_available_current           16
rx_free_current                   16
rx_dma_fifo_current               48
rx_refill_no_free delta        16732
```

Lowering the posted count to 32 gave a larger free reserve but did not move the
wall materially. Increasing the RX pool to 128 buffers with 64 posted BDs gave
a small improvement, and then raising the emacZero RX worker priority from `0`
to `-1` gave the first real step-change. With the same hardware bitstream and
only a dynamic Zephyr reload:

```text
CONFIG_ETH_EMACZERO_RX_BUFFER_COUNT=128
CONFIG_ETH_EMACZERO_RX_DMA_POST_COUNT=64
EMZ_RX_THREAD_PRIORITY=-1

40 Mbit/s requested, 1472-byte UDP payloads
sent packets                   10190
mac_rx_frames delta            10194
gate_good_frames delta         10126
gate_dropped_bad_frames delta     68
gate_dropped_overflow_frames       0
gate_drain_tready_low_cycles       0
rx_bd_errors delta                 0
rx_pre_udp_port_5001 delta     10123
sink_packets delta              9249
sink_bytes delta            13614528
```

This means the hardware RX path, 4-slot gate, AXI DMA S2MM, and direct-ring
refill path now survive the 40 Mbit/s run without overflow or DMA errors. The
remaining loss moved above the driver: the pre-stack UDP classifier sees about
10123 port-5001 frames while the socket sink receives about 9249.

A 50 Mbit/s requested run kept the hardware path clean as well, but did not
increase sink throughput:

```text
50 Mbit/s requested, 1472-byte UDP payloads
sent packets                   12738
gate_good_frames delta         12644
gate_dropped_overflow_frames       0
gate_drain_tready_low_cycles       0
rx_bd_errors delta                 0
rx_pre_udp_port_5001 delta     12641
sink_packets delta              8875
```

The first follow-up instrumentation pass corrected the location of that loss.
With version-13 counters, the UDP socket sink received every packet that Zephyr
accepted from the driver:

```text
40 Mbit/s requested, 1472-byte UDP payloads
sender actual payload rate        31.992 Mbit/s
rx_pre_udp_port_5001 delta        13490
rx_alloc_pkt_fail delta            1240
rx_zero_copy_submit delta          7925
rx_copy_submit delta               4328
net_udp_recv delta                12250
sink_packets delta                12250
sink payload rate                ~27.9 Mbit/s
```

The arithmetic is exact enough to name the limiter:

```text
rx_pre_udp_port_5001 - sink_packets = 1240
rx_alloc_pkt_fail                   = 1240
net_udp_recv                        = sink_packets
```

So the live wall is not the socket queue. It is the driver-to-Zephyr packet
allocation path before `net_recv_data()`. Once a packet is submitted to Zephyr,
the UDP sink consumes it.

Raising `CONFIG_NET_PKT_RX_COUNT` from 96 to 192 did not move the ceiling; the
run still lost about 1300 packets in `rx_alloc_pkt_fail`. Raising the zero-copy
stack-owned limit from 56 to 96 made throughput worse because it starved the
DMA-side BRAM pool. A variable-size Zephyr net buffer pool also failed as a
candidate image: the app heartbeat stayed alive, but the emacZero driver did
not initialize (`rx_pool_size=0`), so it is not a valid performance result.

The next measurement therefore splits `rx_alloc_pkt_fail` into:

```text
rx_alloc_pkt_zc_fail     zero-copy net_pkt allocation failure
rx_alloc_pkt_copy_fail   copy-fallback net_pkt+data allocation failure
rx_copy_write_fail       copy-fallback packet write failure
```

Current hypothesis: most failures are in the MTU-sized copy-fallback allocation.
The fallback path has to allocate a normal Zephyr packet while the zero-copy cap
is active; with 256-byte fixed net_buf data blocks, one MTU packet consumes
multiple fragments. If the split counters confirm that, the next real speed
move is to replace the fallback allocator shape, not to tune the socket sink.

The version-14 split counters confirmed the allocation shape:

```text
40 Mbit/s requested, 1472-byte UDP payloads
sender actual payload rate        31.883 Mbit/s
mac_rx_frames delta               12599
gate_good_frames delta            12461
gate_dropped_bad_frames delta       138
gate_dropped_overflow_frames          0
gate_drain_tready_low_cycles          0
rx_bd_hw_completed delta          12461
rx_bd_errors delta                    0
rx_alloc_pkt_fail delta            1129
rx_alloc_pkt_zc_fail delta            0
rx_alloc_pkt_copy_fail delta       1129
rx_copy_write_fail delta              0
rx_zero_copy_submit delta          7345
rx_copy_submit delta               3987
net_udp_recv delta                11331
sink_packets delta                11331
sink payload rate                25.755 Mbit/s
```

So submitted packets are not being lost by the socket path in this test:
`net_udp_recv == sink_packets`. All allocation failures are in the copy
fallback packet allocation path, not in zero-copy `net_pkt` allocation and not
in packet writes after allocation.

However, the same run also exposed a residual hardware correctness bug:
`gate_dropped_bad_frames` still increments on MTU traffic while the gate and DMA
path have zero overflow/backpressure. Direct emacZero CSRs showed the MII
capture/replay path was corrupting frames before the MAC FCS check:

```text
mii_rx_last_len          296
mii_rx_replay_last_len   592
mii_rx_replay_word*      duplicated byte-pair pattern
```

That means the next speed step is not another Zephyr socket change yet. First
fix the emacZero MII RX replay corruption so the hardware delivers a clean MTU
stream. The active RTL fix stores each complete MII frame into a small
sysclk-side BRAM and replays it continuously to the GMII-facing MAC. This avoids
using an async FIFO output word as both CDC storage and the continuous GMII
replay source. The first implementation accidentally inferred that frame store
as flip-flops and failed placement; it has been changed to an explicit 4096x9
synchronous BRAM with combinational read controls. The emacZero simulation
suite passes with this version.

Board validation of that RTL fix is clean for the hardware path. The bitstream
routes with positive timing (`WNS=0.083 ns`, `TNS=0`, `WHS=0.018 ns`) and uses
all 135 RAMB36 tiles. With the rebuilt Zephyr image dynamically loaded into LMB
BRAM, MTU UDP no longer trips the frame-corruption path:

```text
40 Mbit/s requested, 1472-byte UDP payloads
sender actual payload rate        31.992 Mbit/s
mac_rx_frames delta               13591
gate_good_frames delta            13591
gate_dropped_bad_frames delta         0
gate_dropped_overflow_frames          0
gate_drain_tready_low_cycles          0
rx_bd_hw_completed delta          13591
rx_bd_errors delta                    0
rx_alloc_pkt_fail delta            1354
rx_alloc_pkt_zc_fail delta            0
rx_alloc_pkt_copy_fail delta       1354
rx_zero_copy_submit delta          7906
rx_copy_submit delta               4331
rx_refill_no_free delta            9130
rx_pre_udp_port_5001 delta        13588
net_udp_recv delta                12234
sink_packets delta                12234
sink payload rate                27.936 Mbit/s
```

A higher requested rate keeps the hardware path clean but exposes the same
software allocation ceiling harder:

```text
50 Mbit/s requested, 1472-byte UDP payloads
sender actual payload rate        39.990 Mbit/s
mac_rx_frames delta               16989
gate_good_frames delta            16989
gate_dropped_bad_frames delta         0
gate_dropped_overflow_frames          0
gate_drain_tready_low_cycles          0
rx_bd_errors delta                    0
rx_alloc_pkt_fail delta            5257
rx_alloc_pkt_zc_fail delta            0
rx_alloc_pkt_copy_fail delta       5257
rx_zero_copy_submit delta          7513
rx_copy_submit delta               4219
rx_refill_no_free delta           22701
rx_pre_udp_port_5001 delta        16985
net_udp_recv delta                11728
sink_packets delta                11728
sink payload rate                26.730 Mbit/s
```

Current conclusion: the MAC/MII replay, 4-slot error-drop gate, AXI DMA S2MM,
and direct RX ring now accept the tested MTU stream cleanly through a
40 Mbit/s actual sender rate. The live performance wall is the software
fallback allocation policy: once the zero-copy stack-owned cap is reached, each
MTU fallback packet needs a normal Zephyr packet allocation backed by multiple
256-byte fragments. Those copy-fallback allocations fail under burst pressure,
and every submitted UDP packet still reaches the sink.

Next considerable speed move: replace the copy fallback with a dedicated
MTU-sized external fallback buffer pool, or otherwise make the fallback path
consume one packet-sized object instead of many small Zephyr net_buf fragments.

The first packet-sized fallback pool landed as a Zephyr-only change and was
tested by dynamically loading `zephyr.bin`; the FPGA bitstream was not rebuilt.
The driver now allocates copy-fallback packets with `net_pkt_rx_alloc_on_iface()`
and attaches one driver-owned external net_buf whose payload storage is
MTU-sized. This removes the old multi-fragment `net_pkt_write()` failure mode,
but it does not remove the full socket-stack residency wall.

Best measured configuration in this pass:

```text
CONFIG_ETH_EMACZERO_RX_COPY_FALLBACK_COUNT=80
CONFIG_ETH_EMACZERO_RX_MAX_STACK_OWNED_ZEROCOPY=56
CONFIG_NET_PKT_RX_COUNT=160
CONFIG_NET_BUF_RX_COUNT=32
CONFIG_NET_BUF_TX_COUNT=32
CONFIG_HEAP_MEM_POOL_SIZE=4096
UDP sink priority -2
RAM used by Zephyr image: 255120 B / 256 KiB
```

40 Mbit/s requested, 1472-byte UDP payloads:

```text
sender actual payload rate        31.992 Mbit/s
mac_rx_frames delta               13592
gate_good_frames delta            13592
gate_dropped_bad_frames delta         0
gate_dropped_overflow_frames          0
gate_drain_tready_low_cycles          0
rx_bd_hw_completed delta          13592
rx_bd_errors delta                    0
rx_alloc_pkt_fail delta               0
rx_alloc_frag_fail delta            865
rx_alloc_pkt_zc_fail delta            0
rx_alloc_pkt_copy_fail delta          0
rx_zero_copy_submit delta          5451
rx_copy_submit delta               7276
rx_pre_udp_port_5001 delta        13588
net_udp_recv delta                12723
sink_packets delta                12723
sink payload rate                29.038 Mbit/s
```

50 Mbit/s requested, 1472-byte UDP payloads:

```text
sender actual payload rate        39.990 Mbit/s
mac_rx_frames delta               16989
gate_good_frames delta            16987
gate_dropped_bad_frames delta         0
gate_dropped_overflow_frames          2
gate_drain_tready_low_cycles          0
rx_bd_hw_completed delta          16987
rx_bd_errors delta                    0
rx_alloc_pkt_fail delta               0
rx_alloc_frag_fail delta           4747
rx_alloc_pkt_zc_fail delta            0
rx_alloc_pkt_copy_fail delta          0
rx_zero_copy_submit delta          5120
rx_copy_submit delta               7120
rx_pre_udp_port_5001 delta        16980
net_udp_recv delta                12233
sink_packets delta                12233
sink payload rate                27.851 Mbit/s
```

Interpretation: the packet-object failure was fixed, and fallback packets now
consume one packet-sized external fragment rather than about six 256-byte
Zephyr fragments. The remaining loss is still before `net_recv_data()`, now as
exhaustion of the dedicated packet-sized fallback fragments. A soft cap that
retried exhausted fallback packets as zero-copy was tested and rejected: it
raised `rx_max_stack_owned` to 79, reintroduced packet-object failures, and did
not improve throughput. The next wall is not hardware and not Zephyr dropping
submitted UDP packets; it is that a 256 KiB LMB-only system cannot keep enough
driver and Zephyr socket-resident packet storage live to absorb this burst rate
through the socket path.

The likely next architectural speed step is to reduce or bypass socket-path
packet residency: either a raw/perf receive path for the target workload, a
larger local memory budget, or a Zephyr net stack change that drains UDP packets
with less per-packet residency. More fallback slots would help linearly, but the
current LMB image is already 97.3% full.
