// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
// =============================================================================
// clock_root_100m.v - Board oscillator root for DDR and Ethernet clocks
// =============================================================================

module clock_root_100m (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_in CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 100000000" *)
    input  wire clk_in,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk100 CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 100000000" *)
    output wire clk100,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk25 CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 25000000" *)
    output wire clk25,
    output wire locked
);

    wire clk_ibuf;
    wire clk25_mmcm;
    wire clkfb;
    wire clkfb_buf;

    IBUFG u_ibuf (
        .I(clk_in),
        .O(clk_ibuf)
    );

    BUFG u_bufg_100 (
        .I(clk_ibuf),
        .O(clk100)
    );

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (10.0),
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (10.000),
        .CLKOUT0_DIVIDE_F   (40.0),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT0_DUTY_CYCLE (0.5),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKIN1    (clk_ibuf),
        .CLKFBIN   (clkfb_buf),
        .CLKFBOUT  (clkfb),
        .CLKOUT0   (clk25_mmcm),
        .CLKOUT1   (),
        .CLKOUT2   (),
        .CLKOUT3   (),
        .CLKOUT4   (),
        .CLKOUT5   (),
        .CLKOUT6   (),
        .CLKFBOUTB (),
        .CLKOUT0B  (),
        .CLKOUT1B  (),
        .CLKOUT2B  (),
        .CLKOUT3B  (),
        .LOCKED    (locked),
        .PWRDWN    (1'b0),
        .RST       (1'b0)
    );

    BUFG u_bufg_fb (
        .I(clkfb),
        .O(clkfb_buf)
    );

    BUFG u_bufg_25 (
        .I(clk25_mmcm),
        .O(clk25)
    );

endmodule
