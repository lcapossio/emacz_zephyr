// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
// =============================================================================
// sfp_pcs_ctrl.v - Bring-up and status for a 1000BASE-X PCS/PMA core on SFP
//
// Sits beside the AMD 1G/2.5G Ethernet PCS/PMA core (shared logic in core)
// and does what emacZero's fpga/zcu106 top does around it:
//   - holds the core in reset after configuration, then pulses its reset for
//     1 ms every 2 s until the transceiver reports reset done (the reference
//     clock may still be settling);
//   - drives the static configuration: auto-negotiation on unless an_disable
//     is high, a full-duplex 1000BASE-X base page without PAUSE, the SFP
//     laser on;
//   - collects the core's status for an AXI GPIO, and drives four LEDs.
//
// Runs on the core's independent clock (clk, 50 MHz). status_vector comes from
// userclk2 and the transceiver flags are asynchronous; each bit is
// synchronized here or by the AXI GPIO's input stage, and each is meaningful
// on its own.
// Verilog 2001
// =============================================================================

module sfp_pcs_ctrl #(
    parameter CLK_HZ = 50_000_000
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst" *)
    input  wire        clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input  wire        rst,

    // From the PCS/PMA core
    input  wire        gt_resetdone,
    input  wire        gt_mmcm_locked,
    input  wire        pma_reset_out,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 userclk2 CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 125000000" *)
    input  wire        userclk2,
    input  wire [15:0] status_vector,

    // Board strap: high turns auto-negotiation off
    input  wire        an_disable,

    // To the PCS/PMA core
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 pcs_reset RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output reg         pcs_reset,
    output wire [4:0]  configuration_vector,
    output wire [15:0] an_adv_config_vector,
    output wire        an_restart_config,
    output wire        signal_detect,
    output wire        sfp_tx_disable_b,

    // [15:0] status_vector, [16] GT reset done, [17] GT MMCM locked,
    // [18] PMA in reset, [19] auto-negotiation disabled
    output wire [31:0] status,
    // [0] GT reset done, [1] PCS sync, [2] link up, [3] userclk2 heartbeat
    output wire [3:0]  led
);

    localparam integer WD_PERIOD   = 2 * CLK_HZ;    // 2 s
    localparam integer RESET_PULSE = CLK_HZ / 1000; // 1 ms

    (* ASYNC_REG = "TRUE" *) reg [2:0] rst_sync;
    always @(posedge clk or posedge rst) begin
        if (rst) rst_sync <= 3'b000;
        else     rst_sync <= {rst_sync[1:0], 1'b1};
    end
    wire rst_n = rst_sync[2];

    (* ASYNC_REG = "TRUE" *) reg [2:0] done_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] an_dis_sync;
    always @(posedge clk) begin
        done_sync   <= {done_sync[1:0], gt_resetdone};
        an_dis_sync <= {an_dis_sync[0], an_disable};
    end

    reg [31:0] wd_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wd_cnt    <= 32'd0;
            pcs_reset <= 1'b1;
        end else if (done_sync[2]) begin
            wd_cnt    <= 32'd0;
            pcs_reset <= 1'b0;
        end else begin
            wd_cnt    <= (wd_cnt == WD_PERIOD - 1) ? 32'd0 : wd_cnt + 32'd1;
            pcs_reset <= (wd_cnt < RESET_PULSE);
        end
    end

    // The core samples configuration_vector on userclk2; the strap is static
    // and synchronized above, so a change lands as one clean level change.
    // [4] AN enable, [3] isolate, [2] powerdown, [1] loopback, [0] unidir
    assign configuration_vector = {~an_dis_sync[1], 4'b0000};
    // 1000BASE-X base page: full duplex only, no PAUSE advertised
    assign an_adv_config_vector = 16'h0020;
    assign an_restart_config    = 1'b0;
    // An SFP's LOS is not wired to the fabric on this board; the PCS
    // synchronization state machine tells signal from noise on its own.
    assign signal_detect        = 1'b1;
    assign sfp_tx_disable_b     = 1'b1;

    assign status = {12'd0, an_dis_sync[1], pma_reset_out, gt_mmcm_locked,
                     gt_resetdone, status_vector};

    reg [26:0] heartbeat = 27'd0;
    always @(posedge userclk2) heartbeat <= heartbeat + 27'd1;

    assign led = {heartbeat[26], status_vector[0], status_vector[1], done_sync[2]};

endmodule
