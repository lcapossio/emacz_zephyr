// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
// =============================================================================
// emaczero_axi_gmii_wrapper.v - emacZero AXI-Lite/GMII wrapper (1000BASE-X)
//
// The GMII sibling of emaczero_axi_mii_wrapper.v, for boards where emacZero
// sits behind the AMD 1G/2.5G Ethernet PCS/PMA core (ZCU106 SFP0). The CPU
// side is the same: emacZero CSRs at 0x000-0x0FF, the wrapper's RX gate
// counters at 0x100-0x13F (ERZG) and TX store-and-forward counters at
// 0x1C0-0x1D7 (TXCF), and the same AXI-Stream TX/RX pair for an AXI DMA. The
// MII wrapper's MII capture words read as zero there, and are not present here.
//
// Clocks: eth_mac_sys runs on clk, which must be at least 125 MHz in GMII mode
// (it moves one byte per clk). gmii_clk is the PCS/PMA userclk2 (125 MHz); the
// MAC's own gmii_cdc crosses between the two. Keeping the CSRs on clk means
// the CPU can read them even while the transceiver is still in reset.
// Verilog 2001
// =============================================================================

module emaczero_axi_gmii_wrapper #(
    // Frequency of clk in Hz; at least 125 MHz (eth_mac_sys checks)
    parameter CLK_FREQ_HZ = 150_000_000
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI:S_AXIS:M_AXIS, ASSOCIATED_RESET rst_n" *)
    input  wire        clk,
    input  wire        rst_n,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 gmii_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 125000000" *)
    input  wire        gmii_clk,

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
    output wire        m_axis_tlast,

    // GMII to the PCS/PMA core, synchronous to gmii_clk
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 GMII TXD" *)
    output wire [7:0]  gmii_txd,
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 GMII TX_EN" *)
    output wire        gmii_tx_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 GMII TX_ER" *)
    output wire        gmii_tx_er,
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 GMII RXD" *)
    input  wire [7:0]  gmii_rxd,
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 GMII RX_DV" *)
    input  wire        gmii_rx_dv,
    (* X_INTERFACE_INFO = "xilinx.com:interface:gmii_rtl:1.0 GMII RX_ER" *)
    input  wire        gmii_rx_er,

    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq INTERRUPT" *)
    (* X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *)
    output wire        irq
);

    // ---------------------------------------------------------------------
    // TX store-and-forward: hold each DMA frame until its tlast arrives, so
    // a DMA stall cannot underrun eth_mac_tx mid-frame.
    // ---------------------------------------------------------------------
    wire [7:0]  mac_tx_tdata;
    wire        mac_tx_tvalid;
    wire        mac_tx_tready;
    wire        mac_tx_tlast;
    wire [31:0] tx_sf_frames_committed;
    wire [31:0] tx_sf_frames_drained;
    wire [11:0] tx_sf_data_level;
    wire [3:0]  tx_sf_frames_pending;

    axis_store_forward #(
        .DATA_FIFO_ADDR_WIDTH(12),
        .FRAME_COUNT_WIDTH(4)
    ) u_tx_sf (
        .clk                  (clk),
        .rst_n                (rst_n),
        .s_axis_tdata         (s_axis_tdata),
        .s_axis_tvalid        (s_axis_tvalid),
        .s_axis_tready        (s_axis_tready),
        .s_axis_tlast         (s_axis_tlast),
        .m_axis_tdata         (mac_tx_tdata),
        .m_axis_tvalid        (mac_tx_tvalid),
        .m_axis_tready        (mac_tx_tready),
        .m_axis_tlast         (mac_tx_tlast),
        .dbg_frames_committed (tx_sf_frames_committed),
        .dbg_frames_drained   (tx_sf_frames_drained),
        .dbg_data_level       (tx_sf_data_level),
        .dbg_frames_pending   (tx_sf_frames_pending)
    );

    // ---------------------------------------------------------------------
    // CSR read mux: 0x100-0x1FF is the wrapper's page, the rest is emacZero
    // ---------------------------------------------------------------------
    wire [31:0] rx_error_drop_good_frames;
    wire [31:0] rx_error_drop_bad_frames;
    wire [31:0] rx_error_drop_overflow_frames;
    wire [31:0] rx_error_drop_drain_samples;
    wire [31:0] rx_error_drop_drain_cycles_total;
    wire [31:0] rx_error_drop_drain_cycles_max;
    wire [31:0] rx_error_drop_drain_lt_50us;
    wire [31:0] rx_error_drop_drain_50_100us;
    wire [31:0] rx_error_drop_drain_100_200us;
    wire [31:0] rx_error_drop_drain_200_500us;
    wire [31:0] rx_error_drop_drain_ge_500us;
    wire [31:0] rx_error_drop_drain_tready_low_cycles;
    wire [31:0] rx_error_drop_drain_tready_low_cycles_max;
    wire [31:0] rx_error_drop_drain_tready_low_samples;

    wire        gate_csr_sel = (s_axi_araddr[11:8] == 4'h1);
    reg         gate_rvalid;
    reg  [31:0] gate_rdata;

    wire        mac_s_axi_arvalid = s_axi_arvalid & ~gate_csr_sel;
    wire        mac_s_axi_arready;
    wire [31:0] mac_s_axi_rdata;
    wire [1:0]  mac_s_axi_rresp;
    wire        mac_s_axi_rvalid;

    assign s_axi_arready = gate_csr_sel ? !gate_rvalid : mac_s_axi_arready;
    assign s_axi_rdata   = gate_rvalid ? gate_rdata : mac_s_axi_rdata;
    assign s_axi_rresp   = gate_rvalid ? 2'b00 : mac_s_axi_rresp;
    assign s_axi_rvalid  = gate_rvalid | mac_s_axi_rvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate_rvalid <= 1'b0;
            gate_rdata  <= 32'd0;
        end else begin
            if (gate_rvalid && s_axi_rready) begin
                gate_rvalid <= 1'b0;
            end

            if (s_axi_arvalid && gate_csr_sel && !gate_rvalid) begin
                gate_rvalid <= 1'b1;
                case (s_axi_araddr[7:0])
                    8'h00: gate_rdata <= 32'h45525a47; // "ERZG"
                    8'h04: gate_rdata <= rx_error_drop_good_frames;
                    8'h08: gate_rdata <= rx_error_drop_bad_frames;
                    8'h0c: gate_rdata <= rx_error_drop_overflow_frames;
                    8'h10: gate_rdata <= rx_error_drop_drain_samples;
                    8'h14: gate_rdata <= rx_error_drop_drain_cycles_total;
                    8'h18: gate_rdata <= rx_error_drop_drain_cycles_max;
                    8'h1c: gate_rdata <= rx_error_drop_drain_lt_50us;
                    8'h20: gate_rdata <= rx_error_drop_drain_50_100us;
                    8'h24: gate_rdata <= rx_error_drop_drain_100_200us;
                    8'h28: gate_rdata <= rx_error_drop_drain_200_500us;
                    8'h2c: gate_rdata <= rx_error_drop_drain_ge_500us;
                    8'h30: gate_rdata <= rx_error_drop_drain_tready_low_cycles;
                    8'h34: gate_rdata <= rx_error_drop_drain_tready_low_cycles_max;
                    8'h38: gate_rdata <= rx_error_drop_drain_tready_low_samples;
                    8'hc0: gate_rdata <= 32'h54584346; // "TXCF"
                    8'hc4: gate_rdata <= tx_sf_frames_committed;
                    8'hc8: gate_rdata <= tx_sf_frames_drained;
                    8'hcc: gate_rdata <= {16'd0, 4'd0, tx_sf_frames_pending, tx_sf_data_level};
                    default: gate_rdata <= 32'd0;
                endcase
            end
        end
    end

    // ---------------------------------------------------------------------
    // MAC: GMII mode, standard MTU (the RX gate below holds 2 KiB frames)
    // ---------------------------------------------------------------------
    wire [7:0] mac_rx_tdata;
    wire       mac_rx_tvalid;
    wire       mac_rx_tready;
    wire       mac_rx_tlast;
    wire       mac_rx_terror;
    wire       mac_rx_tsof;

    eth_mac_sys #(
        .PHY_INTERFACE("GMII"),
        .MAX_FRAME(1518),
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_mac (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awaddr   (s_axi_awaddr[7:0]),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr[7:0]),
        .s_axi_arvalid  (mac_s_axi_arvalid),
        .s_axi_arready  (mac_s_axi_arready),
        .s_axi_rdata    (mac_s_axi_rdata),
        .s_axi_rresp    (mac_s_axi_rresp),
        .s_axi_rvalid   (mac_s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .s_axis_tdata   (mac_tx_tdata),
        .s_axis_tvalid  (mac_tx_tvalid),
        .s_axis_tready  (mac_tx_tready),
        .s_axis_tlast   (mac_tx_tlast),
        .m_axis_tdata   (mac_rx_tdata),
        .m_axis_tvalid  (mac_rx_tvalid),
        .m_axis_tready  (mac_rx_tready),
        .m_axis_tlast   (mac_rx_tlast),
        .m_axis_terror  (mac_rx_terror),
        .m_axis_tsof    (mac_rx_tsof),
        // MII unused
        .mii_txd        (),
        .mii_tx_en      (),
        .mii_tx_clk     (1'b0),
        .mii_rxd        (4'd0),
        .mii_rx_dv      (1'b0),
        .mii_rx_er      (1'b0),
        .mii_rx_clk     (1'b0),
        .mii_col        (1'b0),
        .mii_crs        (1'b0),
        // GMII TX clock is the RGMII group's clk_125; the rest is RGMII-only
        .clk_125        (gmii_clk),
        .clk_125_90     (1'b0),
        .clk_25         (1'b0),
        .clk_2_5        (1'b0),
        .rgmii_txd      (),
        .rgmii_tx_ctl   (),
        .rgmii_txc      (),
        .rgmii_rxd      (4'd0),
        .rgmii_rx_ctl   (1'b0),
        .rgmii_rxc      (1'b0),
        // The PCS/PMA is clocked by userclk2 in both directions; the
        // forwarded TX clock is for an external PHY and stays open.
        .phy_gmii_txd    (gmii_txd),
        .phy_gmii_tx_en  (gmii_tx_en),
        .phy_gmii_tx_er  (gmii_tx_er),
        .phy_gmii_txc    (),
        .phy_gmii_rx_clk (gmii_clk),
        .phy_gmii_rxd    (gmii_rxd),
        .phy_gmii_rx_dv  (gmii_rx_dv),
        .phy_gmii_rx_er  (gmii_rx_er),
        // 1000BASE-X has no external PHY to manage
        .mdc            (),
        .mdio_i         (1'b1),
        .mdio_o         (),
        .mdio_oe        (),
        .cfg_ip_addr    (),
        .irq            (irq)
    );

    // ---------------------------------------------------------------------
    // RX: drop errored frames, then an elastic FIFO toward the DMA
    // ---------------------------------------------------------------------
    wire [7:0] gate_dma_tdata;
    wire       gate_dma_tvalid;
    wire       gate_dma_tready;
    wire       gate_dma_tlast;
    wire       gate_dma_terror;
    wire       gate_dma_tsof;

    axis_frame_error_drop #(
        .ADDR_WIDTH(11),
        .SLOT_COUNT(4)
    ) u_rx_error_drop (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .s_axis_tdata            (mac_rx_tdata),
        .s_axis_tvalid           (mac_rx_tvalid),
        .s_axis_tready           (mac_rx_tready),
        .s_axis_tlast            (mac_rx_tlast),
        .s_axis_terror           (mac_rx_terror),
        .s_axis_tsof             (mac_rx_tsof),
        .m_axis_tdata            (gate_dma_tdata),
        .m_axis_tvalid           (gate_dma_tvalid),
        .m_axis_tready           (gate_dma_tready),
        .m_axis_tlast            (gate_dma_tlast),
        .m_axis_terror           (gate_dma_terror),
        .m_axis_tsof             (gate_dma_tsof),
        .good_frames             (rx_error_drop_good_frames),
        .dropped_bad_frames      (rx_error_drop_bad_frames),
        .dropped_overflow_frames (rx_error_drop_overflow_frames),
        .drain_samples           (rx_error_drop_drain_samples),
        .drain_cycles_total      (rx_error_drop_drain_cycles_total),
        .drain_cycles_max        (rx_error_drop_drain_cycles_max),
        .drain_lt_50us           (rx_error_drop_drain_lt_50us),
        .drain_50_100us          (rx_error_drop_drain_50_100us),
        .drain_100_200us         (rx_error_drop_drain_100_200us),
        .drain_200_500us         (rx_error_drop_drain_200_500us),
        .drain_ge_500us          (rx_error_drop_drain_ge_500us),
        .drain_tready_low_cycles (rx_error_drop_drain_tready_low_cycles),
        .drain_tready_low_cycles_max (rx_error_drop_drain_tready_low_cycles_max),
        .drain_tready_low_samples (rx_error_drop_drain_tready_low_samples)
    );

    axis_elastic_fifo #(
        .ADDR_WIDTH(12)
    ) u_rx_dma_elastic_fifo (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axis_tdata  (gate_dma_tdata),
        .s_axis_tvalid (gate_dma_tvalid),
        .s_axis_tready (gate_dma_tready),
        .s_axis_tlast  (gate_dma_tlast),
        .s_axis_terror (gate_dma_terror),
        .s_axis_tsof   (gate_dma_tsof),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tlast  (m_axis_tlast),
        .m_axis_terror (),
        .m_axis_tsof   ()
    );

endmodule
