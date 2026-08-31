#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Discover and configure emacZero boards without assuming an IP subnet."""

from __future__ import annotations

import argparse
import ipaddress
import random
import select
import socket
import struct
import sys
import time
import zlib
from dataclasses import dataclass

try:
    import psutil
except ImportError as exc:  # pragma: no cover - environment error
    raise SystemExit("emacz_config.py requires psutil (python -m pip install psutil)") from exc


PORT = 5004
MULTICAST_GROUP = "239.255.77.90"
BROADCAST_ADDRESS = "255.255.255.255"
MAGIC = b"EZCF"
VERSION = 1
DISCOVER = 1
OFFER = 2
CONFIG = 3
ACK = 4
NACK = 5
PACKET = struct.Struct("!4sBBBBI6s2x4s4sII")
CRC_OFFSET = 32


@dataclass(frozen=True)
class Message:
    op: int
    status: int
    prefix: int
    xid: int
    mac: bytes
    ip: ipaddress.IPv4Address
    gateway: ipaddress.IPv4Address
    token: int


@dataclass
class Endpoint:
    name: str
    address: str
    sock: socket.socket


def parse_mac(text: str) -> bytes:
    compact = text.replace(":", "").replace("-", "")
    if len(compact) != 12:
        raise ValueError(f"invalid MAC address: {text}")
    return bytes.fromhex(compact)


def format_mac(value: bytes) -> str:
    return ":".join(f"{byte:02x}" for byte in value)


def encode_message(message: Message) -> bytes:
    if len(message.mac) != 6:
        raise ValueError("MAC address must contain six bytes")
    without_crc = PACKET.pack(
        MAGIC,
        VERSION,
        message.op,
        message.status,
        message.prefix,
        message.xid,
        message.mac,
        message.ip.packed,
        message.gateway.packed,
        message.token,
        0,
    )
    crc = zlib.crc32(without_crc[:CRC_OFFSET]) & 0xFFFFFFFF
    return without_crc[:CRC_OFFSET] + struct.pack("!I", crc)


def decode_message(data: bytes) -> Message:
    if len(data) != PACKET.size:
        raise ValueError(f"bad packet size {len(data)}")
    fields = PACKET.unpack(data)
    if fields[0] != MAGIC or fields[1] != VERSION:
        raise ValueError("bad protocol identity")
    expected = zlib.crc32(data[:CRC_OFFSET]) & 0xFFFFFFFF
    if fields[-1] != expected:
        raise ValueError("bad packet CRC")
    return Message(
        op=fields[2],
        status=fields[3],
        prefix=fields[4],
        xid=fields[5],
        mac=fields[6],
        ip=ipaddress.IPv4Address(fields[7]),
        gateway=ipaddress.IPv4Address(fields[8]),
        token=fields[9],
    )


def active_ipv4(interface: str | None = None, bind: str | None = None) -> list[tuple[str, str]]:
    stats = psutil.net_if_stats()
    found: list[tuple[str, str]] = []
    for name, addresses in psutil.net_if_addrs().items():
        if interface is not None and name.casefold() != interface.casefold():
            continue
        if name in stats and not stats[name].isup:
            continue
        for address in addresses:
            if address.family != socket.AF_INET or address.address.startswith("127."):
                continue
            if bind is not None and address.address != bind:
                continue
            found.append((name, address.address))
    if bind is not None and not any(address == bind for _, address in found):
        raise RuntimeError(f"bind address {bind} is not assigned to an active interface")
    if interface is not None and not found:
        raise RuntimeError(f"interface {interface!r} has no active IPv4 address")
    return found


def open_endpoints(interface: str | None = None, bind: str | None = None) -> list[Endpoint]:
    interfaces = active_ipv4(interface, bind)
    if not interfaces:
        raise RuntimeError("no active non-loopback IPv4 interfaces found")
    receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    receiver.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    receiver.bind(("", PORT))
    joined: list[tuple[str, str]] = []
    failures: list[str] = []
    for name, address in interfaces:
        membership = socket.inet_aton(MULTICAST_GROUP) + socket.inet_aton(address)
        try:
            receiver.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
            joined.append((name, address))
        except OSError as exc:
            failures.append(f"{name} ({address}): {exc}")
    if not joined:
        receiver.close()
        detail = "; ".join(failures)
        raise RuntimeError(f"no active interface supports provisioning multicast ({detail})")
    receiver.setblocking(False)
    endpoints: list[Endpoint] = [Endpoint("all", "0.0.0.0", receiver)]
    for name, address in joined:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        try:
            sock.bind((address, 0))
            sock.setblocking(False)
            endpoints.append(Endpoint(name, address, sock))
        except Exception:
            sock.close()
            raise
    return endpoints


