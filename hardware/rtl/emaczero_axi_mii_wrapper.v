// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
// =============================================================================
// emaczero_axi_mii_wrapper.v - Arty A7 emacZero AXI-Lite/MII wrapper
//
// This wrapper keeps the vendor-specific FPGA shell boundary outside the
// Zephyr driver. MicroBlaze V accesses the emacZero CSR aperture over AXI-Lite;
// packet AXI-Stream TX/RX is exposed for an external DMA or stream adapter.
// =============================================================================

module emaczero_axi_mii_wrapper #(
    parameter MII_DEBUG = 1
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 100000000, ASSOCIATED_BUSIF S_AXI:S_AXIS:M_AXIS, ASSOCIATED_RESET rst_n" *)
    input  wire        clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 phy_ref_clk_25 CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 25000000" *)
    input  wire        phy_ref_clk_25,
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
    output wire        m_axis_tlast,
    output wire        m_axis_terror,
    output wire        m_axis_tsof,

    output wire [3:0]  eth_txd,
    output wire        eth_tx_en,
    input  wire        eth_tx_clk,
    input  wire [3:0]  eth_rxd,
    input  wire        eth_rx_dv,
    input  wire        eth_rxerr,
    input  wire        eth_rx_clk,
    input  wire        eth_crs,
    input  wire        eth_col,
    output wire        eth_mdc,
    inout  wire        eth_mdio,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 eth_ref_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 25000000" *)
    output wire        eth_ref_clk,
    output wire        eth_rstn,

    output wire        irq,

    output wire [7:0]  dbg_mac_rx_tdata,
    output wire        dbg_mac_rx_tvalid,
    output wire        dbg_mac_rx_tready,
    output wire        dbg_mac_rx_tlast,
    output wire        dbg_mac_rx_tsof,
    output wire        dbg_mac_rx_terror,
    output wire [7:0]  dbg_dma_rx_tdata,
    output wire        dbg_dma_rx_tvalid,
    output wire        dbg_dma_rx_tready,
    output wire        dbg_dma_rx_tlast,
    output wire        dbg_dma_rx_tsof,
    output wire        dbg_dma_rx_terror,
    output wire [3:0]  dbg_mii_txd_pre_iob,
    output wire        dbg_mii_tx_en_pre_iob
);

    // Upstream eth_mac_sys no longer exposes pre-IOB MII TX taps; keep the
    // wrapper's debug ELA output ports at logical 0. Vivado's ELA probe still
    // sees a driven net; the observable path is now inside emacZero itself.
    assign dbg_mii_txd_pre_iob   = 4'd0;
    assign dbg_mii_tx_en_pre_iob = 1'b0;

    ddr_output u_ref_clk (
        .clk (phy_ref_clk_25),
        .d1  (1'b1),
        .d2  (1'b0),
        .q   (eth_ref_clk)
    );

    // Hold DP83848 reset low for 200 ms after the Ethernet clock is running.
    localparam PHY_RST_CYCLES = 25'd20_000_000;
    reg [24:0] phy_rst_cnt;
    reg        phy_rst_done;

    always @(posedge clk) begin
        if (!rst_n) begin
            phy_rst_cnt  <= 25'd0;
            phy_rst_done <= 1'b0;
        end else if (phy_rst_cnt < PHY_RST_CYCLES) begin
            phy_rst_cnt <= phy_rst_cnt + 25'd1;
        end else begin
            phy_rst_done <= 1'b1;
        end
    end

    assign eth_rstn = phy_rst_done;

    wire mac_rst_n = rst_n;

    wire mdio_i;
    wire mdio_o;
    wire mdio_oe;
    assign eth_mdio = mdio_oe ? mdio_o : 1'bz;
    assign mdio_i = eth_mdio;

    wire [7:0] mac_rx_tdata;
    wire       mac_rx_tvalid;
    wire       mac_rx_tready;
    wire       mac_rx_tlast;
    wire       mac_rx_terror;
    wire       mac_rx_tsof;
    wire [7:0] gate_dma_tdata;
    wire       gate_dma_tvalid;
    wire       gate_dma_tready;
    wire       gate_dma_tlast;
    wire       gate_dma_terror;
    wire       gate_dma_tsof;
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
    // Upstream eth_mac_sys no longer exports these dbg_* observability ports;
    // the wrapper keeps its debug CSR pages read-safe by tying the read-side
    // wires to zero. Runtime observability now lives in emacZero's own
    // AXI-Lite CSRs (IP_ADDR / SAF_DBG).
    wire [31:0] mii_rx_fifo_full_frames        = 32'd0;
    wire [31:0] mii_rx_fifo_full_writes        = 32'd0;
    wire [31:0] mii_rx_fifo_overflow_pulses    = 32'd0;
    wire [31:0] mii_rx_fifo_wr_level_max       = 32'd0;
    wire [31:0] mii_rx_replay_gap_frames       = 32'd0;
    wire [31:0] mii_rx_replay_gap_cycles       = 32'd0;
    wire [31:0] mii_rx_replay_gap_byte_max     = 32'd0;
    wire [31:0] mii_rx_last_len                = 32'd0;
    wire [31:0] mii_rx_word0                   = 32'd0;
    wire [31:0] mii_rx_word1                   = 32'd0;
    wire [31:0] mii_rx_word2                   = 32'd0;
    wire [31:0] mii_rx_word3                   = 32'd0;
    wire [31:0] mii_rx_replay_last_len         = 32'd0;
    wire [31:0] mii_rx_replay_word0            = 32'd0;
    wire [31:0] mii_rx_replay_word1            = 32'd0;
    wire [31:0] mii_rx_replay_word2            = 32'd0;
    wire [31:0] mii_rx_replay_word3            = 32'd0;
    wire [31:0] mii_rx_replay_eof_count        = 32'd0;
    wire [31:0] mac_rx_last_len                = 32'd0;
    wire [31:0] mac_rx_last_flags              = 32'd0;
    wire [31:0] mac_rx_stat_count              = 32'd0;
    wire [31:0] tx_mii_status                  = 32'd0;
    wire [31:0] tx_mii_counts                  = 32'd0;
    wire [31:0] tx_mii_cap_len                 = 32'd0;
    wire [31:0] tx_mii_cap_word0               = 32'd0;
    wire [31:0] tx_mii_cap_word1               = 32'd0;
    wire [31:0] tx_mii_cap_word2               = 32'd0;
    wire [31:0] tx_mii_cap_word3               = 32'd0;
    wire [31:0] tx_er_pulses                   = 32'd0;
    wire [31:0] tx_er_frames                   = 32'd0;
    wire [31:0] tx_sf_frames_committed;
    wire [31:0] tx_sf_frames_drained;
    wire [11:0] tx_sf_data_level;
    wire [3:0]  tx_sf_frames_pending;
    wire [31:0] tx_mii_cap_word4  = 32'd0, tx_mii_cap_word5  = 32'd0,
                tx_mii_cap_word6  = 32'd0, tx_mii_cap_word7  = 32'd0;
    wire [31:0] tx_mii_cap_word8  = 32'd0, tx_mii_cap_word9  = 32'd0,
                tx_mii_cap_word10 = 32'd0, tx_mii_cap_word11 = 32'd0;
    wire [31:0] tx_mii_cap_word12 = 32'd0, tx_mii_cap_word13 = 32'd0,
                tx_mii_cap_word14 = 32'd0, tx_mii_cap_word15 = 32'd0;
    wire [31:0] mii_rx_word4      = 32'd0, mii_rx_word5      = 32'd0,
                mii_rx_word6      = 32'd0, mii_rx_word7      = 32'd0;
    wire [31:0] mii_rx_word8      = 32'd0, mii_rx_word9      = 32'd0,
                mii_rx_word10     = 32'd0, mii_rx_word11     = 32'd0;
    wire [31:0] mii_rx_word12     = 32'd0, mii_rx_word13     = 32'd0,
                mii_rx_word14     = 32'd0, mii_rx_word15     = 32'd0;

    // Gate region 0x100-0x1FF holds the original CSRs; region 0x200-0x2FF holds
    // the extended 64-byte capture words (bytes 16-63).
    wire        gate_csr_sel = (s_axi_araddr[11:8] == 4'h1)
                            || (s_axi_araddr[11:8] == 4'h2);
    wire        gate_ext_sel = (s_axi_araddr[11:8] == 4'h2);
    reg         gate_rvalid;
    reg  [31:0] gate_rdata;

    wire        mac_s_axi_arvalid = s_axi_arvalid & ~gate_csr_sel;
    wire        mac_s_axi_arready;
    wire [31:0] mac_s_axi_rdata;
    wire [1:0]  mac_s_axi_rresp;
    wire        mac_s_axi_rvalid;

    assign s_axi_arready = gate_csr_sel ? !gate_rvalid : mac_s_axi_arready;
    assign s_axi_rdata = gate_rvalid ? gate_rdata : mac_s_axi_rdata;
    assign s_axi_rresp = gate_rvalid ? 2'b00 : mac_s_axi_rresp;
    assign s_axi_rvalid = gate_rvalid | mac_s_axi_rvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate_rvalid <= 1'b0;
            gate_rdata <= 32'd0;
        end else begin
            if (gate_rvalid && s_axi_rready) begin
                gate_rvalid <= 1'b0;
            end

            if (s_axi_arvalid && gate_csr_sel && !gate_rvalid) begin
                gate_rvalid <= 1'b1;
                if (gate_ext_sel) begin
                    // 0x200-0x2FF: extended TX/RX 64-byte captures (bytes 16-63)
                    case (s_axi_araddr[7:0])
                        8'h00: gate_rdata <= 32'h45585443; // "EXTC" extended-capture magic
                        8'h04: gate_rdata <= tx_mii_cap_word4;
                        8'h08: gate_rdata <= tx_mii_cap_word5;
                        8'h0c: gate_rdata <= tx_mii_cap_word6;
                        8'h10: gate_rdata <= tx_mii_cap_word7;
                        8'h14: gate_rdata <= tx_mii_cap_word8;
                        8'h18: gate_rdata <= tx_mii_cap_word9;
                        8'h1c: gate_rdata <= tx_mii_cap_word10;
                        8'h20: gate_rdata <= tx_mii_cap_word11;
                        8'h24: gate_rdata <= tx_mii_cap_word12;
                        8'h28: gate_rdata <= tx_mii_cap_word13;
                        8'h2c: gate_rdata <= tx_mii_cap_word14;
                        8'h30: gate_rdata <= tx_mii_cap_word15;
                        8'h40: gate_rdata <= 32'h52584558; // "RXEX" rx-extended magic
                        8'h44: gate_rdata <= mii_rx_word4;
                        8'h48: gate_rdata <= mii_rx_word5;
                        8'h4c: gate_rdata <= mii_rx_word6;
                        8'h50: gate_rdata <= mii_rx_word7;
                        8'h54: gate_rdata <= mii_rx_word8;
                        8'h58: gate_rdata <= mii_rx_word9;
                        8'h5c: gate_rdata <= mii_rx_word10;
                        8'h60: gate_rdata <= mii_rx_word11;
                        8'h64: gate_rdata <= mii_rx_word12;
                        8'h68: gate_rdata <= mii_rx_word13;
                        8'h6c: gate_rdata <= mii_rx_word14;
                        8'h70: gate_rdata <= mii_rx_word15;
                        default: gate_rdata <= 32'd0;
                    endcase
                end else
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
                    8'h40: gate_rdata <= mii_rx_fifo_full_frames;
                    8'h44: gate_rdata <= mii_rx_fifo_full_writes;
                    8'h48: gate_rdata <= mii_rx_fifo_overflow_pulses;
                    8'h4c: gate_rdata <= mii_rx_fifo_wr_level_max;
                    8'h50: gate_rdata <= mii_rx_replay_gap_frames;
                    8'h54: gate_rdata <= mii_rx_replay_gap_cycles;
                    8'h58: gate_rdata <= mii_rx_replay_gap_byte_max;
                    8'h60: gate_rdata <= 32'h46524d58; // "FRMX"
                    8'h64: gate_rdata <= mii_rx_last_len;
                    8'h68: gate_rdata <= mii_rx_word0;
                    8'h6c: gate_rdata <= mii_rx_word1;
                    8'h70: gate_rdata <= mii_rx_word2;
                    8'h74: gate_rdata <= mii_rx_word3;
                    8'h78: gate_rdata <= mii_rx_replay_last_len;
                    8'h7c: gate_rdata <= mii_rx_replay_word0;
                    8'h80: gate_rdata <= mii_rx_replay_word1;
                    8'h84: gate_rdata <= mii_rx_replay_word2;
                    8'h88: gate_rdata <= mii_rx_replay_word3;
                    8'h8c: gate_rdata <= mii_rx_replay_eof_count;
                    8'h90: gate_rdata <= mac_rx_last_len;
                    8'h94: gate_rdata <= mac_rx_last_flags;
                    8'h98: gate_rdata <= mac_rx_stat_count;
                    8'ha0: gate_rdata <= 32'h54584d49; // "TXMI"
                    8'ha4: gate_rdata <= tx_mii_status;
                    8'ha8: gate_rdata <= tx_mii_counts;
                    8'hac: gate_rdata <= tx_mii_cap_len;
                    8'hb0: gate_rdata <= tx_mii_cap_word0;
                    8'hb4: gate_rdata <= tx_mii_cap_word1;
                    8'hb8: gate_rdata <= tx_mii_cap_word2;
                    8'hbc: gate_rdata <= tx_mii_cap_word3;
                    8'hc0: gate_rdata <= 32'h54584346; // "TXCF" tx store-forward + tx_er section
                    8'hc4: gate_rdata <= tx_sf_frames_committed;
                    8'hc8: gate_rdata <= tx_sf_frames_drained;
                    8'hcc: gate_rdata <= {16'd0, 4'd0, tx_sf_frames_pending, tx_sf_data_level};
                    8'hd0: gate_rdata <= tx_er_pulses;
                    8'hd4: gate_rdata <= tx_er_frames;
                    default: gate_rdata <= 32'd0;
                endcase
            end
        end
    end

    // ---------------------------------------------------------------------
    // Store-and-forward TX buffer
    //   Holds incoming DMA frames until tlast lands before exposing them to
    //   eth_mac_tx. Prevents mid-frame underrun (which otherwise aborts the
    //   MAC into S_IFG, drops gmii_tx_en without CRC, and ships a truncated
    //   bad-FCS frame to the PHY).
    // ---------------------------------------------------------------------
    wire [7:0] mac_tx_tdata;
    wire       mac_tx_tvalid;
    wire       mac_tx_tready;
    wire       mac_tx_tlast;

    axis_store_forward #(
        .DATA_FIFO_ADDR_WIDTH(12),
        .FRAME_COUNT_WIDTH(4)
    ) u_tx_sf (
        .clk                  (clk),
        .rst_n                (mac_rst_n),
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

    eth_mac_sys #(
        .PHY_INTERFACE("MII"),
        .MII_DEBUG(MII_DEBUG)
    ) u_mac (
        .clk            (clk),
        .rst_n          (mac_rst_n),
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
        .mii_txd        (eth_txd),
        .mii_tx_en      (eth_tx_en),
        .mii_tx_clk     (eth_tx_clk),
        .mii_rxd        (eth_rxd),
        .mii_rx_dv      (eth_rx_dv),
        .mii_rx_er      (eth_rxerr),
        .mii_rx_clk     (eth_rx_clk),
        .mii_col        (eth_col),
        .mii_crs        (eth_crs),
        .clk_125        (1'b0),
        .clk_125_90     (1'b0),
        .clk_25         (1'b0),
        .clk_2_5        (1'b0),
        .rgmii_txd      (),
        .rgmii_tx_ctl   (),
        .rgmii_txc      (),
        .rgmii_rxd      (4'd0),
        .rgmii_rx_ctl   (1'b0),
        .rgmii_rxc      (1'b0),
        .mdc            (eth_mdc),
        .mdio_i         (mdio_i),
        .mdio_o         (mdio_o),
        .mdio_oe        (mdio_oe),
        .irq            (irq)
    );

    axis_frame_error_drop #(
        .ADDR_WIDTH(11),
        .SLOT_COUNT(4)
    ) u_rx_error_drop (
        .clk                     (clk),
        .rst_n                   (mac_rst_n),
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
        .rst_n         (mac_rst_n),
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
        .m_axis_terror (m_axis_terror),
        .m_axis_tsof   (m_axis_tsof)
    );

    assign dbg_mac_rx_tdata   = mac_rx_tdata;
    assign dbg_mac_rx_tvalid  = mac_rx_tvalid;
    assign dbg_mac_rx_tready  = mac_rx_tready;
    assign dbg_mac_rx_tlast   = mac_rx_tlast;
    assign dbg_mac_rx_tsof    = mac_rx_tsof;
    assign dbg_mac_rx_terror  = mac_rx_terror;

    assign dbg_dma_rx_tdata   = m_axis_tdata;
    assign dbg_dma_rx_tvalid  = m_axis_tvalid;
    assign dbg_dma_rx_tready  = m_axis_tready;
    assign dbg_dma_rx_tlast   = m_axis_tlast;
    assign dbg_dma_rx_tsof    = m_axis_tsof;
    assign dbg_dma_rx_terror  = m_axis_terror;

endmodule
