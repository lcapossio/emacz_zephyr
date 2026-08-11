#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Vivado BD generator for the Arty A7-100T VexRiscv-full shell.

Step 0 (scaffold): this is a stub so the alternate implementation has a
place to live. The actual BD script arrives in Step 1 once the VexRiscv
Verilog is generated from external/VexRiscv and packaged into a Vivado
Module Reference. Address map matches build_arty_a7_mbv.py (DDR at
0x90000000, DMA aperture at 0x9F000000, emacZero at 0x44A00000, AXI DMA at
0x41E00000, axis_rx_stream_stats at 0x41F00000).

Differences from build_arty_a7_mbv.py that Step 1 must implement:
  - Replace AMD MicroBlaze V IP with a packaged VexRiscv-full block.
  - Drop the mbv MDM debug bridge; fcapz USER3 EJTAG-AXI stays.
  - Reconfigure MIG so ui_clk = 100 MHz (single-domain build).
  - Wire IBUS + DBUS AXI4 masters into ddr_axi + ctrl_axi.
  - Interrupt path: PLIC or a small AXI-INTC OR-reduction into the
    VexRiscv ExternalInterruptPlugin input.
  - USER1 EIO reset bit routed to the VexRiscv reset input.
"""

import sys


def main() -> int:
    sys.stderr.write(
        "build_arty_a7_vex.py: scaffold only. Populated in Step 1.\n"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
