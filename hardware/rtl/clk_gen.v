// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
// =============================================================================
// clk_gen.v - Arty A7 25 MHz Ethernet clock from the DDR MIG ui_clk
//
// Parent-project copy of the board-specific clock generator. The upstream
// emacZero submodule keeps its standalone Arty clock generator tied to the
// 100 MHz board oscillator; this repo's DDR design can use the MIG ui_clk
// variant when a top-level integration needs that clocking relationship.
// =============================================================================

module clk_gen (
    input  wire clk_in,      // MIG ui_clk, about 81.25 MHz
    output wire clk_25,      // 25 MHz output
    output wire locked       // MMCM lock indicator
);

    wire clk_25_buf;
    wire clkfb;
    wire clkfb_buf;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (12.0),
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (12.308),
        .CLKOUT0_DIVIDE_F   (39.0),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT0_DUTY_CYCLE (0.5),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKIN1    (clk_in),
        .CLKFBIN   (clkfb_buf),
        .CLKFBOUT  (clkfb),
        .CLKOUT0   (clk_25_buf),
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
        .I(clk_25_buf),
        .O(clk_25)
    );

endmodule
