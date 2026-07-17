// SPDX-License-Identifier: Apache-2.0
// Author: Leonardo Capossio - bard0 design - 2026
// Elastic byte-wide AXI-stream FIFO for absorbing AXI DMA S2MM tready gaps.

module axis_elastic_fifo #(
    parameter ADDR_WIDTH = 12
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tvalid,
    output wire       s_axis_tready,
    input  wire       s_axis_tlast,
    input  wire       s_axis_terror,
    input  wire       s_axis_tsof,

    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tvalid,
    input  wire       m_axis_tready,
    output wire       m_axis_tlast,
    output wire       m_axis_terror,
    output wire       m_axis_tsof
);

    localparam DEPTH = (1 << ADDR_WIDTH);
    localparam [ADDR_WIDTH:0] DEPTH_COUNT = DEPTH;

    wire [10:0] fifo_din = {s_axis_tsof, s_axis_terror, s_axis_tlast, s_axis_tdata};
    wire [10:0] fifo_dout;
    wire        fifo_full;
    wire        fifo_empty;

`ifdef XILINX_7SERIES
    xpm_fifo_sync #(
        .CASCADE_HEIGHT(0),
        .DOUT_RESET_VALUE("0"),
        .ECC_MODE("no_ecc"),
        .FIFO_MEMORY_TYPE("block"),
        .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(DEPTH),
        .FULL_RESET_VALUE(0),
        .PROG_EMPTY_THRESH(10),
        .PROG_FULL_THRESH(DEPTH - 16),
        .RD_DATA_COUNT_WIDTH(ADDR_WIDTH + 1),
        .READ_DATA_WIDTH(11),
        .READ_MODE("fwft"),
        .SIM_ASSERT_CHK(0),
        .USE_ADV_FEATURES("0000"),
        .WAKEUP_TIME(0),
        .WRITE_DATA_WIDTH(11),
        .WR_DATA_COUNT_WIDTH(ADDR_WIDTH + 1)
    ) u_fifo (
        .sleep(1'b0),
        .rst(!rst_n),
        .wr_clk(clk),
        .wr_en(s_axis_tvalid && s_axis_tready),
        .din(fifo_din),
        .full(fifo_full),
        .overflow(),
        .wr_rst_busy(),
        .rd_en(m_axis_tvalid && m_axis_tready),
        .dout(fifo_dout),
        .empty(fifo_empty),
        .underflow(),
        .rd_rst_busy(),
        .prog_full(),
        .prog_empty(),
        .wr_data_count(),
        .rd_data_count(),
        .almost_full(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr()
    );
`else
    reg [10:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0] count;
    reg [10:0] fifo_dout_r;

    assign fifo_full = (count == DEPTH_COUNT);
    assign fifo_empty = (count == {ADDR_WIDTH+1{1'b0}});
    assign fifo_dout = fifo_dout_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            count <= {ADDR_WIDTH+1{1'b0}};
            fifo_dout_r <= 11'd0;
        end else begin
            if (s_axis_tvalid && s_axis_tready) begin
                mem[wr_ptr] <= fifo_din;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (m_axis_tvalid && m_axis_tready) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            case ({s_axis_tvalid && s_axis_tready, m_axis_tvalid && m_axis_tready})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
            fifo_dout_r <= mem[rd_ptr];
        end
    end
`endif

    assign s_axis_tready = !fifo_full;
    assign m_axis_tvalid = !fifo_empty;
    assign {m_axis_tsof, m_axis_terror, m_axis_tlast, m_axis_tdata} = fifo_dout;

endmodule
