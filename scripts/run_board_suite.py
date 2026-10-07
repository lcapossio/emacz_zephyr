#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Boot a hardware shell and run the board acceptance suite against it.

Steps, in order (each one runs only if the previous ones passed):

  boot       program the bitstream and load the Zephyr image (--skip-boot
             to test a board that is already running); on the ZCU106 R5
             shell load_zynqmp_r5.py does both, with the FSBL
  provision  give the board its IPv4 address over emacz_config discovery,
             then wait for the UDP control port to answer
  rx         UDP sink accounting (run_udp_accounting.py)
  recovery   AXI DMA S2MM halt and driver recovery (run_dma_recovery_test.py)
  tx         board UDP TX benchmark (run_tx_accounting.py)

The JTAG and address details of each shell come from SHELLS; the host side
needs only the interface (or address) that faces the board.
"""

from __future__ import annotations

import argparse
import ipaddress
import socket
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path

import emacz_config as config
from run_arty_stress import choose_bind_ip, provision_board

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


@dataclass(frozen=True)
class Shell:
    tap: str            # FPGA JTAG target, see fcapz_jtag
    chain: int          # fcapz EJTAG-AXI BSCAN chain
    perf_stats: int     # app perf-stats block (host page + 0x1000)
    dma_base: int       # AXI DMA registers, as the JTAG-AXI bridge sees them
    csr_base: int       # emacZero CSRs, as the JTAG-AXI bridge sees them
    ps_boot: bool = False  # the PS boots it: load_zynqmp_r5.py, not program+BRAM


# The soft-CPU shells share one address map; only the FPGA, the bridge's
# chain and the CPU reset differ (load_zephyr_bram.py knows the reset).
SHELLS = {
    "mbv": Shell("xc7a100t", 3, 0x9FFFF000, 0x41E00000, 0x44A00000),
    "vex": Shell("xc7a100t", 4, 0x9FFFF000, 0x41E00000, 0x44A00000),
    "zcu106_vex": Shell("xczu7", 4, 0x9FFFF000, 0x41E00000, 0x44A00000),
    # Cortex-R5 #0 in the PS: the blocks sit in the HPM0_LPD window, the
    # host page in PS DDR (app/boards/zcu106_r5.overlay)
    "zcu106_r5": Shell("xczu7", 4, 0x07FFF000, 0x81E00000, 0x84A00000, ps_boot=True),
}

LOAD_ATTEMPTS = 3


def run(cmd: list[str], log: list[str] | None = None) -> int:
    """Run a script from the repo root, echoing its output."""
    print("$ " + " ".join(cmd), flush=True)
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=False)
    output = result.stdout + result.stderr
    sys.stdout.write(output)
    if log is not None:
        log.extend(output.splitlines())
    return result.returncode


class UartCapture(threading.Thread):
    """Collect the console UART's lines while the board boots."""

    def __init__(self, port: str, baud: int):
        super().__init__(daemon=True)
        import serial  # pyserial; only needed with --uart

        self.serial = serial.Serial(port, baud, timeout=0.2)
        self.lines: list[str] = []
        self.stop = threading.Event()

    def run(self) -> None:
        with self.serial:
            while not self.stop.is_set():
                line = self.serial.readline()
                if line:
                    self.lines.append(line.decode(errors="replace").rstrip())

    def finish(self) -> list[str]:
        self.stop.set()
        self.join()
        return self.lines


def load_command(args: argparse.Namespace, shell: Shell) -> list[str]:
    if shell.ps_boot:
        load = [sys.executable, str(SCRIPTS / "load_zynqmp_r5.py"), "--tap", shell.tap]
        if args.bit:
            load += ["--bit", str(args.bit)]
        if args.image:
            load += ["--elf", str(args.image)]
        return load
    load = [sys.executable, str(SCRIPTS / "load_zephyr_bram.py"), "--shell", args.shell]
    if args.image:
        load += ["--file", str(args.image)]
    return load


def boot(args: argparse.Namespace, shell: Shell) -> bool:
    if not shell.ps_boot:
        program = [sys.executable, str(SCRIPTS / "program_fpga.py"), "--shell", args.shell]
        if args.bit:
            program += ["--bit", str(args.bit)]
        if run(program) != 0:
            return False
    # Opening the port before the CPU leaves reset catches the banner
    uart = UartCapture(args.uart, args.baud) if args.uart else None
    if uart:
        uart.start()
    load = load_command(args, shell)
    try:
        for attempt in range(1, LOAD_ATTEMPTS + 1):
            if run(load) == 0:
                break
            print(f"load attempt {attempt} failed", flush=True)
            time.sleep(3)
        else:
            return False
        time.sleep(args.boot_wait)
    finally:
        if uart:
            print("---- console UART")
            for line in uart.finish():
                print(line)
            print("----", flush=True)
    return True


def control_reply(board: str, bind: str, port: int, timeout: float) -> str | None:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((bind, 0))
        sock.settimeout(timeout)
        try:
            sock.sendto(b"s", (board, port))
            data, _ = sock.recvfrom(2048)
        except OSError:
            return None
    return data.decode("ascii", errors="replace").strip()


