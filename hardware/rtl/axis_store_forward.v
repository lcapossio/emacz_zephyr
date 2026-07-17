// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
// =============================================================================
// axis_store_forward.v
//
// Byte-wide AXI-Stream store-and-forward buffer. The output side never asserts
// tvalid until a complete frame (delimited by tlast on the input) is buffered.
// This guarantees the downstream consumer (eth_mac_tx) never sees a mid-frame
// underrun, which would otherwise trigger gmii_tx_er and a truncated/no-CRC
// frame on the MII bus.
//
// Topology
//   single FIFO holds {tlast, tdata} pairs. A pending-frame counter advances
//   on every tlast write and retires on every tlast read. m_axis_tvalid is
//   gated by (pending_frames > 0), so the downstream sees frames atomically.
//
// Sizing
//   DATA_FIFO_ADDR_WIDTH must be large enough for one full MAX_FRAME — if the
//   write side fills the FIFO before tlast arrives, it stalls upstream by
//   dropping s_axis_tready. Default 4096 bytes covers standard Ethernet 1518.
//   Raise for jumbo support.
// =============================================================================
`timescale 1ns / 1ps

module axis_store_forward #(
    parameter integer DATA_FIFO_ADDR_WIDTH = 12,  // 2**12 = 4096 entries
    parameter integer FRAME_COUNT_WIDTH    = 8    // up to 255 frames pending
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 100000000, ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET rst_n" *)
    input  wire        clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        rst_n,

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

    // Diagnostics
    output wire [31:0] dbg_frames_committed,
    output wire [31:0] dbg_frames_drained,
    output wire [DATA_FIFO_ADDR_WIDTH-1:0] dbg_data_level,
    output wire [FRAME_COUNT_WIDTH-1:0]    dbg_frames_pending
);

    localparam integer DATA_FIFO_DEPTH = (1 << DATA_FIFO_ADDR_WIDTH);

    wire [8:0] fifo_din  = {s_axis_tlast, s_axis_tdata};
    wire [8:0] fifo_dout;
    wire       fifo_full;
    wire       fifo_empty;
    wire       fifo_wr_en;
    wire       fifo_rd_en;
    wire       wr_rst_busy;
    wire       rd_rst_busy;

    // Frame-pending counter: increments on tlast write, decrements on tlast read.
    // It must NEVER saturate. We backpressure new writes when at max, so the
    // counter only ever reaches max on a legitimate tlast commit and the next
    // accepted byte happens only after at least one drain has decremented it.
    reg [FRAME_COUNT_WIDTH-1:0] frames_pending_r;
    wire frames_pending_full = (frames_pending_r == {FRAME_COUNT_WIDTH{1'b1}});
    wire frames_available    = (frames_pending_r != {FRAME_COUNT_WIDTH{1'b0}});

    // Write/read handshakes — gate by reset-busy and pending-full so the AXIS
    // contract is honored even while the FIFO is held in reset by xpm_fifo_sync.
    assign s_axis_tready = !fifo_full && !wr_rst_busy && !frames_pending_full;
    assign fifo_wr_en    = s_axis_tvalid && s_axis_tready;

    wire frame_wr_commit = fifo_wr_en && s_axis_tlast;
    wire frame_rd_retire = fifo_rd_en && fifo_dout[8];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            frames_pending_r <= {FRAME_COUNT_WIDTH{1'b0}};
        else begin
            case ({frame_wr_commit, frame_rd_retire})
                // Saturation guard kept as defensive insurance, but with the
                // tready-pending-full backpressure above this branch is
                // unreachable in well-formed traffic.
                2'b10: if (!frames_pending_full)
                           frames_pending_r <= frames_pending_r + 1'b1;
                2'b01: if (frames_available)
                           frames_pending_r <= frames_pending_r - 1'b1;
                default: ;
            endcase
        end
    end

    // Output side: tvalid only when a complete frame is buffered AND the FIFO
    // is not held in read-reset. tready from the downstream pops bytes; tlast
    // comes from the FIFO payload directly.
    assign m_axis_tvalid = frames_available && !fifo_empty && !rd_rst_busy;
    assign m_axis_tdata  = fifo_dout[7:0];
    assign m_axis_tlast  = fifo_dout[8];
    assign fifo_rd_en    = m_axis_tvalid && m_axis_tready;

    // Frame counters for debug
    reg [31:0] frames_committed_r;
    reg [31:0] frames_drained_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frames_committed_r <= 32'd0;
            frames_drained_r   <= 32'd0;
        end else begin
            if (frame_wr_commit) frames_committed_r <= frames_committed_r + 1'b1;
            if (frame_rd_retire) frames_drained_r   <= frames_drained_r   + 1'b1;
        end
    end

    assign dbg_frames_committed = frames_committed_r;
    assign dbg_frames_drained   = frames_drained_r;
    assign dbg_frames_pending   = frames_pending_r;

`ifdef SYNTHESIS
    wire [DATA_FIFO_ADDR_WIDTH-1:0] wr_data_count;

    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(DATA_FIFO_DEPTH),
        .WRITE_DATA_WIDTH(9),
        .READ_DATA_WIDTH(9),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .DOUT_RESET_VALUE("0"),
        .FULL_RESET_VALUE(0),
        .RD_DATA_COUNT_WIDTH(1),
        .WR_DATA_COUNT_WIDTH(DATA_FIFO_ADDR_WIDTH),
        .USE_ADV_FEATURES("0400"),
        .WAKEUP_TIME(0)
    ) u_fifo (
        .rst           (~rst_n),
        .wr_clk        (clk),
        .wr_en         (fifo_wr_en && !wr_rst_busy),
        .din           (fifo_din),
        .full          (fifo_full),
        .wr_rst_busy   (wr_rst_busy),
        .rd_en         (fifo_rd_en && !rd_rst_busy),
        .dout          (fifo_dout),
        .empty         (fifo_empty),
        .rd_rst_busy   (rd_rst_busy),
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
        .wr_data_count (wr_data_count),
        .rd_data_count (),
        .data_valid    (),
        .wr_ack        ()
    );
    assign dbg_data_level = wr_data_count;
`else
    // Behavioral sync FIFO for iverilog/cocotb simulation
    reg [8:0] mem [0:DATA_FIFO_DEPTH-1];
    reg [DATA_FIFO_ADDR_WIDTH:0] wr_ptr_r;
    reg [DATA_FIFO_ADDR_WIDTH:0] rd_ptr_r;

    wire [DATA_FIFO_ADDR_WIDTH:0] fill_level = wr_ptr_r - rd_ptr_r;
    assign fifo_full      = (fill_level == DATA_FIFO_DEPTH);
    assign fifo_empty     = (fill_level == {(DATA_FIFO_ADDR_WIDTH+1){1'b0}});
    assign fifo_dout      = mem[rd_ptr_r[DATA_FIFO_ADDR_WIDTH-1:0]];
    assign dbg_data_level = fill_level[DATA_FIFO_ADDR_WIDTH-1:0];
    assign wr_rst_busy    = 1'b0;
    assign rd_rst_busy    = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_r <= {(DATA_FIFO_ADDR_WIDTH+1){1'b0}};
            rd_ptr_r <= {(DATA_FIFO_ADDR_WIDTH+1){1'b0}};
        end else begin
            if (fifo_wr_en) begin
                mem[wr_ptr_r[DATA_FIFO_ADDR_WIDTH-1:0]] <= fifo_din;
                wr_ptr_r <= wr_ptr_r + 1'b1;
            end
            if (fifo_rd_en)
                rd_ptr_r <= rd_ptr_r + 1'b1;
        end
    end
`endif

endmodule
