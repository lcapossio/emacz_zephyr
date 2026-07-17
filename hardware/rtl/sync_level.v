// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
// =============================================================================
// sync_level.v - Two-flop level synchronizer
// =============================================================================

module sync_level (
    input  wire clk,
    input  wire rst_n,
    input  wire din,
    output wire dout
);

    (* ASYNC_REG = "TRUE" *) reg sync_0;
    (* ASYNC_REG = "TRUE" *) reg sync_1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_0 <= 1'b0;
            sync_1 <= 1'b0;
        end else begin
            sync_0 <= din;
            sync_1 <= sync_0;
        end
    end

    assign dout = sync_1;

endmodule
