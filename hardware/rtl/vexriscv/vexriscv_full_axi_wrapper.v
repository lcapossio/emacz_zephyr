// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
//
// Vivado-friendly wrapper around SpinalHDL's VexRiscvAxi4 (as emitted by
// external/VexRiscv/src/main/scala/vexriscv/demo/VexRiscvAxi4WithIntegratedJtag).
//
// Purpose: rename SpinalHDL AXI4 signal naming (dBusAxi_aw_payload_addr, ...)
// to the Xilinx/AMD convention (M_AXI_DBUS_awaddr, ...) so Vivado's Module
// Reference flow infers the AXI4 interfaces and SmartConnect can attach.
//
// JTAG is left tied off for now: fcapz USER3 owns the AXI fabric for memory
// loading and USER1 EIO drives CPU reset, so the SpinalHDL DebugPlugin is
// not wired to a live TAP. Rework once we want native VexRiscv debug via
// OpenOCD/BSCAN.

`default_nettype none

module vexriscv_full_axi_wrapper (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire        externalInterrupt,
    input  wire        timerInterrupt,

    // AXI4 read-only master: instruction fetch
    output wire        m_axi_ibus_arvalid,
    input  wire        m_axi_ibus_arready,
    output wire [31:0] m_axi_ibus_araddr,
    output wire [0:0]  m_axi_ibus_arid,
    output wire [3:0]  m_axi_ibus_arregion,
    output wire [7:0]  m_axi_ibus_arlen,
    output wire [2:0]  m_axi_ibus_arsize,
    output wire [1:0]  m_axi_ibus_arburst,
    output wire [0:0]  m_axi_ibus_arlock,
    output wire [3:0]  m_axi_ibus_arcache,
    output wire [3:0]  m_axi_ibus_arqos,
    output wire [2:0]  m_axi_ibus_arprot,
    input  wire        m_axi_ibus_rvalid,
    output wire        m_axi_ibus_rready,
    input  wire [31:0] m_axi_ibus_rdata,
    input  wire [0:0]  m_axi_ibus_rid,
    input  wire [1:0]  m_axi_ibus_rresp,
    input  wire        m_axi_ibus_rlast,

    // AXI4 full master: cached + uncached data
    output wire        m_axi_dbus_awvalid,
    input  wire        m_axi_dbus_awready,
    output wire [31:0] m_axi_dbus_awaddr,
    output wire [0:0]  m_axi_dbus_awid,
    output wire [3:0]  m_axi_dbus_awregion,
    output wire [7:0]  m_axi_dbus_awlen,
    output wire [2:0]  m_axi_dbus_awsize,
    output wire [1:0]  m_axi_dbus_awburst,
    output wire [0:0]  m_axi_dbus_awlock,
    output wire [3:0]  m_axi_dbus_awcache,
    output wire [3:0]  m_axi_dbus_awqos,
    output wire [2:0]  m_axi_dbus_awprot,
    output wire        m_axi_dbus_wvalid,
    input  wire        m_axi_dbus_wready,
    output wire [31:0] m_axi_dbus_wdata,
    output wire [3:0]  m_axi_dbus_wstrb,
    output wire        m_axi_dbus_wlast,
    input  wire        m_axi_dbus_bvalid,
    output wire        m_axi_dbus_bready,
    input  wire [0:0]  m_axi_dbus_bid,
    input  wire [1:0]  m_axi_dbus_bresp,
    output wire        m_axi_dbus_arvalid,
    input  wire        m_axi_dbus_arready,
    output wire [31:0] m_axi_dbus_araddr,
    output wire [0:0]  m_axi_dbus_arid,
    output wire [3:0]  m_axi_dbus_arregion,
    output wire [7:0]  m_axi_dbus_arlen,
    output wire [2:0]  m_axi_dbus_arsize,
    output wire [1:0]  m_axi_dbus_arburst,
    output wire [0:0]  m_axi_dbus_arlock,
    output wire [3:0]  m_axi_dbus_arcache,
    output wire [3:0]  m_axi_dbus_arqos,
    output wire [2:0]  m_axi_dbus_arprot,
    input  wire        m_axi_dbus_rvalid,
    output wire        m_axi_dbus_rready,
    input  wire [31:0] m_axi_dbus_rdata,
    input  wire [0:0]  m_axi_dbus_rid,
    input  wire [1:0]  m_axi_dbus_rresp,
    input  wire        m_axi_dbus_rlast,

    // Debug taps for cpu_liveness_probe — separate ports, do NOT belong to
    // any AXI interface, so wiring them in BD cannot hijack interface pins.
    output wire        dbg_ibus_arvalid,
    output wire        dbg_ibus_arready,
    output wire        dbg_ibus_rvalid,
    output wire        dbg_dbus_arvalid,
    output wire        dbg_dbus_awvalid,
    output wire        dbg_dbus_wvalid,
    output wire        dbg_dbus_bvalid,
    output wire [31:0] dbg_ibus_araddr,
    output wire [31:0] dbg_dbus_awaddr,
    output wire        dbg_reset_i
);

    wire reset_i = ~aresetn;

    assign dbg_ibus_arvalid = m_axi_ibus_arvalid;
    assign dbg_ibus_arready = m_axi_ibus_arready;
    assign dbg_ibus_rvalid  = m_axi_ibus_rvalid;
    assign dbg_dbus_arvalid = m_axi_dbus_arvalid;
    assign dbg_dbus_awvalid = m_axi_dbus_awvalid;
    assign dbg_dbus_wvalid  = m_axi_dbus_wvalid;
    assign dbg_dbus_bvalid  = m_axi_dbus_bvalid;
    assign dbg_ibus_araddr  = m_axi_ibus_araddr;
    assign dbg_dbus_awaddr  = m_axi_dbus_awaddr;
    assign dbg_reset_i      = reset_i;

    VexRiscvAxi4 u_cpu (
        .clk                        (aclk),
        .reset                      (reset_i),
        .debugReset                 (reset_i),
        .debug_resetOut             (/* unused */),

        .timerInterrupt             (timerInterrupt),
        .externalInterrupt          (externalInterrupt),

        // JTAG tied off; native VexRiscv debug not wired yet.
        .jtag_tms                   (1'b0),
        .jtag_tdi                   (1'b0),
        .jtag_tdo                   (/* unused */),
        .jtag_tck                   (1'b0),

        // iBusAxi -> m_axi_ibus
        .iBusAxi_ar_valid           (m_axi_ibus_arvalid),
        .iBusAxi_ar_ready           (m_axi_ibus_arready),
        .iBusAxi_ar_payload_addr    (m_axi_ibus_araddr),
        .iBusAxi_ar_payload_id      (m_axi_ibus_arid),
        .iBusAxi_ar_payload_region  (m_axi_ibus_arregion),
        .iBusAxi_ar_payload_len     (m_axi_ibus_arlen),
        .iBusAxi_ar_payload_size    (m_axi_ibus_arsize),
        .iBusAxi_ar_payload_burst   (m_axi_ibus_arburst),
        .iBusAxi_ar_payload_lock    (m_axi_ibus_arlock),
        .iBusAxi_ar_payload_cache   (m_axi_ibus_arcache),
        .iBusAxi_ar_payload_qos     (m_axi_ibus_arqos),
        .iBusAxi_ar_payload_prot    (m_axi_ibus_arprot),
        .iBusAxi_r_valid            (m_axi_ibus_rvalid),
        .iBusAxi_r_ready            (m_axi_ibus_rready),
        .iBusAxi_r_payload_data     (m_axi_ibus_rdata),
        .iBusAxi_r_payload_id       (m_axi_ibus_rid),
        .iBusAxi_r_payload_resp     (m_axi_ibus_rresp),
        .iBusAxi_r_payload_last     (m_axi_ibus_rlast),

        // dBusAxi -> m_axi_dbus
        .dBusAxi_aw_valid           (m_axi_dbus_awvalid),
        .dBusAxi_aw_ready           (m_axi_dbus_awready),
        .dBusAxi_aw_payload_addr    (m_axi_dbus_awaddr),
        .dBusAxi_aw_payload_id      (m_axi_dbus_awid),
        .dBusAxi_aw_payload_region  (m_axi_dbus_awregion),
        .dBusAxi_aw_payload_len     (m_axi_dbus_awlen),
        .dBusAxi_aw_payload_size    (m_axi_dbus_awsize),
        .dBusAxi_aw_payload_burst   (m_axi_dbus_awburst),
        .dBusAxi_aw_payload_lock    (m_axi_dbus_awlock),
        .dBusAxi_aw_payload_cache   (m_axi_dbus_awcache),
        .dBusAxi_aw_payload_qos     (m_axi_dbus_awqos),
        .dBusAxi_aw_payload_prot    (m_axi_dbus_awprot),
        .dBusAxi_w_valid            (m_axi_dbus_wvalid),
        .dBusAxi_w_ready            (m_axi_dbus_wready),
        .dBusAxi_w_payload_data     (m_axi_dbus_wdata),
        .dBusAxi_w_payload_strb     (m_axi_dbus_wstrb),
        .dBusAxi_w_payload_last     (m_axi_dbus_wlast),
        .dBusAxi_b_valid            (m_axi_dbus_bvalid),
        .dBusAxi_b_ready            (m_axi_dbus_bready),
        .dBusAxi_b_payload_id       (m_axi_dbus_bid),
        .dBusAxi_b_payload_resp     (m_axi_dbus_bresp),
        .dBusAxi_ar_valid           (m_axi_dbus_arvalid),
        .dBusAxi_ar_ready           (m_axi_dbus_arready),
        .dBusAxi_ar_payload_addr    (m_axi_dbus_araddr),
        .dBusAxi_ar_payload_id      (m_axi_dbus_arid),
        .dBusAxi_ar_payload_region  (m_axi_dbus_arregion),
        .dBusAxi_ar_payload_len     (m_axi_dbus_arlen),
        .dBusAxi_ar_payload_size    (m_axi_dbus_arsize),
        .dBusAxi_ar_payload_burst   (m_axi_dbus_arburst),
        .dBusAxi_ar_payload_lock    (m_axi_dbus_arlock),
        .dBusAxi_ar_payload_cache   (m_axi_dbus_arcache),
        .dBusAxi_ar_payload_qos     (m_axi_dbus_arqos),
        .dBusAxi_ar_payload_prot    (m_axi_dbus_arprot),
        .dBusAxi_r_valid            (m_axi_dbus_rvalid),
        .dBusAxi_r_ready            (m_axi_dbus_rready),
        .dBusAxi_r_payload_data     (m_axi_dbus_rdata),
        .dBusAxi_r_payload_id       (m_axi_dbus_rid),
        .dBusAxi_r_payload_resp     (m_axi_dbus_rresp),
        .dBusAxi_r_payload_last     (m_axi_dbus_rlast)
    );

endmodule

`default_nettype wire
