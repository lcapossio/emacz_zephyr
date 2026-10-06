#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

"""Halt the AXI DMA S2MM channel on a running board and check the driver recovers.

Over JTAG-AXI, zero the length (CONTROL word) of the RX descriptor at S2MM's
TAILDESC, the last one the driver handed to the engine. The SG engine cannot
have fetched it yet, so once traffic has walked S2MM up to it, the engine
raises DMAIntErr and halts, the fault a corrupt descriptor would cause. The
driver counts the halt in the Ethernet rx_dma_failed statistic, resets the
DMA and rebuilds both rings, all within a few milliseconds, so DMASR shows
nothing afterwards. The test checks that exactly one RX DMA failure was
counted, that S2MM runs without error, and that RX accounting is exact and TX
works again.

Only one descriptor is touched, in one write: zeroing several would race
the recovery, which rebuilds the ring and posts fresh descriptors in the
slots still to be written.
"""

from __future__ import annotations

import argparse
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

from read_perf_stats import read_stats

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(ROOT / "fcapz" / "host"))

from fcapz.ejtagaxi import EjtagAxiController  # noqa: E402
from fcapz.transport import XilinxHwServerTransport  # noqa: E402

# Xilinx AXI DMA scatter-gather descriptor fields
DESC_CONTROL = 0x18
DESC_STATUS = 0x1C
DESC_STATUS_CMPLT = 1 << 31
# S2MM registers, relative to the AXI DMA base
S2MM_DMASR = 0x34
S2MM_TAILDESC = 0x40
DMASR_HALTED = 1 << 0
DMASR_ERRORS = 0x770  # DMAIntErr, DMASlvErr, DMADecErr, SGIntErr, SGSlvErr, SGDecErr


def retry_jtag(open_session):
    """Run open_session(), once more if xsdb lost the target list."""
    # xsdb sometimes reports "target list is empty" when a JTAG session
    # opens right after the previous one closed; one retry after a pause
    # gets through.
    try:
        return open_session()
    except RuntimeError as exc:
        if "target list is empty" not in str(exc):
            raise
        time.sleep(2.0)
        return open_session()


def jtag(args: argparse.Namespace) -> EjtagAxiController:
    def connect() -> EjtagAxiController:
        transport = XilinxHwServerTransport(fpga_name=args.tap)
        axi = EjtagAxiController(transport, chain=args.chain)
        try:
            axi.connect()
        except Exception:
            transport.close()
            raise
        return axi

    return retry_jtag(connect)


def inject(args: argparse.Namespace) -> int | None:
    """Zero the CONTROL word of S2MM's tail descriptor; return its address."""
    axi = jtag(args)
    try:
        desc = axi.axi_read(args.dma_base + S2MM_TAILDESC)
        control = axi.axi_read(desc + DESC_CONTROL)
        status = axi.axi_read(desc + DESC_STATUS)
        if control == 0 or status & DESC_STATUS_CMPLT:
            return None
        axi.axi_write(desc + DESC_CONTROL, 0)
        return desc
    finally:
        axi.close()


def s2mm_status(args: argparse.Namespace) -> int:
    axi = jtag(args)
    try:
        return axi.axi_read(args.dma_base + S2MM_DMASR)
    finally:
        axi.close()


def control(args: argparse.Namespace, command: str) -> str | None:
    """Send one control command; None if no reply came back in time."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((args.bind, 0))
        sock.settimeout(args.timeout)
        sock.sendto(command.encode("ascii"), (args.board, args.control_port))
        try:
            data, _addr = sock.recvfrom(2048)
        except socket.timeout:
            return None
    return data.decode("ascii", errors="replace").strip()


def send_udp(args: argparse.Namespace, duration: float) -> int:
    """Send sink traffic and return the data-packet count (the FIN is extra)."""
    out = subprocess.run(
        [sys.executable, str(SCRIPTS / "zperf_udp_client.py"), args.board,
         "--bind", args.bind, "--port", "5001", "--duration", str(duration),
         "--rate-mbps", str(args.rate_mbps), "--packet-size", "1472",
         "--fin-retries", "1", "--timeout", "0.5"],
        capture_output=True, text=True, check=False,
    ).stdout
    match = re.search(r"sent packets=(\d+)", out)
    if match is None:
        raise RuntimeError(f"zperf_udp_client produced no count:\n{out}")
    return int(match.group(1))


def stats(args: argparse.Namespace):
    return retry_jtag(lambda: read_stats(args.addr, args.tap, args.chain))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--addr", type=lambda s: int(s, 0), default=0x9FFFF000,
                        help="perf-stats block")
    parser.add_argument("--dma-base", type=lambda s: int(s, 0), default=0x41E00000)
    parser.add_argument("--tap", default="xc7a100t")
    parser.add_argument("--chain", type=int, default=3,
                        help="JTAG-AXI chain (3=mbv shell, 4=vex shell)")
    parser.add_argument("--board", default="192.168.237.200")
    parser.add_argument("--bind", default="192.168.237.1")
    parser.add_argument("--control-port", type=int, default=5002)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--rate-mbps", type=float, default=5.0,
                        help="sink rate; below the socket path's ceiling, so that "
                             "exact delivery after recovery is a fair check")
    args = parser.parse_args()

    before = stats(args)
    desc = inject(args)
    if desc is None:
        print("result=FAIL (S2MM tail descriptor is not posted)")
        return 1
    print(f"zeroed_descriptor=0x{desc:08x}")

    # A second of traffic walks S2MM through the posted ring into the zeroed
    # descriptor. Frames that arrive while it is halted are lost by design.
    send_udp(args, 1.0)
    time.sleep(0.5)
    dmasr = s2mm_status(args)
    print(f"s2mm_dmasr_after_recovery=0x{dmasr:08x}")

    # A deaf board misses the host's ARP probes, and the host then drops the
    # first datagrams it sends while it re-resolves. One control round trip
    # settles ARP before the counted window.
    for _ in range(3):
        if control(args, "s") is not None:
            break
    faulted = stats(args)
    sent = send_udp(args, 2.0)
    time.sleep(0.2)
    after = stats(args)
    tx_reply = control(args, "s")

    rx_dma_failed = after.eth_rx_dma_failed - before.eth_rx_dma_failed
    tx_dma_failed = after.eth_tx_dma_failed - before.eth_tx_dma_failed
    print(f"rx_dma_failed+={rx_dma_failed} tx_dma_failed+={tx_dma_failed}")
    print(f"sink_packets_during_fault={faulted.sink_packets - before.sink_packets}")
    print(f"sent_after={sent} board_after={after.sink_packets - faulted.sink_packets}")
    post = ("mac_rx_frames", "gate_good_frames", "gate_dropped_bad_frames",
            "gate_dropped_overflow_frames", "eth_rx_errors", "net_udp_drop",
            "sink_recv_errors")
    print("post " + " ".join(
        f"{name}+={getattr(after, name) - getattr(faulted, name)}" for name in post))

    checks = {
        "one_rx_dma_failure": rx_dma_failed == 1 and tx_dma_failed == 0,
        "s2mm_running": not dmasr & (DMASR_HALTED | DMASR_ERRORS),
        # the zperf client's FIN datagram reaches the sink as well
        "rx_exact_after": after.sink_packets - faulted.sink_packets == sent + 1,
        "tx_after": tx_reply is not None,
    }
    for name, ok in checks.items():
        print(f"{name}={'ok' if ok else 'FAIL'}")
    passed = all(checks.values())
    print(f"result={'PASS' if passed else 'FAIL'}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
