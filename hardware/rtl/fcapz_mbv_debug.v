// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
// =============================================================================
// fcapz_mbv_debug.v - fpgacapZero debug wrapper for the Arty MBV shell
//
// Keeps fcapz/Xilinx USER-chain debug plumbing outside the MicroBlaze V block
// design. The CPU still talks to a normal AXI UARTLite; this wrapper bridges
// that UART to fcapz EJTAG-UART on USER4 and captures bring-up probes with an
// fcapz ELA on USER1.
// =============================================================================

module fcapz_mbv_debug #(
    parameter CLK_HZ = 100_000_000,
    parameter UART_BAUD = 115200,
    parameter ELA_DEPTH = 512
) (
    input  wire clk,
    input  wire rst,

    (* X_INTERFACE_IGNORE = "true" *)
    input  wire cpu_uart_tx,
    (* X_INTERFACE_IGNORE = "true" *)
    output wire cpu_uart_rx,

    (* X_INTERFACE_IGNORE = "true" *)
    input  wire timer_irq,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire uart_irq,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire gpio_irq,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire emac_irq,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire mb_reset,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire peripheral_reset,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire phy_rstn,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire [3:0] mii_txd_pre_iob,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire       mii_tx_en_pre_iob,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire       eth_tx_clk,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire       phy_ref_clk_25,
    (* X_INTERFACE_IGNORE = "true" *)
    output wire debug_reset_req,

    (* X_INTERFACE_IGNORE = "true" *)
    input  wire [7:0]  mac_rx_axis_tdata,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        mac_rx_axis_tvalid,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        mac_rx_axis_tready,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        mac_rx_axis_tlast,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        mac_rx_axis_tsof,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        mac_rx_axis_terror,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire [7:0]  dma_rx_axis_tdata,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        dma_rx_axis_tvalid,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        dma_rx_axis_tready,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        dma_rx_axis_tlast,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        dma_rx_axis_tsof,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        dma_rx_axis_terror,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire [7:0]  s2mm_awlen,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        s2mm_awvalid,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        s2mm_awready,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        s2mm_wvalid,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        s2mm_wready,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        s2mm_wlast,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire [1:0]  s2mm_bresp,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        s2mm_bvalid,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        s2mm_bready,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        sg_awvalid,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        sg_awready,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        sg_wvalid,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        sg_wready,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        sg_bvalid,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        sg_bready,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        sg_arvalid,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        sg_arready,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        sg_rvalid,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        sg_rready,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire        sg_rlast,

    output wire [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    output wire [2:0]  m_axi_awprot,
    output wire [31:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    output wire        m_axi_wlast,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,
    output wire [31:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    output wire [2:0]  m_axi_arprot,
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    input  wire        m_axi_rlast,
    output wire        m_axi_rready
);

    reg [15:0] heartbeat;

    always @(posedge clk) begin
        if (rst) begin
            heartbeat <= 16'd0;
        end else begin
            heartbeat <= heartbeat + 16'd1;
        end
    end

    wire eio_reset_req_jtag;
    reg  eio_reset_meta;
    reg  eio_reset_sync;

    always @(posedge clk) begin
        if (rst) begin
            eio_reset_meta <= 1'b0;
            eio_reset_sync <= 1'b0;
        end else begin
            eio_reset_meta <= eio_reset_req_jtag;
            eio_reset_sync <= eio_reset_meta;
        end
    end

    assign debug_reset_req = eio_reset_sync;

    fcapz_ejtaguart_xilinx7 #(
        .JTAG_CHAIN(4),
        .CLK_HZ(CLK_HZ),
        .BAUD_RATE(UART_BAUD),
        .TX_FIFO_DEPTH(256),
        .RX_FIFO_DEPTH(256),
        .PARITY(0)
    ) u_ejtaguart (
        .uart_clk(clk),
        .uart_rst(rst),
        .uart_txd(cpu_uart_rx),
        .uart_rxd(cpu_uart_tx)
    );

    fcapz_ejtagaxi_xilinx7 #(
        .ADDR_W(32),
        .DATA_W(32),
        .FIFO_DEPTH(16),
        .TIMEOUT(4096),
        .ASYNC_FIFO_IMPL(0),
        .CHAIN(3)
    ) u_ejtagaxi (
        .axi_clk(clk),
        .axi_rst(rst),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rready(m_axi_rready),
        .debug_tck(),
        .debug_tck_edge(),
        .debug_axi(),
        .debug_axi_edge()
    );

    wire dma_rx_axis_accept = dma_rx_axis_tvalid & dma_rx_axis_tready;
    wire mac_rx_axis_stall = mac_rx_axis_tvalid & !mac_rx_axis_tready;
    wire dma_rx_axis_stall = dma_rx_axis_tvalid & !dma_rx_axis_tready;
    wire s2mm_aw_hs = s2mm_awvalid & s2mm_awready;
    wire s2mm_w_hs = s2mm_wvalid & s2mm_wready;
    wire s2mm_b_hs = s2mm_bvalid & s2mm_bready;
    wire s2mm_aw_stall = s2mm_awvalid & !s2mm_awready;
    wire s2mm_w_stall = s2mm_wvalid & !s2mm_wready;
    wire s2mm_write_active = s2mm_awvalid | s2mm_wvalid | s2mm_bvalid;
    wire sg_read_active = sg_arvalid | sg_rvalid;
    wire sg_write_active = sg_awvalid | sg_wvalid | sg_bvalid;
    wire dma_stall_no_wvalid = dma_rx_axis_stall & !s2mm_wvalid;
    reg [15:0] dma_rx_byte_index;
    reg [15:0] dma_rx_eth_type;
    reg        dma_rx_in_frame;
    reg        dma_rx_bad_header;
    reg [7:0]  mac_rx_stall_run;
    reg [7:0]  dma_rx_stall_run;

    always @(posedge clk) begin
        if (rst) begin
            dma_rx_byte_index <= 16'd0;
            dma_rx_eth_type <= 16'd0;
            dma_rx_in_frame <= 1'b0;
            dma_rx_bad_header <= 1'b0;
            mac_rx_stall_run <= 8'd0;
            dma_rx_stall_run <= 8'd0;
        end else begin
            dma_rx_bad_header <= 1'b0;

            if (mac_rx_axis_stall) begin
                if (mac_rx_stall_run != 8'hff)
                    mac_rx_stall_run <= mac_rx_stall_run + 1'b1;
            end else begin
                mac_rx_stall_run <= 8'd0;
            end

            if (dma_rx_axis_stall) begin
                if (dma_rx_stall_run != 8'hff)
                    dma_rx_stall_run <= dma_rx_stall_run + 1'b1;
            end else begin
                dma_rx_stall_run <= 8'd0;
            end

            if (dma_rx_axis_accept) begin
                dma_rx_in_frame <= 1'b1;
                case (dma_rx_byte_index)
                    16'd12: dma_rx_eth_type[15:8] <= dma_rx_axis_tdata;
                    16'd13: begin
                        dma_rx_eth_type[7:0] <= dma_rx_axis_tdata;
                        if ({dma_rx_eth_type[15:8], dma_rx_axis_tdata} != 16'h0800 &&
                            {dma_rx_eth_type[15:8], dma_rx_axis_tdata} != 16'h0806) begin
                            dma_rx_bad_header <= 1'b1;
                        end
                    end
                    16'd14: begin
                        if (dma_rx_eth_type == 16'h0800 && dma_rx_axis_tdata[7:4] != 4'h4) begin
                            dma_rx_bad_header <= 1'b1;
                        end
                    end
                    default: begin
                    end
                endcase

                if (dma_rx_axis_tlast) begin
                    dma_rx_byte_index <= 16'd0;
                    dma_rx_in_frame <= 1'b0;
                end else begin
                    dma_rx_byte_index <= dma_rx_byte_index + 16'd1;
                end
            end
        end
    end

    reg [1:0] eth_tx_en_sync;
    reg [1:0] eth_tx_clk_sync;
    reg [1:0] eth_ref_clk_sync;
    reg [1:0] eth_rstn_sync;
    reg [3:0] eth_txd_meta;
    reg [3:0] eth_txd_sync;

    always @(posedge clk) begin
        if (rst) begin
            eth_tx_en_sync  <= 2'b00;
            eth_tx_clk_sync <= 2'b00;
            eth_ref_clk_sync <= 2'b00;
            eth_rstn_sync <= 2'b00;
            eth_txd_meta <= 4'd0;
            eth_txd_sync <= 4'd0;
        end else begin
            eth_tx_en_sync  <= {eth_tx_en_sync[0], mii_tx_en_pre_iob};
            eth_tx_clk_sync <= {eth_tx_clk_sync[0], eth_tx_clk};
            eth_ref_clk_sync <= {eth_ref_clk_sync[0], phy_ref_clk_25};
            eth_rstn_sync <= {eth_rstn_sync[0], phy_rstn};
            eth_txd_meta <= mii_txd_pre_iob;
            eth_txd_sync <= eth_txd_meta;
        end
    end

    wire eth_tx_en_rise = eth_tx_en_sync == 2'b01;
    wire eth_tx_clk_edge = eth_tx_clk_sync[1] ^ eth_tx_clk_sync[0];
    wire eth_ref_clk_edge = eth_ref_clk_sync[1] ^ eth_ref_clk_sync[0];
    wire ela_trigger = eth_tx_en_rise;

    wire [31:0] ela_probe = {
        heartbeat[7:0],
        eth_ref_clk_edge,
        eth_tx_clk_edge,
        eth_tx_en_rise,
        dma_rx_axis_tvalid,
        mac_rx_axis_tvalid,
        eth_rstn_sync[1],
        eth_ref_clk_sync[1],
        eth_tx_clk_sync[1],
        eth_tx_en_sync[1],
        eth_txd_sync,
        heartbeat[7:0]
    };

    fcapz_ela_xilinx7 #(
        .SAMPLE_W(32),
        .DEPTH(ELA_DEPTH),
        .TRIG_STAGES(1),
        .INPUT_PIPE(1),
        .TIMESTAMP_W(0),
        .CTRL_CHAIN(1),
        .SINGLE_CHAIN_BURST(1),
        .BURST_EN(1),
        .EIO_EN(1),
        .EIO_IN_W(8),
        .EIO_OUT_W(1)
    ) u_ela (
        .sample_clk(clk),
        .sample_rst(rst),
        .probe_in(ela_probe),
        .trigger_in(ela_trigger),
        .trigger_out(),
        .armed_out(),
        .eio_probe_in({
            3'b000,
            phy_rstn,
            peripheral_reset,
            mb_reset,
            debug_reset_req,
            eio_reset_req_jtag
        }),
        .eio_probe_out(eio_reset_req_jtag)
    );

endmodule
