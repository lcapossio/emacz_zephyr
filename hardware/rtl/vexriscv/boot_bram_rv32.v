// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
//
// Minimal RV32 boot ROM for the VexRiscv-full Arty shell. Two instructions
// that jump from the reset vector (0x00000000) into DDR at 0x90000000, where
// the fcapz JTAG-AXI loader has already written the Zephyr image before the
// external reset is released.
//
//   00000000:  lui  x5, 0x90000      ; t0 = 0x90000000
//   00000004:  jalr x0, x5, 0        ; jump to DDR (do not link)
//
// The remaining words are 0x00000013 (nop) so an accidental fall-through
// makes no forward progress but does not fault. Storage is 1 KiB = 256
// words, fitting a single 18Kb BRAM. AXI4 slave interface so the CPU IBUS
// can fetch and fcapz can inspect if needed.

`default_nettype none

module boot_bram_rv32 #(
    parameter integer ADDR_WIDTH = 10   // 1 KiB
) (
    input  wire                  aclk,
    input  wire                  aresetn,

    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [7:0]            s_axi_arlen,
    input  wire [2:0]            s_axi_arsize,
    input  wire [1:0]            s_axi_arburst,
    input  wire [0:0]            s_axi_arid,

    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready,
    output reg  [31:0]           s_axi_rdata,
    output reg  [1:0]            s_axi_rresp,
    output reg                   s_axi_rlast,
    output reg  [0:0]            s_axi_rid,

    // Write channel is present so this looks like an AXI4 slave to the
    // interconnect, but writes complete with DECERR to signal read-only.
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [7:0]            s_axi_awlen,
    input  wire [2:0]            s_axi_awsize,
    input  wire [1:0]            s_axi_awburst,
    input  wire [0:0]            s_axi_awid,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    input  wire [31:0]           s_axi_wdata,
    input  wire [3:0]            s_axi_wstrb,
    input  wire                  s_axi_wlast,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,
    output reg  [1:0]            s_axi_bresp,
    output reg  [0:0]            s_axi_bid
);

    localparam integer WORDS = 1 << (ADDR_WIDTH - 2);

    reg [31:0] rom [0:WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) begin
            rom[i] = 32'h00000013;               // nop (addi x0,x0,0)
        end
        rom[0] = 32'h900002B7;                   // lui  x5, 0x90000
        rom[1] = 32'h00028067;                   // jalr x0, x5, 0
    end

    // -------- read channel: single-beat + burst (INCR) --------
    reg                    r_active;
    reg [ADDR_WIDTH-3:0]   r_word_idx;
    reg [7:0]              r_beats_left;
    reg [0:0]              r_id;

    assign s_axi_arready = ~r_active;

    always @(posedge aclk) begin
        if (!aresetn) begin
            r_active      <= 1'b0;
            r_word_idx    <= {(ADDR_WIDTH-2){1'b0}};
            r_beats_left  <= 8'd0;
            r_id          <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rlast   <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rid     <= 1'b0;
            s_axi_rdata   <= 32'h0;
        end else begin
            if (!r_active && s_axi_arvalid) begin
                r_active     <= 1'b1;
                r_word_idx   <= s_axi_araddr[ADDR_WIDTH-1:2];
                r_beats_left <= s_axi_arlen;
                r_id         <= s_axi_arid;
                s_axi_rdata  <= rom[s_axi_araddr[ADDR_WIDTH-1:2]];
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
                s_axi_rid    <= s_axi_arid;
                s_axi_rlast  <= (s_axi_arlen == 8'd0);
            end else if (r_active && s_axi_rvalid && s_axi_rready) begin
                if (r_beats_left == 8'd0) begin
                    r_active     <= 1'b0;
                    s_axi_rvalid <= 1'b0;
                    s_axi_rlast  <= 1'b0;
                end else begin
                    r_beats_left <= r_beats_left - 8'd1;
                    r_word_idx   <= r_word_idx + 1'b1;
                    s_axi_rdata  <= rom[r_word_idx + 1'b1];
                    s_axi_rlast  <= (r_beats_left == 8'd1);
                end
            end
        end
    end

    // -------- write channel: swallow + DECERR --------
    reg w_addr_seen;
    reg w_last_seen;

    assign s_axi_awready = ~w_addr_seen;
    assign s_axi_wready  = w_addr_seen & ~w_last_seen;

    always @(posedge aclk) begin
        if (!aresetn) begin
            w_addr_seen  <= 1'b0;
            w_last_seen  <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b11;   // DECERR
            s_axi_bid    <= 1'b0;
        end else begin
            if (!w_addr_seen && s_axi_awvalid) begin
                w_addr_seen <= 1'b1;
                s_axi_bid   <= s_axi_awid;
            end
            if (w_addr_seen && s_axi_wvalid && s_axi_wready && s_axi_wlast) begin
                w_last_seen  <= 1'b1;
                s_axi_bvalid <= 1'b1;
            end
            if (s_axi_bvalid && s_axi_bready) begin
                w_addr_seen  <= 1'b0;
                w_last_seen  <= 1'b0;
                s_axi_bvalid <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
