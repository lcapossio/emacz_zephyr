// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
//
// Minimal RISC-V "machine-timer" for Zephyr's riscv,machine-timer driver on
// the VexRiscv-full Arty shell. Presents mtime and mtimecmp as two 64-bit
// AXI4-Lite registers back-to-back:
//
//   0x00 : mtime.lo    (R/W, free-running at aclk / TICK_DIV)
//   0x04 : mtime.hi
//   0x08 : mtimecmp.lo (R/W)
//   0x0C : mtimecmp.hi
//
// timer_irq asserts while mtime >= mtimecmp (level-sensitive, per RISC-V
// privileged spec 3.2.1). At 100 MHz with TICK_DIV=1 the tick period is
// 10 ns — CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC=100000000 in arty_a7_vex.conf
// matches this directly.
//
// Single-outstanding, no burst — sufficient for CLINT-style single-word
// polling/store traffic from the CPU. Ticks every aclk cycle — at 100 MHz
// that gives a 10 ns period, matching CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC.

`default_nettype none

module riscv_mtimer (
    input  wire        aclk,
    input  wire        aresetn,

    // AXI4-Lite slave (4 registers)
    input  wire [3:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [3:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    output wire        timer_irq
);

    // -------- registers --------
    reg [63:0] mtime;
    reg [63:0] mtimecmp;

    // Level-sensitive per RISC-V priv spec: hold high while mtime >= mtimecmp.
    assign timer_irq = (mtime >= mtimecmp);

    // -------- AXI4-Lite write handshake --------
    reg        aw_seen;
    reg [3:0]  aw_addr_l;

    assign s_axi_awready = ~aw_seen;
    assign s_axi_wready  = aw_seen & ~s_axi_bvalid;

    wire       do_write   = aw_seen && s_axi_wvalid && !s_axi_bvalid;
    wire [1:0] wr_word    = aw_addr_l[3:2];   // 0=mtime.lo, 1=mtime.hi, 2=cmp.lo, 3=cmp.hi
    wire       wr_mtime_l = do_write && (wr_word == 2'd0);
    wire       wr_mtime_h = do_write && (wr_word == 2'd1);
    wire       wr_cmp_l   = do_write && (wr_word == 2'd2);
    wire       wr_cmp_h   = do_write && (wr_word == 2'd3);

    // Single always block for mtime — AXI write beats the free-running
    // increment on any strobed byte lane; unstrobed bytes tick as normal.
    integer bi;
    always @(posedge aclk) begin
        if (!aresetn) begin
            mtime <= 64'd0;
        end else begin
            mtime <= mtime + 64'd1;
            if (wr_mtime_l) begin
                for (bi = 0; bi < 4; bi = bi + 1) begin
                    if (s_axi_wstrb[bi]) mtime[bi*8 +: 8] <= s_axi_wdata[bi*8 +: 8];
                end
            end
            if (wr_mtime_h) begin
                for (bi = 0; bi < 4; bi = bi + 1) begin
                    if (s_axi_wstrb[bi]) mtime[32 + bi*8 +: 8] <= s_axi_wdata[bi*8 +: 8];
                end
            end
        end
    end

    // Single always block for mtimecmp.
    always @(posedge aclk) begin
        if (!aresetn) begin
            mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF;  // parked, no IRQ
        end else begin
            if (wr_cmp_l) begin
                for (bi = 0; bi < 4; bi = bi + 1) begin
                    if (s_axi_wstrb[bi]) mtimecmp[bi*8 +: 8] <= s_axi_wdata[bi*8 +: 8];
                end
            end
            if (wr_cmp_h) begin
                for (bi = 0; bi < 4; bi = bi + 1) begin
                    if (s_axi_wstrb[bi]) mtimecmp[32 + bi*8 +: 8] <= s_axi_wdata[bi*8 +: 8];
                end
            end
        end
    end

    // Handshake bookkeeping.
    always @(posedge aclk) begin
        if (!aresetn) begin
            aw_seen      <= 1'b0;
            aw_addr_l    <= 4'h0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
        end else begin
            if (!aw_seen && s_axi_awvalid) begin
                aw_seen   <= 1'b1;
                aw_addr_l <= s_axi_awaddr;
            end
            if (do_write) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
            end
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
                aw_seen      <= 1'b0;
            end
        end
    end

    // -------- AXI4-Lite read channel --------
    assign s_axi_arready = ~s_axi_rvalid;

    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= 2'b00;
            s_axi_rdata  <= 32'h0;
        end else begin
            if (!s_axi_rvalid && s_axi_arvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
                case (s_axi_araddr[3:2])
                    2'd0: s_axi_rdata <= mtime[31:0];
                    2'd1: s_axi_rdata <= mtime[63:32];
                    2'd2: s_axi_rdata <= mtimecmp[31:0];
                    2'd3: s_axi_rdata <= mtimecmp[63:32];
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
