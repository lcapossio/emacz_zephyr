#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Monitor the Arty A7 fcapz EJTAG-UART console over Xilinx hw_server."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "fcapz" / "host"))

from fcapz import EjtagUartController, XilinxHwServerTransport  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1", help="hw_server host")
    parser.add_argument("--port", type=int, default=3121, help="hw_server port")
    parser.add_argument("--fpga", default="xc7a100t", help="JTAG target filter")
    parser.add_argument("--chain", type=int, default=4, help="BSCANE2 USER chain")
    parser.add_argument("--program", help="optional bitstream to program first")
    parser.add_argument("--timeout", type=float, default=10.0, help="seconds to monitor")
    parser.add_argument("--send", help="optional text to send after connecting")
    parser.add_argument("--no-reset", action="store_true", help="do not reset the fcapz UART FIFO on connect")
    args = parser.parse_args()

    bitfile = Path(args.program).resolve().as_posix() if args.program else None
    transport = XilinxHwServerTransport(
        host=args.host,
        port=args.port,
        fpga_name=args.fpga,
        bitfile=bitfile,
        ready_probe_addr=None,
    )
    uart = EjtagUartController(transport, chain=args.chain)
    info = uart.connect()
    print(f"connected EJTAG-UART version=0x{info['version']:08X}", file=sys.stderr)
    if not args.no_reset:
        for _ in range(2):
            uart._scan(cmd=uart.CMD_RESET)
            for _ in range(8):
                uart._scan(cmd=uart.CMD_NOP)
            time.sleep(0.01)

    try:
        if args.send:
            uart.send(args.send.encode("utf-8"))
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            data = uart.recv(count=0, timeout=0.25)
            if data:
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
    finally:
        uart.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
