#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Provision an emacZero board and run a portable UDP RX stress test."""

from __future__ import annotations

import argparse
import ipaddress
import socket
import sys
import time
from dataclasses import dataclass

import emacz_config as config

ERROR_COUNTERS = (
    "sink_err",
    "mac_err",
    "gate_bad",
    "gate_ovf",
    "tready",
    "dma_err",
    "bd_err",
    "invalid",
    "alloc",
    "recv_fail",
    "nofree",
)


@dataclass(frozen=True)
class StressResult:
    sent_packets: int
    sent_bytes: int
    elapsed: float
    sink_packets: int
    sink_bytes: int
    delivery_pct: float
    error_deltas: dict[str, int]


def parse_snapshot(data: bytes) -> dict[str, int | str]:
    fields: dict[str, int | str] = {}
    for item in data.decode("ascii", errors="strict").strip().split():
        if "=" not in item:
            raise ValueError(f"malformed snapshot field: {item!r}")
        name, value = item.split("=", 1)
        fields[name] = value if name == "magic" else int(value, 10)
    if fields.get("magic") != "EZRX":
        raise ValueError("board did not return an EZRX acceptance snapshot")
    required = {"uptime", "sink_p", "sink_b", "mac_rx", "dma", *ERROR_COUNTERS}
    missing = required.difference(fields)
    if missing:
        raise ValueError(f"snapshot is missing fields: {', '.join(sorted(missing))}")
    return fields


def get_snapshot(board_ip: str, bind_ip: str, port: int, timeout: float
                 ) -> dict[str, int | str]:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((bind_ip, 0))
        sock.settimeout(timeout)
        sock.sendto(b"a", (board_ip, port))
        data, _ = sock.recvfrom(1024)
    return parse_snapshot(data)


def choose_bind_ip(board_ip: ipaddress.IPv4Address, prefix: int,
                   interface: str | None, bind_ip: str | None) -> str:
    candidates = config.active_ipv4(interface, bind_ip)
    network = ipaddress.IPv4Network((board_ip, prefix), strict=False)
    matches = [address for _, address in candidates if ipaddress.IPv4Address(address) in network]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        raise RuntimeError(f"no selected host address belongs to {network}")
    raise RuntimeError(f"multiple selected host addresses belong to {network}; use --bind")


def provision_board(args: argparse.Namespace) -> bytes:
    endpoints = config.open_endpoints(args.interface, args.bind)
    try:
        boards = config.discover(endpoints, args.timeout)
        offer, _ = config.select_board(boards, args.mac)
        request = config.Message(
            op=config.CONFIG,
            status=0,
            prefix=args.prefix,
            xid=offer.xid,
            mac=offer.mac,
            ip=args.board_ip,
            gateway=args.gateway,
            token=offer.token,
        )
        replies = config.exchange(
            endpoints, config.encode_message(request), offer.xid, config.ACK,
            args.timeout, target_mac=offer.mac,
        )
        if offer.mac not in replies or replies[offer.mac][0].status != 0:
            raise RuntimeError("board did not acknowledge its runtime IPv4 configuration")
        return offer.mac
    finally:
        config.close_endpoints(endpoints)


def send_load(board_ip: str, bind_ip: str, port: int, rate_mbps: float,
              duration: float, packet_size: int, progress: float) -> tuple[int, int, float]:
    rate_bps = rate_mbps * 1_000_000.0
    interval = packet_size * 8.0 / rate_bps
    payload = bytes(index & 0xff for index in range(packet_size))
    target = (board_ip, port)
    packets = 0

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((bind_ip, 0))
        start = time.perf_counter()
        next_send = start
        next_progress = start + progress if progress > 0 else float("inf")
        while True:
            now = time.perf_counter()
            elapsed = now - start
            if elapsed >= duration:
                break
            if now >= next_progress:
                actual = packets * packet_size * 8.0 / elapsed / 1_000_000.0
                print(f"progress elapsed={elapsed:.1f}s packets={packets} rate={actual:.3f}Mbps",
                      flush=True)
                next_progress += progress
            if now < next_send:
                time.sleep(min(next_send - now, 0.001))
                continue
            sock.sendto(payload, target)
            packets += 1
            next_send += interval

    elapsed = time.perf_counter() - start
    return packets, packets * packet_size, elapsed


