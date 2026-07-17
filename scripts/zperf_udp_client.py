#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Tiny iperf2/zperf-compatible UDP client for board bring-up."""

from __future__ import annotations

import argparse
import socket
import struct
import time


ZPERF_DATAGRAM_SIZE = 16
ZPERF_CLIENT_HDR_SIZE = 24
ZPERF_SERVER_HDR_SIZE = 40


def mbps(num_bytes: int, seconds: float) -> float:
    if seconds <= 0:
        return 0.0
    return (num_bytes * 8.0) / seconds / 1_000_000.0


def make_packet(seq: int, elapsed_us: int, packet_size: int, port: int, rate_bps: float) -> bytes:
    sec = elapsed_us // 1_000_000
    usec = elapsed_us % 1_000_000
    payload_len = max(0, packet_size - ZPERF_DATAGRAM_SIZE - ZPERF_CLIENT_HDR_SIZE)
    datagram = struct.pack("!iIII", seq, sec, usec, 0)
    client_hdr = struct.pack(
        "!iiiiii",
        0,
        1,
        port,
        payload_len,
        int(rate_bps // 1000),
        packet_size,
    )
    return datagram + client_hdr + (b"z" * payload_len)


def parse_stats(data: bytes) -> dict[str, int | float]:
    if len(data) < ZPERF_DATAGRAM_SIZE + ZPERF_SERVER_HDR_SIZE:
        raise ValueError(f"short stats packet: {len(data)} bytes")

    fields = struct.unpack(
        "!iiiiiiiiii",
        data[ZPERF_DATAGRAM_SIZE:ZPERF_DATAGRAM_SIZE + ZPERF_SERVER_HDR_SIZE],
    )
    flags, total_hi, total_lo, stop_sec, stop_usec, errors, outorder, datagrams, jitter_hi, jitter_lo = fields
    total_len = ((total_hi & 0xFFFFFFFF) << 32) + (total_lo & 0xFFFFFFFF)
    duration = stop_sec + (stop_usec / 1_000_000.0)
    jitter_us = (jitter_hi * 1_000_000) + jitter_lo
    return {
        "flags": flags & 0xFFFFFFFF,
        "total_len": total_len,
        "duration": duration,
        "errors": errors,
        "outorder": outorder,
        "datagrams": datagrams,
        "jitter_us": jitter_us,
    }


def run(args: argparse.Namespace) -> int:
    if args.packet_size < ZPERF_DATAGRAM_SIZE + ZPERF_CLIENT_HDR_SIZE:
        raise SystemExit("packet size is too small for zperf UDP headers")

    rate_bps = args.rate_mbps * 1_000_000.0
    interval = (args.packet_size * 8.0) / rate_bps if rate_bps > 0 else 0.0
    target = (args.host, args.port)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if args.host.endswith(".255"):
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    if args.bind:
        sock.bind((args.bind, 0))
    sock.settimeout(args.timeout)

    start = time.perf_counter()
    next_send = start
    seq = 0

    while True:
        now = time.perf_counter()
        if now - start >= args.duration:
            break

        if interval > 0 and now < next_send:
            time.sleep(min(next_send - now, 0.001))
            continue

        elapsed_us = int((now - start) * 1_000_000)
        sock.sendto(make_packet(seq, elapsed_us, args.packet_size, args.port, rate_bps), target)
        seq += 1
        next_send += interval

    elapsed_us = int((time.perf_counter() - start) * 1_000_000)
    fin = make_packet(-seq, elapsed_us, args.packet_size, args.port, rate_bps)

    stats = None
    for _ in range(args.fin_retries):
        sock.sendto(fin, target)
        try:
            stats = parse_stats(sock.recv(2048))
            break
        except socket.timeout:
            continue

    elapsed = time.perf_counter() - start
    sent_bytes = seq * args.packet_size
    print(f"sent packets={seq} bytes={sent_bytes} time={elapsed:.3f}s rate={mbps(sent_bytes, elapsed):.3f} Mbits/sec")

    if stats is None:
        print("receiver stats: timeout")
        return 1

    print(
        "receiver packets={datagrams} lost={errors} outorder={outorder} "
        "bytes={total_len} time={duration:.3f}s rate={rate:.3f} Mbits/sec "
        "jitter_us={jitter_us}".format(rate=mbps(int(stats["total_len"]), float(stats["duration"])), **stats)
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("host", nargs="?", default="192.168.137.200")
    parser.add_argument("--port", type=int, default=5001)
    parser.add_argument("--duration", type=float, default=2.0)
    parser.add_argument("--rate-mbps", type=float, default=1.0)
    parser.add_argument("--packet-size", type=int, default=1064)
    parser.add_argument("--bind", help="local IPv4 address to bind, e.g. 192.168.137.1")
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--fin-retries", type=int, default=5)
    return run(parser.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
