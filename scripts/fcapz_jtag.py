# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""fcapz hw_server transport for the board's FPGA, whatever its family.

A Zynq UltraScale+ MPSoC (the ZCU106's xczu7ev) has the ARM DAP in series
with the PL TAP, so its BSCAN scans need different IR handling from a
7-series part. fcapz's CLI picks the chain shape from the part name; the
scripts here use the same rule so one --tap value is all they need.
"""

from __future__ import annotations

import sys
import time
from collections.abc import Callable, Iterator
from pathlib import Path
from typing import TypeVar

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "fcapz" / "host"))

# _chain_shape_kwargs is the CLI's part-family table; emacZero's ZCU106
# scripts use it the same way.
from fcapz.cli import _chain_shape_kwargs  # noqa: E402
from fcapz.ejtagaxi import EjtagAxiController  # noqa: E402
from fcapz.transport import XilinxHwServerTransport  # noqa: E402

# Errors hw_server gives now and then, in spells, when a new xsdb session
# starts: an empty target list on connect, and "JTAG node is not accessible"
# on connect or on a later scan. A fresh session after a pause gets through.
XSDB_TRANSIENT = ("target list is empty", "JTAG node is not accessible")
XSDB_RETRY_PAUSE_S = 2.0
XSDB_TRIES = 3

T = TypeVar("T")


def transport(tap: str, **kwargs) -> XilinxHwServerTransport:
    """Return an unconnected transport for the FPGA named `tap` (e.g. xc7a100t, xczu7)."""
    name = tap.removesuffix(".tap")
    return XilinxHwServerTransport(fpga_name=name, **_chain_shape_kwargs(name), **kwargs)


def open_session(session: Callable[[], T]) -> T:
    """Run session(), again after a pause while xsdb fails transiently.

    session() must open its own transport and close it before it returns or
    raises, and must be safe to run again after a failure.
    """
    for attempt in range(1, XSDB_TRIES + 1):
        try:
            return session()
        except RuntimeError as exc:
            if attempt == XSDB_TRIES or not any(s in str(exc) for s in XSDB_TRANSIENT):
                raise
        time.sleep(XSDB_RETRY_PAUSE_S)
    raise AssertionError("unreachable")


def _connect_axi(tap: str, chain: int) -> EjtagAxiController:
    link = transport(tap)
    bridge = EjtagAxiController(link, chain=chain)
    try:
        bridge.connect()
    except Exception:
        link.close()
        raise
    return bridge


def axi(tap: str, chain: int) -> EjtagAxiController:
    """Return a connected JTAG-AXI bridge; close() it to end the session.

    Only the connect is retried. For reads, read() also retries the scans.
    """
    return open_session(lambda: _connect_axi(tap, chain))


def read(tap: str, chain: int, op: Callable[[EjtagAxiController], T]) -> T:
    """Run op on a JTAG-AXI session of its own and return its result.

    A transient xsdb failure, on connect or inside op, reruns the whole
    session, so op must only read.
    """
    def session() -> T:
        bridge = _connect_axi(tap, chain)
        try:
            return op(bridge)
        finally:
            bridge.close()

    return open_session(session)


# AXI4 forbids an INCR burst from crossing a 4 KiB boundary (A3.4.1); the
# fabric may wrap the address inside the page instead of moving on.
AXI_BOUNDARY = 0x1000


def bursts(addr: int, words: int, max_words: int) -> Iterator[tuple[int, int]]:
    """Split `words` 32-bit words from `addr` into (word offset, count) bursts.

    Each burst holds at most `max_words` beats and stays inside one 4 KiB page.
    """
    if addr % 4:
        raise ValueError(f"burst address 0x{addr:08X} is not word aligned")
    offset = 0
    while offset < words:
        start = addr + offset * 4
        to_boundary = (AXI_BOUNDARY - start % AXI_BOUNDARY) // 4
        count = min(max_words, words - offset, to_boundary)
        yield offset, count
        offset += count