def evaluate(before: dict[str, int | str], after: dict[str, int | str],
             sent_packets: int, sent_bytes: int, elapsed: float,
             min_delivery_pct: float) -> StressResult:
    if int(after["uptime"]) <= int(before["uptime"]):
        raise RuntimeError("board restarted or stopped advancing during the stress run")
    sink_packets = int(after["sink_p"]) - int(before["sink_p"])
    sink_bytes = int(after["sink_b"]) - int(before["sink_b"])
    error_deltas = {name: int(after[name]) - int(before[name]) for name in ERROR_COUNTERS}
    if any(value < 0 for value in (sink_packets, sink_bytes, *error_deltas.values())):
        raise RuntimeError("board counters moved backwards, indicating a restart or corrupt sample")
    delivery_pct = sink_packets * 100.0 / sent_packets if sent_packets else 0.0
    result = StressResult(sent_packets, sent_bytes, elapsed, sink_packets, sink_bytes,
                          delivery_pct, error_deltas)
    if delivery_pct + 1e-9 < min_delivery_pct:
        raise RuntimeError(
            f"delivery {delivery_pct:.6f}% is below required {min_delivery_pct:.6f}%"
        )
    nonzero = {name: value for name, value in error_deltas.items() if value != 0}
    if nonzero:
        details = ", ".join(f"{name}=+{value}" for name, value in nonzero.items())
        raise RuntimeError(f"hardware/driver error counters advanced: {details}")
    expected_bytes = sink_packets * (sent_bytes // sent_packets) if sent_packets else 0
    if sink_bytes != expected_bytes:
        raise RuntimeError(f"sink byte accounting mismatch: {sink_bytes} != {expected_bytes}")
    return result


def verify_discovery(args: argparse.Namespace, mac: bytes) -> None:
    endpoints = config.open_endpoints(args.interface, args.bind)
    try:
        boards = config.discover(endpoints, args.timeout)
        if mac not in boards:
            raise RuntimeError("board did not answer discovery after the stress run")
        message, _ = boards[mac]
        if message.ip != args.board_ip or message.prefix != args.prefix:
            raise RuntimeError(
                f"board address changed after stress: {message.ip}/{message.prefix}"
            )
    finally:
        config.close_endpoints(endpoints)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interface", help="host interface name, for example Ethernet 2 or enp3s0")
    parser.add_argument("--bind", help="host IPv4 address; inferred from --board-ip/--prefix if unique")
    parser.add_argument("--mac", type=config.parse_mac, help="target board MAC when multiple boards exist")
    parser.add_argument("--board-ip", type=ipaddress.IPv4Address, required=True)
    parser.add_argument("--prefix", type=int, default=24)
    parser.add_argument("--gateway", type=ipaddress.IPv4Address,
                        default=ipaddress.IPv4Address("0.0.0.0"))
    parser.add_argument("--duration", type=float, default=600.0)
    parser.add_argument("--rate-mbps", type=float, default=95.0)
    parser.add_argument("--packet-size", type=int, default=1472)
    parser.add_argument("--port", type=int, default=5001)
    parser.add_argument("--control-port", type=int, default=5002)
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--progress", type=float, default=10.0)
    parser.add_argument("--min-delivery-pct", type=float, default=100.0)
    args = parser.parse_args()

    config.validate_config(args.board_ip, args.prefix, args.gateway)
    if args.duration <= 0 or args.rate_mbps <= 0 or not 1 <= args.packet_size <= 1472:
        raise ValueError("duration/rate must be positive and packet size must be 1..1472")
    if not 0.0 <= args.min_delivery_pct <= 100.0:
        raise ValueError("minimum delivery percentage must be in 0..100")

    bind_ip = choose_bind_ip(args.board_ip, args.prefix, args.interface, args.bind)
    print(f"host_bind={bind_ip} board={args.board_ip}/{args.prefix}")
    mac = provision_board(args)
    print(f"configured_mac={config.format_mac(mac)}")
    time.sleep(0.25)
    before = get_snapshot(str(args.board_ip), bind_ip, args.control_port, args.timeout)
    sent_packets, sent_bytes, elapsed = send_load(
        str(args.board_ip), bind_ip, args.port, args.rate_mbps, args.duration,
        args.packet_size, args.progress,
    )
    time.sleep(0.25)
    after = get_snapshot(str(args.board_ip), bind_ip, args.control_port, args.timeout)
    result = evaluate(before, after, sent_packets, sent_bytes, elapsed,
                      args.min_delivery_pct)
    verify_discovery(args, mac)

    sent_rate = sent_bytes * 8.0 / elapsed / 1_000_000.0
    sink_rate = result.sink_bytes * 8.0 / elapsed / 1_000_000.0
    print(f"sent_packets={sent_packets} sent_bytes={sent_bytes} sent_mbps={sent_rate:.3f}")
    print(f"sink_packets={result.sink_packets} sink_bytes={result.sink_bytes} "
          f"sink_mbps={sink_rate:.3f} delivery_pct={result.delivery_pct:.6f}")
    print("error_deltas=" + " ".join(f"{key}:{value}" for key, value in result.error_deltas.items()))
    print("post_stress_discovery=pass")
    print("stress_result=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"stress_result=fail error={exc}", file=sys.stderr)
        raise SystemExit(1)
