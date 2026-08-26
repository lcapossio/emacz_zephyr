// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
//
// Latched observations of CPU AXI behaviour, presented as a 32-bit status
// word for the host to poll via axi_gpio.

`default_nettype none

module cpu_liveness_probe (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire        ibus_arvalid,
    input  wire        ibus_arready,
    input  wire        ibus_rvalid,
    input  wire        dbus_arvalid,
    input  wire        dbus_awvalid,
    input  wire        dbus_wvalid,
    input  wire        dbus_bvalid,

    input  wire [31:0] ibus_araddr,       // for last-fetched observability
    input  wire [31:0] dbus_awaddr,       // for last-store observability

    input  wire        reset_i,           // CPU-internal reset (~aresetn)

    output wire [31:0] status,
    output wire [31:0] last_ibus_araddr,  // last accepted IBUS fetch address
    output wire [31:0] last_dbus_awaddr   // last accepted DBUS write address
);

    reg ibus_ar_seen;
    reg ibus_arready_seen;
    reg ibus_r_seen;
    reg dbus_ar_seen;
    reg dbus_aw_seen;
    reg dbus_w_seen;
    reg dbus_b_seen;
    reg reset_seen;

    reg [15:0] ibus_ar_count;
    reg [31:0] last_ibus_araddr_r;
    reg [31:0] last_dbus_awaddr_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            ibus_ar_seen       <= 1'b0;
            ibus_arready_seen  <= 1'b0;
            ibus_r_seen        <= 1'b0;
            dbus_ar_seen       <= 1'b0;
            dbus_aw_seen       <= 1'b0;
            dbus_w_seen        <= 1'b0;
            dbus_b_seen        <= 1'b0;
            reset_seen         <= 1'b0;
            ibus_ar_count      <= 16'd0;
            last_ibus_araddr_r <= 32'hdeadbeef;
            last_dbus_awaddr_r <= 32'hdeadbeef;
        end else begin
            if (reset_i)                       reset_seen        <= 1'b1;
            if (ibus_arvalid)                  ibus_ar_seen      <= 1'b1;
            if (ibus_arvalid && ibus_arready)  ibus_arready_seen <= 1'b1;
            if (ibus_rvalid)                   ibus_r_seen       <= 1'b1;
            if (dbus_arvalid)                  dbus_ar_seen      <= 1'b1;
            if (dbus_awvalid)                  dbus_aw_seen      <= 1'b1;
            if (dbus_wvalid)                   dbus_w_seen       <= 1'b1;
            if (dbus_bvalid)                   dbus_b_seen       <= 1'b1;
            if (ibus_arvalid && ibus_arready) begin
                ibus_ar_count      <= ibus_ar_count + 16'd1;
                last_ibus_araddr_r <= ibus_araddr;
            end
            if (dbus_awvalid)
                last_dbus_awaddr_r <= dbus_awaddr;
        end
    end

    assign last_ibus_araddr = last_ibus_araddr_r;
    assign last_dbus_awaddr = last_dbus_awaddr_r;

    assign status = {
        ibus_ar_count,        // [31:16] handshake count
        7'd0,                 // [15:9]  reserved
        reset_seen,           // [8]     reset ever high (async)
        1'b0,                 // [7]     reserved
        dbus_b_seen,          // [6]
        dbus_w_seen,          // [5]
        dbus_aw_seen,         // [4]
        dbus_ar_seen,         // [3]
        ibus_r_seen,          // [2]
        ibus_arready_seen,    // [1]
        ibus_ar_seen          // [0]
    };

endmodule

`default_nettype wire
