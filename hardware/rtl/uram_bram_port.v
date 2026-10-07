// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
// =============================================================================
// uram_bram_port.v - UltraRAM memory behind an AXI BRAM Controller port
//
// blk_mem_gen cannot target UltraRAM and emb_mem_gen is Versal-only, so this
// module gives axi_bram_ctrl (BRAM_PORTA, SINGLE_PORT_BRAM 1) an UltraScale+
// URAM array through xpm_memory_spram. READ_LATENCY must equal the
// controller's READ_LATENCY: the extra stages are the URAM output and
// cascade registers, which a deep array needs to close timing. UltraRAM
// has no read-during-write output, hence WRITE_MODE no_change; the controller
// never reads data back on a write cycle.
// Verilog 2001
// =============================================================================

module uram_bram_port #(
    parameter ADDR_WIDTH   = 19,    // byte address bits: 2^19 = 512 KiB
    parameter DATA_WIDTH   = 64,
    parameter READ_LATENCY = 3
) (
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA CLK" *)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL, MEM_ECC NONE, READ_WRITE_MODE READ_WRITE, READ_LATENCY 3" *)
    input  wire                    clk,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA RST" *)
    input  wire                    rst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA EN" *)
    input  wire                    en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA WE" *)
    input  wire [DATA_WIDTH/8-1:0] we,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *)
    input  wire [ADDR_WIDTH-1:0]   addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *)
    input  wire [DATA_WIDTH-1:0]   din,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA DOUT" *)
    output wire [DATA_WIDTH-1:0]   dout
);

    localparam BYTE_LANES = DATA_WIDTH / 8;
    localparam LANE_BITS  = $clog2(BYTE_LANES);
    localparam WORD_BITS  = ADDR_WIDTH - LANE_BITS;

    xpm_memory_spram #(
        .ADDR_WIDTH_A        (WORD_BITS),
        .AUTO_SLEEP_TIME     (0),
        .BYTE_WRITE_WIDTH_A  (8),
        .ECC_MODE            ("no_ecc"),
        .MEMORY_INIT_FILE    ("none"),
        .MEMORY_INIT_PARAM   ("0"),
        .MEMORY_OPTIMIZATION ("true"),
        .MEMORY_PRIMITIVE    ("ultra"),
        .MEMORY_SIZE         ((1 << WORD_BITS) * DATA_WIDTH),
        .MESSAGE_CONTROL     (0),
        .READ_DATA_WIDTH_A   (DATA_WIDTH),
        .READ_LATENCY_A      (READ_LATENCY),
        .READ_RESET_VALUE_A  ("0"),
        .RST_MODE_A          ("SYNC"),
        .USE_MEM_INIT        (0),
        .WAKEUP_TIME         ("disable_sleep"),
        .WRITE_DATA_WIDTH_A  (DATA_WIDTH),
        .WRITE_MODE_A        ("no_change")
    ) u_mem (
        .clka           (clk),
        .rsta           (rst),
        .ena            (en),
        .regcea         (1'b1),
        .wea            (we),
        .addra          (addr[ADDR_WIDTH-1:LANE_BITS]),
        .dina           (din),
        .douta          (dout),
        .injectdbiterra (1'b0),
        .injectsbiterra (1'b0),
        .dbiterra       (),
        .sbiterra       (),
        .sleep          (1'b0)
    );

endmodule
