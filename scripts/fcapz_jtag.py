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
from collections.abc import Callable
from pathlib import Path
from typing import TypeVar

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "fcapz" / "host"))

# _chain_shape_kwargs is the CLI's part-family table; emacZero's ZCU106
# scripts use it the same way.
from fcapz.cli import _chain_shape_kwargs  # noqa: E402
from fcapz.ejtagaxi import EjtagAxiController  # noqa: E402
from fcapz.transport import XilinxHwServerTransport  # noqa: E402

# xsdb sometimes reports "target list is empty" when a JTAG session opens
# right after the previous one closed; one retry after a pause gets through.
XSDB_RACE = "target list is empty"
XSDB_RACE_PAUSE_S = 2.0

T = TypeVar("T")


def transport(tap: str, **kwargs) -> XilinxHwServerTransport:
    """Return an unconnected transport for the FPGA named `tap` (e.g. xc7a100t, xczu7)."""
    name = tap.removesuffix(".tap")
    return XilinxHwServerTransport(fpga_name=name, **_chain_shape_kwargs(name), **kwargs)


def open_session(connect: Callable[[], T]) -> T:
    """Run connect(), once more if xsdb lost its target list.

    connect() must open its own transport and close it if it fails.
    """
    try:
        return connect()
    except RuntimeError as exc:
        if XSDB_RACE not in str(exc):
            raise
    time.sleep(XSDB_RACE_PAUSE_S)
    return connect()


def axi(tap: str, chain: int) -> EjtagAxiController:
    """Return a connected JTAG-AXI bridge; close() it to end the session."""
    def connect() -> EjtagAxiController:
        link = transport(tap)
        bridge = EjtagAxiController(link, chain=chain)
        try:
            bridge.connect()
        except Exception:
            link.close()
            raise
        return bridge

    return open_session(connect)