def provision(args: argparse.Namespace) -> bool:
    # The host address only shows up once the link is up, which on an SFP
    # board is after the bitstream is loaded, so it is resolved here.
    deadline = time.monotonic() + args.provision_timeout
    requested_bind = args.bind
    while True:
        try:
            args.bind = choose_bind_ip(args.board_ip, args.prefix, args.interface,
                                       requested_bind)
            mac = provision_board(args)
            print(f"configured {config.format_mac(mac)} as {args.board_ip}/{args.prefix} "
                  f"from {args.bind}")
            break
        except (OSError, RuntimeError) as exc:
            if time.monotonic() >= deadline:
                print(f"provisioning failed: {exc}")
                return False
            time.sleep(1.0)
    while True:
        reply = control_reply(str(args.board_ip), args.bind, args.control_port, 1.0)
        if reply is not None:
            print(f"control port: {reply}")
            return True
        if time.monotonic() >= deadline:
            print("control port did not answer")
            return False


def jtag_args(shell: Shell) -> list[str]:
    return ["--tap", shell.tap, "--chain", str(shell.chain)]


def test_rx(args: argparse.Namespace, shell: Shell) -> bool:
    return run([
        sys.executable, str(SCRIPTS / "run_udp_accounting.py"), *jtag_args(shell),
        "--addr", hex(shell.perf_stats), "--target", str(args.board_ip), "--bind", args.bind,
        "--rate-mbps", str(args.rx_rate_mbps), "--duration", str(args.rx_duration),
    ]) == 0


def test_recovery(args: argparse.Namespace, shell: Shell) -> bool:
    return run([
        sys.executable, str(SCRIPTS / "run_dma_recovery_test.py"), *jtag_args(shell),
        "--addr", hex(shell.perf_stats), "--dma-base", hex(shell.dma_base),
        "--board", str(args.board_ip), "--bind", args.bind,
    ]) == 0


def test_tx(args: argparse.Namespace, shell: Shell) -> bool:
    return run([
        sys.executable, str(SCRIPTS / "run_tx_accounting.py"), *jtag_args(shell),
        "--csr-base", hex(shell.csr_base), "--board", str(args.board_ip), "--bind", args.bind,
        "--rate-mbps", str(args.tx_rate_mbps), "--duration", str(args.tx_duration),
    ]) == 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--shell", choices=sorted(SHELLS), required=True)
    parser.add_argument("--bit", type=Path, help="bitstream (default: the shell's build output)")
    parser.add_argument("--image", type=Path, help="Zephyr image: zephyr.bin, or zephyr.elf for zcu106_r5 "
                        "(default: the loader's)")
    parser.add_argument("--skip-boot", action="store_true", help="the board is already running")
    parser.add_argument("--uart", help="console UART to capture during boot, e.g. COM4 or /dev/ttyUSB1")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--boot-wait", type=float, default=6.0,
                        help="seconds from CPU release to provisioning (default 6)")
    parser.add_argument("--interface", help="host interface facing the board, e.g. \"Ethernet 2\"")
    parser.add_argument("--bind", help="host IPv4 address facing the board")
    parser.add_argument("--mac", type=config.parse_mac, help="board MAC, if several answer")
    parser.add_argument("--board-ip", type=ipaddress.IPv4Address, required=True)
    parser.add_argument("--prefix", type=int, default=24)
    parser.add_argument("--gateway", type=ipaddress.IPv4Address,
                        default=ipaddress.IPv4Address("0.0.0.0"))
    parser.add_argument("--timeout", type=float, default=2.0, help="discovery reply timeout")
    parser.add_argument("--provision-timeout", type=float, default=30.0)
    parser.add_argument("--control-port", type=int, default=5002)
    parser.add_argument("--rx-rate-mbps", type=float, default=5.0)
    parser.add_argument("--rx-duration", type=float, default=10.0)
    parser.add_argument("--tx-rate-mbps", type=float, default=0.0, help="0 is as fast as possible")
    parser.add_argument("--tx-duration", type=float, default=5.0)
    args = parser.parse_args()

    config.validate_config(args.board_ip, args.prefix, args.gateway)
    shell = SHELLS[args.shell]
    print(f"shell={args.shell} board={args.board_ip}/{args.prefix}", flush=True)

    steps = [
        ("provision", lambda: provision(args)),
        ("rx", lambda: test_rx(args, shell)),
        ("recovery", lambda: test_recovery(args, shell)),
        ("tx", lambda: test_tx(args, shell)),
    ]
    if not args.skip_boot:
        steps.insert(0, ("boot", lambda: boot(args, shell)))

    results: dict[str, str] = {}
    for name, step in steps:
        print(f"===== {name}", flush=True)
        passed = step()
        results[name] = "pass" if passed else "FAIL"
        if not passed:
            break
    for name, _ in steps:
        results.setdefault(name, "skipped")

    print("===== summary")
    for name, _ in steps:
        print(f"{name:10} {results[name]}")
    ok = all(value == "pass" for value in results.values())
    print(f"suite_result={'pass' if ok else 'fail'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