def exchange(endpoints: list[Endpoint], packet: bytes, xid: int, expected_op: int,
             timeout: float, target_mac: bytes | None = None
             ) -> dict[bytes, tuple[Message, Endpoint]]:
    for endpoint in endpoints:
        if endpoint.address == "0.0.0.0":
            continue
        endpoint.sock.sendto(packet, (BROADCAST_ADDRESS, PORT))

    deadline = time.monotonic() + timeout
    found: dict[bytes, tuple[Message, Endpoint]] = {}
    sockets = [endpoint.sock for endpoint in endpoints]
    by_socket = {endpoint.sock: endpoint for endpoint in endpoints}
    while time.monotonic() < deadline:
        ready, _, _ = select.select(sockets, [], [], max(0.0, deadline - time.monotonic()))
        if not ready:
            break
        for sock in ready:
            try:
                data, _ = sock.recvfrom(256)
                message = decode_message(data)
            except (BlockingIOError, ValueError):
                continue
            if message.xid == xid and message.op == expected_op:
                found[message.mac] = (message, by_socket[sock])
                if target_mac is not None and message.mac == target_mac:
                    return found
    return found


def discover(endpoints: list[Endpoint], timeout: float) -> dict[bytes, tuple[Message, Endpoint]]:
    xid = random.SystemRandom().getrandbits(32) or 1
    request = Message(
        op=DISCOVER,
        status=0,
        prefix=0,
        xid=xid,
        mac=b"\x00" * 6,
        ip=ipaddress.IPv4Address("0.0.0.0"),
        gateway=ipaddress.IPv4Address("0.0.0.0"),
        token=0,
    )
    return exchange(endpoints, encode_message(request), xid, OFFER, timeout)


def select_board(boards: dict[bytes, tuple[Message, Endpoint]], mac: bytes | None
                 ) -> tuple[Message, Endpoint]:
    if mac is not None:
        if mac not in boards:
            raise RuntimeError(f"board {format_mac(mac)} was not discovered")
        return boards[mac]
    if not boards:
        raise RuntimeError("no emacZero boards discovered")
    if len(boards) != 1:
        names = ", ".join(format_mac(value) for value in sorted(boards))
        raise RuntimeError(f"multiple boards discovered ({names}); select one with --mac")
    return next(iter(boards.values()))


def validate_config(ip: ipaddress.IPv4Address, prefix: int,
                    gateway: ipaddress.IPv4Address) -> None:
    if not 1 <= prefix <= 30:
        raise ValueError("prefix must be between 1 and 30")
    network = ipaddress.IPv4Network((ip, prefix), strict=False)
    if ip.is_multicast or ip.is_unspecified or ip.is_loopback or ip in (network.network_address,
                                                                        network.broadcast_address):
        raise ValueError(f"{ip}/{prefix} is not a usable unicast host address")
    if int(gateway) and (gateway not in network or gateway in (ip, network.network_address,
                                                               network.broadcast_address)):
        raise ValueError(f"gateway {gateway} is not a usable peer in {network}")


def close_endpoints(endpoints: list[Endpoint]) -> None:
    for endpoint in endpoints:
        endpoint.sock.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interface", help="limit discovery to one OS interface name")
    parser.add_argument("--bind", help="limit discovery to one local IPv4 address")
    parser.add_argument("--timeout", type=float, default=2.0)
    subparsers = parser.add_subparsers(dest="command", required=True)
    discover_parser = subparsers.add_parser("discover")
    discover_parser.add_argument("--mac", type=parse_mac)
    configure_parser = subparsers.add_parser("configure")
    configure_parser.add_argument("--mac", type=parse_mac)
    configure_parser.add_argument("--ip", type=ipaddress.IPv4Address, required=True)
    configure_parser.add_argument("--prefix", type=int, default=24)
    configure_parser.add_argument("--gateway", type=ipaddress.IPv4Address,
                                  default=ipaddress.IPv4Address("0.0.0.0"))
    args = parser.parse_args()

    endpoints = open_endpoints(args.interface, args.bind)
    try:
        boards = discover(endpoints, args.timeout)
        if args.command == "discover":
            if args.mac is not None:
                message, endpoint = select_board(boards, args.mac)
                boards = {message.mac: (message, endpoint)}
            for mac, (message, endpoint) in sorted(boards.items()):
                print(
                    f"mac={format_mac(mac)} ip={message.ip}/{message.prefix} "
                    f"gateway={message.gateway} via={endpoint.name} bind={endpoint.address}"
                )
            if not boards:
                raise RuntimeError("no emacZero boards discovered")
            return 0

        validate_config(args.ip, args.prefix, args.gateway)
        offer, endpoint = select_board(boards, args.mac)
        request = Message(
            op=CONFIG,
            status=0,
            prefix=args.prefix,
            xid=offer.xid,
            mac=offer.mac,
            ip=args.ip,
            gateway=args.gateway,
            token=offer.token,
        )
        replies = exchange(endpoints, encode_message(request), offer.xid, ACK, args.timeout,
                           target_mac=offer.mac)
        if offer.mac not in replies:
            raise RuntimeError("board did not acknowledge the configuration")
        reply, _ = replies[offer.mac]
        if reply.status != 0:
            raise RuntimeError(f"board rejected the configuration with status {reply.status}")
        print(
            f"configured mac={format_mac(offer.mac)} ip={reply.ip}/{reply.prefix} "
            f"gateway={reply.gateway} via={endpoint.name}"
        )
        return 0
    finally:
        close_endpoints(endpoints)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2)
