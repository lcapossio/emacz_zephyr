// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
// =============================================================================
// axis_rx_stream_stats.v - AXI-Stream (8-bit) pass-through with AXI-Lite
// slave exposing live-pollable counters for observing the S2MM RX path.
//
// Address map (12-bit, 32-bit data, saturating counters, reset by rst_n):
//   0x00: magic = 0x53324D53 ("S2MS" little-endian)
//   0x04: tvalid_high_cycles              - cycles tvalid=1
//   0x08: tvalid_hs_cycles                - cycles tvalid=1 && tready=1
//   0x0c: tready_low_while_tvalid_cycles  - cycles tvalid=1 && tready=0
//   0x10: tready_low_max_burst            - longest tvalid=1 && tready=0 run
//   0x14: tlast_hs_count                  - frames completed
//   0x18: tsof_hs_count                   - frame starts
//   0x1c: terror_hs_count                 - error-marked handshakes
//   0x20-0x2C: reserved (reads as 0)
//   0x30: control - bit[0] write clears all counters; reads as 0
// =============================================================================

module axis_rx_stream_stats (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI:S_AXIS:M_AXIS, ASSOCIATED_RESET rst_n" *)
    input  wire        clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        rst_n,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input  wire [11:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire        s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire        s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]  s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire        s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire        s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire        s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire        s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [11:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire        s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire        s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire        s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire        s_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *)
    input  wire [7:0]  s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
    input  wire        s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
    output wire        s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST" *)
    input  wire        s_axis_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [7:0]  m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire        m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire        m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire        m_axis_tlast
);

    // tsof/terror sidebands are not surfaced by rx_axis_cc (upstream FIFO);
    // tie internally so their counters stay at 0 rather than exposing unused
    // sideband pins on the BD cell.
    wire s_axis_tsof   = 1'b0;
    wire s_axis_terror = 1'b0;

    // ---------------------------------------------------------------------
    // Pure pass-through of the AXI-Stream (no register slice)
    // ---------------------------------------------------------------------
    assign m_axis_tdata  = s_axis_tdata;
    assign m_axis_tvalid = s_axis_tvalid;
    assign s_axis_tready = m_axis_tready;
    assign m_axis_tlast  = s_axis_tlast;

    wire hs        = s_axis_tvalid & m_axis_tready;
    wire stall     = s_axis_tvalid & ~m_axis_tready;
    wire tvalid_hi = s_axis_tvalid;

    // ---------------------------------------------------------------------
    // Counters
    // ---------------------------------------------------------------------
    reg [31:0] cnt_tvalid_high;
    reg [31:0] cnt_tvalid_hs;
    reg [31:0] cnt_tready_low;
    reg [31:0] cnt_tready_low_max;
    reg [31:0] cnt_tready_low_run;
    reg [31:0] cnt_tlast_hs;
    reg [31:0] cnt_tsof_hs;
    reg [31:0] cnt_terror_hs;

    reg        clear_req;

    // Saturating increment helper (macro-like via function is fine in V2001)
    function [31:0] sat_inc;
        input [31:0] cur;
        input        do_inc;
        begin
            if (do_inc && (cur != 32'hFFFFFFFF))
                sat_inc = cur + 32'd1;
            else
                sat_inc = cur;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_tvalid_high    <= 32'd0;
            cnt_tvalid_hs      <= 32'd0;
            cnt_tready_low     <= 32'd0;
            cnt_tready_low_max <= 32'd0;
            cnt_tready_low_run <= 32'd0;
            cnt_tlast_hs       <= 32'd0;
            cnt_tsof_hs        <= 32'd0;
            cnt_terror_hs      <= 32'd0;
        end else if (clear_req) begin
            cnt_tvalid_high    <= 32'd0;
            cnt_tvalid_hs      <= 32'd0;
            cnt_tready_low     <= 32'd0;
            cnt_tready_low_max <= 32'd0;
            cnt_tready_low_run <= 32'd0;
            cnt_tlast_hs       <= 32'd0;
            cnt_tsof_hs        <= 32'd0;
            cnt_terror_hs      <= 32'd0;
        end else begin
            cnt_tvalid_high <= sat_inc(cnt_tvalid_high, tvalid_hi);
            cnt_tvalid_hs   <= sat_inc(cnt_tvalid_hs,   hs);
            cnt_tready_low  <= sat_inc(cnt_tready_low,  stall);
            cnt_tlast_hs    <= sat_inc(cnt_tlast_hs,    hs & s_axis_tlast);
            cnt_tsof_hs     <= sat_inc(cnt_tsof_hs,     hs & s_axis_tsof);
            cnt_terror_hs   <= sat_inc(cnt_terror_hs,   hs & s_axis_terror);

            // Longest contiguous stall run tracker
            if (stall) begin
                cnt_tready_low_run <= sat_inc(cnt_tready_low_run, 1'b1);
                if (sat_inc(cnt_tready_low_run, 1'b1) > cnt_tready_low_max)
                    cnt_tready_low_max <= sat_inc(cnt_tready_low_run, 1'b1);
            end else begin
                cnt_tready_low_run <= 32'd0;
            end
        end
    end

    // ---------------------------------------------------------------------
    // AXI-Lite slave
    // ---------------------------------------------------------------------
    reg        awready_r;
    reg        wready_r;
    reg        bvalid_r;
    reg [1:0]  bresp_r;
    reg        arready_r;
    reg        rvalid_r;
    reg [31:0] rdata_r;
    reg [1:0]  rresp_r;

    assign s_axi_awready = awready_r;
    assign s_axi_wready  = wready_r;
    assign s_axi_bvalid  = bvalid_r;
    assign s_axi_bresp   = bresp_r;
    assign s_axi_arready = arready_r;
    assign s_axi_rvalid  = rvalid_r;
    assign s_axi_rdata   = rdata_r;
    assign s_axi_rresp   = rresp_r;

    // Latched write address for control decode
    reg [11:0] awaddr_r;
    reg        aw_seen;
    reg        w_seen;
    reg [31:0] wdata_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awready_r <= 1'b0;
            wready_r  <= 1'b0;
            bvalid_r  <= 1'b0;
            bresp_r   <= 2'b00;
            aw_seen   <= 1'b0;
            w_seen    <= 1'b0;
            awaddr_r  <= 12'd0;
            wdata_r   <= 32'd0;
            clear_req <= 1'b0;
        end else begin
            clear_req <= 1'b0;

            // AW capture
            if (!aw_seen && s_axi_awvalid && !awready_r) begin
                awready_r <= 1'b1;
            end else if (awready_r && s_axi_awvalid) begin
                awready_r <= 1'b0;
                awaddr_r  <= s_axi_awaddr;
                aw_seen   <= 1'b1;
            end

            // W capture
            if (!w_seen && s_axi_wvalid && !wready_r) begin
                wready_r <= 1'b1;
            end else if (wready_r && s_axi_wvalid) begin
                wready_r <= 1'b0;
                wdata_r  <= s_axi_wdata;
                w_seen   <= 1'b1;
            end

            // Complete write
            if (aw_seen && w_seen && !bvalid_r) begin
                bvalid_r <= 1'b1;
                bresp_r  <= 2'b00;
                if (awaddr_r == 12'h030 && wdata_r[0]) begin
                    clear_req <= 1'b1;
                end
                aw_seen <= 1'b0;
                w_seen  <= 1'b0;
            end
            if (bvalid_r && s_axi_bready) begin
                bvalid_r <= 1'b0;
            end
        end
    end

    // AR / R
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arready_r <= 1'b0;
            rvalid_r  <= 1'b0;
            rdata_r   <= 32'd0;
            rresp_r   <= 2'b00;
        end else begin
            if (!arready_r && s_axi_arvalid && !rvalid_r) begin
                arready_r <= 1'b1;
            end else if (arready_r && s_axi_arvalid) begin
                arready_r <= 1'b0;
                rvalid_r  <= 1'b1;
                rresp_r   <= 2'b00;
                case (s_axi_araddr[11:0])
                    12'h000: rdata_r <= 32'h53324D53; // "S2MS"
                    12'h004: rdata_r <= cnt_tvalid_high;
                    12'h008: rdata_r <= cnt_tvalid_hs;
                    12'h00c: rdata_r <= cnt_tready_low;
                    12'h010: rdata_r <= cnt_tready_low_max;
                    12'h014: rdata_r <= cnt_tlast_hs;
                    12'h018: rdata_r <= cnt_tsof_hs;
                    12'h01c: rdata_r <= cnt_terror_hs;
                    default: rdata_r <= 32'd0;
                endcase
            end
            if (rvalid_r && s_axi_rready) begin
                rvalid_r <= 1'b0;
            end
        end
    end

endmodule
