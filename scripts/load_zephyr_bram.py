#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Load a flat binary into the Arty MBV memory window through fcapz EJTAG-AXI."""

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


def words_from_file(path: Path) -> list[int]:
    raw = path.read_bytes()
    if len(raw) % 4:
        raw += b"\x00" * (4 - (len(raw) % 4))
    return [int.from_bytes(raw[i:i + 4], "little") for i in range(0, len(raw), 4)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", default="build-wsl-zephyr-run/zephyr/zephyr.bin")
    parser.add_argument("--addr", type=lambda value: int(value, 0), default=0x80000000)
    parser.add_argument("--chain", type=int, default=3)
    parser.add_argument("--tap", default="xc7a100t")
    parser.add_argument("--chunk-words", type=int, default=16)
    parser.add_argument("--verify-words", type=int, default=16)
    parser.add_argument("--no-reset", action="store_true")
    parser.add_argument("--monitor", type=float, default=0.0)
    parser.add_argument("--send", default="")
    args = parser.parse_args()

    image = Path(args.file)
    if not image.is_absolute():
        image = ROOT / image
    words = words_from_file(image)

    transport = XilinxHwServerTransport(fpga_name=args.tap)
    eio = None
    if not args.no_reset:
        eio = EioController(transport, chain=1, base_addr=0x8000)
        eio.connect()
        eio.write_outputs(1)
        print("held MBV reset through USER1 EIO")

    axi = EjtagAxiController(transport, chain=args.chain)
    axi.connect()

    try:
        for offset in range(0, len(words), args.chunk_words):
            chunk = words[offset:offset + args.chunk_words]
            axi.burst_write(args.addr + offset * 4, chunk)
            print(f"loaded {offset + len(chunk):5d}/{len(words)} words", flush=True)

        verify_count = min(args.verify_words, len(words))
        got = axi.burst_read(args.addr, verify_count)
        if got != words[:verify_count]:
            for i, (expected, actual) in enumerate(zip(words, got)):
                if expected != actual:
                    print(
                        f"verify mismatch @ 0x{args.addr + i * 4:08X}: "
                        f"expected 0x{expected:08X}, got 0x{actual:08X}",
                        file=sys.stderr,
                    )
                    return 1
            return 1

        print(f"loaded {len(words) * 4} bytes to 0x{args.addr:08X}")
        uart = None
        if args.monitor > 0:
            uart = EjtagUartController(transport, chain=4)
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
            print("released MBV reset through USER1 EIO")
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
