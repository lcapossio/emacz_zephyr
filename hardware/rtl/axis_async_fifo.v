// SPDX-License-Identifier: Apache-2.0
// Byte-wide AXI-stream clock-domain crossing FIFO.

module axis_async_fifo #(
    parameter ADDR_WIDTH = 10
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXIS, ASSOCIATED_RESET s_rst_n" *)
    input  wire       s_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire       s_rst_n,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 m_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF M_AXIS, ASSOCIATED_RESET m_rst_n" *)
    input  wire       m_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 m_rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire       m_rst_n,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *)
    input  wire [7:0] s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
    input  wire       s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
    output wire       s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST" *)
    input  wire       s_axis_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [7:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire       m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire       m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire       m_axis_tlast
);

    wire [8:0] fifo_din = {s_axis_tlast, s_axis_tdata};
    wire [8:0] fifo_dout;
    wire       fifo_full;
    wire       fifo_empty;

`ifdef XILINX_7SERIES
    wire wr_rst_busy;
    wire rd_rst_busy;

    xpm_fifo_async #(
        .FIFO_WRITE_DEPTH(1 << ADDR_WIDTH),
        .WRITE_DATA_WIDTH(9),
        .READ_DATA_WIDTH(9),
        .READ_MODE("FWFT"),
        .FIFO_READ_LATENCY(0),
        .CDC_SYNC_STAGES(3),
        .DOUT_RESET_VALUE("0"),
        .FULL_RESET_VALUE(0),
        .PROG_EMPTY_THRESH(10),
        .PROG_FULL_THRESH(10),
        .RD_DATA_COUNT_WIDTH(1),
        .WR_DATA_COUNT_WIDTH(ADDR_WIDTH),
        .USE_ADV_FEATURES("0000"),
        .WAKEUP_TIME(0)
    ) u_fifo (
        .wr_clk        (s_clk),
        .wr_en         (s_axis_tvalid && s_axis_tready && !wr_rst_busy),
        .din           (fifo_din),
        .full          (fifo_full),
        .wr_rst_busy   (wr_rst_busy),
        .rd_clk        (m_clk),
        .rd_en         (m_axis_tvalid && m_axis_tready && !rd_rst_busy),
        .dout          (fifo_dout),
        .empty         (fifo_empty),
        .rd_rst_busy   (rd_rst_busy),
        .rst           (~s_rst_n | ~m_rst_n),
        .sleep         (1'b0),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0),
        .sbiterr       (),
        .dbiterr       (),
        .overflow      (),
        .underflow     (),
        .prog_full     (),
        .prog_empty    (),
        .almost_full   (),
        .almost_empty  (),
        .wr_data_count (),
        .rd_data_count (),
        .data_valid    (),
        .wr_ack        ()
    );
`else
    async_fifo #(
        .DATA_WIDTH(9),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_fifo (
        .wr_clk   (s_clk),
        .wr_rst_n (s_rst_n),
        .wr_data  (fifo_din),
        .wr_en    (s_axis_tvalid && s_axis_tready),
        .wr_full  (fifo_full),
        .rd_clk   (m_clk),
        .rd_rst_n (m_rst_n),
        .rd_data  (fifo_dout),
        .rd_en    (m_axis_tvalid && m_axis_tready),
        .rd_empty (fifo_empty)
    );
`endif

    assign s_axis_tready = !fifo_full
`ifdef XILINX_7SERIES
			   && !wr_rst_busy
`endif
			   ;
    assign m_axis_tvalid = !fifo_empty
`ifdef XILINX_7SERIES
			   && !rd_rst_busy
`endif
			   ;
    assign {m_axis_tlast, m_axis_tdata} = fifo_dout;

endmodule
