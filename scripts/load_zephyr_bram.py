#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Load a flat binary into the Arty DDR window through fcapz EJTAG-AXI.

The CPU is held in reset while the image is written and verified, then
released. The two shells differ only in where that reset lives and which
BSCAN chain the JTAG-AXI bridge sits on; --shell picks both.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "fcapz" / "host"))

from fcapz.eio import EioController  # noqa: E402
from fcapz.ejtagaxi import EjtagAxiController  # noqa: E402
from fcapz.ejtaguart import EjtagUartController  # noqa: E402
from fcapz.transport import XilinxHwServerTransport  # noqa: E402

# The VexRiscv shell's JTAG-AXI bridge returns SLVERR on a 16-beat burst.
# 15 works on both shells, so it is the cap everywhere rather than a
# per-CPU special case.
MAX_BURST_WORDS = 15

# Per-shell defaults. MicroBlaze V's reset is an fcapz EIO output; VexRiscv's
# is an AXI GPIO on its own fabric (bit 0 high holds the CPU, and it powers
# up high), reached through the JTAG-AXI bridge. Vex's debug TAP sits ahead
# of the bridge in the BSCAN chain, hence chain 4.
SHELLS = {
    "mbv": {"chain": 3, "file": "build-mbv-emac/zephyr/zephyr.bin", "reset": "eio"},
    "vex": {"chain": 4, "file": "build-vex-emac/zephyr/zephyr.bin", "reset": "gpio"},
}
VEX_CPU_RESET_GPIO = 0x40020000


def words_from_file(path: Path) -> list[int]:
    raw = path.read_bytes()
    if len(raw) % 4:
        raw += b"\x00" * (4 - (len(raw) % 4))
    return [int.from_bytes(raw[i:i + 4], "little") for i in range(0, len(raw), 4)]


def verify_range(axi, addr: int, words: list[int], count: int, burst: int) -> int:
    """Read back `count` words and report the first mismatch. 0 on success."""
    for offset in range(0, count, burst):
        span = min(burst, count - offset)
        got = axi.burst_read(addr + offset * 4, span)
        for i, actual in enumerate(got):
            expected = words[offset + i]
            if actual != expected:
                print(
                    f"verify mismatch @ 0x{addr + (offset + i) * 4:08X}: "
                    f"expected 0x{expected:08X}, got 0x{actual:08X}",
                    file=sys.stderr,
                )
                return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--shell", choices=sorted(SHELLS), default="mbv",
                        help="CPU shell in the bitstream (default mbv)")
    parser.add_argument("--file", help="image to load (default: the shell's build dir)")
    parser.add_argument("--addr", type=lambda value: int(value, 0), default=0x90000000)
    parser.add_argument(
        "--chain", type=int, default=None,
        help="EJTAG-AXI BSCAN chain (default: 3 for mbv, 4 for vex)",
    )
    parser.add_argument(
        "--uart-chain", type=int, default=None,
        help="EJTAG-UART chain (default: --chain + 1, matching the shell layout)",
    )
    parser.add_argument(
        "--eio-chain", type=int, default=1,
        help="EIO reset-control chain, mbv only (default 1)",
    )
    parser.add_argument("--tap", default="xc7a100t")
    parser.add_argument(
        "--chunk-words", type=int, default=MAX_BURST_WORDS,
        help=f"words per AXI burst (clamped to {MAX_BURST_WORDS})",
    )
    parser.add_argument(
        "--verify-words", type=int, default=0,
        help="words to read back and compare; 0 (default) verifies the whole image",
    )
    parser.add_argument("--no-reset", action="store_true")
    parser.add_argument("--monitor", type=float, default=0.0)
    parser.add_argument("--send", default="")
    args = parser.parse_args()
    shell = SHELLS[args.shell]
    if args.chain is None:
        args.chain = shell["chain"]
    if args.file is None:
        args.file = shell["file"]

    burst = max(1, min(args.chunk_words, MAX_BURST_WORDS))
    if args.chunk_words > MAX_BURST_WORDS:
        print(
            f"--chunk-words {args.chunk_words} exceeds the {MAX_BURST_WORDS}-beat "
            "JTAG-AXI limit; clamping",
            file=sys.stderr,
        )
    uart_chain = args.uart_chain if args.uart_chain is not None else args.chain + 1

    image = Path(args.file)
    if not image.is_absolute():
        image = ROOT / image
    words = words_from_file(image)

    transport = XilinxHwServerTransport(fpga_name=args.tap)
    eio = None
    if not args.no_reset and shell["reset"] == "eio":
        eio = EioController(transport, chain=args.eio_chain, base_addr=0x8000)
        eio.connect()
        eio.write_outputs(1)
        print(f"held CPU reset through EIO chain {args.eio_chain}")

    axi = EjtagAxiController(transport, chain=args.chain)
    axi.connect()
    gpio_reset = not args.no_reset and shell["reset"] == "gpio"
    if gpio_reset:
        axi.axi_write(VEX_CPU_RESET_GPIO, 1)
        print(f"held CPU reset through AXI GPIO 0x{VEX_CPU_RESET_GPIO:08X}")

    try:
        for offset in range(0, len(words), burst):
            chunk = words[offset:offset + burst]
            axi.burst_write(args.addr + offset * 4, chunk)
            print(f"loaded {offset + len(chunk):5d}/{len(words)} words", flush=True)

        verify_count = len(words) if args.verify_words <= 0 else min(args.verify_words, len(words))
        if verify_range(axi, args.addr, words, verify_count, burst) != 0:
            return 1
        print(f"verified {verify_count}/{len(words)} words", flush=True)

        print(f"loaded {len(words) * 4} bytes to 0x{args.addr:08X}")
        uart = None
        if args.monitor > 0:
            uart = EjtagUartController(transport, chain=uart_chain)
            info = uart.attach()
            print(f"attached EJTAG-UART version=0x{info['version']:08X}")
            for _ in range(2):
                uart._scan(cmd=uart.CMD_RESET)
                for _ in range(8):
                    uart._scan(cmd=uart.CMD_NOP)
                time.sleep(0.01)
            axi.axi_write(0x4060000C, 0x00000003)
            print("cleared AXI UARTLite FIFOs")

        if eio is not None:
            eio.write_outputs(0)
            print(f"released CPU reset through EIO chain {args.eio_chain}")
        if gpio_reset:
            axi.axi_write(VEX_CPU_RESET_GPIO, 0)
            print(f"released CPU reset through AXI GPIO 0x{VEX_CPU_RESET_GPIO:08X}")
        if uart is not None:
            time.sleep(0.25)
            for _ in range(2):
                uart._scan(cmd=uart.CMD_RESET)
                for _ in range(8):
                    uart._scan(cmd=uart.CMD_NOP)
                time.sleep(0.01)
            if args.send:
                uart.send(args.send.encode("utf-8"))
            deadline = time.monotonic() + args.monitor
            while time.monotonic() < deadline:
                try:
                    data = uart.recv(count=0, timeout=0.25)
                except RuntimeError as exc:
                    print(f"UART monitor error: {exc}", file=sys.stderr)
                    for _ in range(2):
                        uart._scan(cmd=uart.CMD_RESET)
                        for _ in range(8):
                            uart._scan(cmd=uart.CMD_NOP)
                        time.sleep(0.01)
                    continue
                if data:
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
        return 0
    finally:
        axi.close()


if __name__ == "__main__":
    raise SystemExit(main())
