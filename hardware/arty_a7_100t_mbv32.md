# Arty A7-100T MicroBlaze V Hardware Shell

This project uses AMD Zephyr's `mbv32` board support as the software target for
an Arty A7-100T FPGA system. The Vivado design must instantiate a MicroBlaze V
soft CPU and expose emacZero to Zephyr through AXI.

## Required Blocks

- MicroBlaze V 32-bit CPU configured for RV32IMAC with Zicsr/Zifencei.
- AXI INTC at `0x41200000`.
- AXI Timer at `0x41c00000`.
- AXI UARTLite at `0x40600000`, 115200 baud.
- DDR at `0x90000000`.
- emacZero AXI-Lite CSRs at `0x44a00000`.
- emacZero interrupt wired to AXI INTC input 5.

## Ethernet Data Path

The current Zephyr driver controls emacZero's AXI-Lite CSR block. Full Ethernet
traffic needs one more architecture-specific wrapper: a CPU-visible bridge from
emacZero's AXI-Stream TX/RX ports into MicroBlaze V software. Reasonable options
are AXI DMA, an MMIO packet FIFO, or a compact custom AXI-Stream adapter.

Keep the bridge behind the `bard0,emaczero` devicetree boundary so the Zephyr
driver can grow without tying the public API to a single FPGA vendor wrapper.
