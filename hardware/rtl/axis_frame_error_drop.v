// =============================================================================
// axis_frame_error_drop.v - Store-and-forward AXI-stream frame error gate
//
// Buffers whole byte-wide frames and forwards only frames that never asserted the
// MAC error sideband. SLOT_COUNT gives a small elastic store so a DMA-side drain
// stall does not immediately backpressure the MAC receive path.
// =============================================================================

module axis_frame_error_drop #(
    parameter ADDR_WIDTH = 11,
    parameter SLOT_COUNT = 4
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire        s_axis_terror,
    input  wire        s_axis_tsof,

    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast,
    output reg         m_axis_terror,
    output reg         m_axis_tsof,

    output reg  [31:0] good_frames,
    output reg  [31:0] dropped_bad_frames,
    output reg  [31:0] dropped_overflow_frames,
    output reg  [31:0] drain_samples,
    output reg  [31:0] drain_cycles_total,
    output reg  [31:0] drain_cycles_max,
    output reg  [31:0] drain_lt_50us,
    output reg  [31:0] drain_50_100us,
    output reg  [31:0] drain_100_200us,
    output reg  [31:0] drain_200_500us,
    output reg  [31:0] drain_ge_500us,
    output reg  [31:0] drain_tready_low_cycles,
    output reg  [31:0] drain_tready_low_cycles_max,
    output reg  [31:0] drain_tready_low_samples
);

    localparam DEPTH = (1 << ADDR_WIDTH);
    localparam SLOT_BITS = (SLOT_COUNT <= 2) ? 1 :
                           (SLOT_COUNT <= 4) ? 2 :
                           (SLOT_COUNT <= 8) ? 3 : 4;
    localparam MEM_ADDR_WIDTH = ADDR_WIDTH + SLOT_BITS;

    localparam [0:0]
        FILL_ACTIVE = 1'b0,
        FILL_DROP   = 1'b1;

    reg fill_state;
    reg [SLOT_BITS-1:0] fill_slot;
    reg [SLOT_BITS-1:0] drain_slot;
    reg [SLOT_BITS:0] full_count;
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_count;
    reg [ADDR_WIDTH:0] slot_len [0:SLOT_COUNT-1];
    reg [ADDR_WIDTH:0] drain_len;
    reg frame_bad;
    reg drain_active;
    reg [31:0] drain_cycles_current;
    reg [31:0] drain_tready_low_current;
    reg ram_rd_pending;
    reg inc_full_count;
    reg dec_full_count;

    wire input_accept = s_axis_tvalid && s_axis_tready;
    wire output_accept = m_axis_tvalid && m_axis_tready;
    wire finish_drain = output_accept && m_axis_tlast;
    wire output_slot_free = !m_axis_tvalid || m_axis_tready;
    wire slot_available = (full_count < SLOT_COUNT);
    wire write_overflow = input_accept && (wr_ptr == {ADDR_WIDTH{1'b1}}) && !s_axis_tlast;
    wire [MEM_ADDR_WIDTH-1:0] wr_addr = {fill_slot, wr_ptr};
    wire [MEM_ADDR_WIDTH-1:0] rd_addr = {drain_slot, rd_count[ADDR_WIDTH-1:0]};
    wire [10:0] ram_din = {s_axis_tsof, s_axis_terror, s_axis_tlast, s_axis_tdata};
    wire [10:0] ram_dout;
    wire ram_wr_en = input_accept && (fill_state == FILL_ACTIVE);
    wire ram_rd_fire = drain_active && !finish_drain && output_slot_free &&
                       !ram_rd_pending && (rd_count < drain_len);

    assign s_axis_tready = (fill_state == FILL_DROP) || slot_available;

    integer i;

`ifdef XILINX_7SERIES
    // Force the frame store into BRAM. Vivado's generic inference can otherwise
    // try to legalize the 4-slot store as LUTRAM and spend minutes going nowhere.
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(MEM_ADDR_WIDTH),
        .ADDR_WIDTH_B(MEM_ADDR_WIDTH),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(11),
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(11 * SLOT_COUNT * DEPTH),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_B(11),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(11),
        .WRITE_MODE_B("read_first")
    ) u_frame_ram (
        .sleep(1'b0),
        .clka(clk),
        .ena(ram_wr_en),
        .wea(1'b1),
        .addra(wr_addr),
        .dina(ram_din),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .clkb(clk),
        .rstb(1'b0),
        .enb(ram_rd_fire),
        .regceb(1'b1),
        .addrb(rd_addr),
        .doutb(ram_dout),
        .sbiterrb(),
        .dbiterrb()
    );
`else
    (* ram_style = "block" *) reg [10:0] mem [0:(SLOT_COUNT*DEPTH)-1];
    reg [10:0] ram_dout_r;
    assign ram_dout = ram_dout_r;

    always @(posedge clk) begin
        if (ram_wr_en) begin
            mem[wr_addr] <= ram_din;
        end
        if (ram_rd_fire) begin
            ram_dout_r <= mem[rd_addr];
        end
    end
`endif

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_state <= FILL_ACTIVE;
            fill_slot <= {SLOT_BITS{1'b0}};
            drain_slot <= {SLOT_BITS{1'b0}};
            full_count <= {SLOT_BITS+1{1'b0}};
            wr_ptr <= {ADDR_WIDTH{1'b0}};
            rd_count <= {ADDR_WIDTH+1{1'b0}};
            drain_len <= {ADDR_WIDTH+1{1'b0}};
            frame_bad <= 1'b0;
            drain_active <= 1'b0;
            m_axis_tdata <= 8'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            m_axis_terror <= 1'b0;
            m_axis_tsof <= 1'b0;
            good_frames <= 32'd0;
            dropped_bad_frames <= 32'd0;
            dropped_overflow_frames <= 32'd0;
            drain_samples <= 32'd0;
            drain_cycles_total <= 32'd0;
            drain_cycles_max <= 32'd0;
            drain_lt_50us <= 32'd0;
            drain_50_100us <= 32'd0;
            drain_100_200us <= 32'd0;
            drain_200_500us <= 32'd0;
            drain_ge_500us <= 32'd0;
            drain_tready_low_cycles <= 32'd0;
            drain_tready_low_cycles_max <= 32'd0;
            drain_tready_low_samples <= 32'd0;
            drain_cycles_current <= 32'd0;
            drain_tready_low_current <= 32'd0;
            ram_rd_pending <= 1'b0;
            for (i = 0; i < SLOT_COUNT; i = i + 1) begin
                slot_len[i] <= {ADDR_WIDTH+1{1'b0}};
            end
        end else begin
            inc_full_count = 1'b0;
            dec_full_count = 1'b0;

            if (drain_active) begin
                drain_cycles_current <= drain_cycles_current + 1'b1;
                if (m_axis_tvalid && !m_axis_tready) begin
                    drain_tready_low_cycles <= drain_tready_low_cycles + 1'b1;
                    drain_tready_low_current <= drain_tready_low_current + 1'b1;
                    drain_tready_low_samples <= drain_tready_low_samples + 1'b1;
                end
            end

            if (fill_state == FILL_DROP) begin
                if (input_accept && s_axis_tlast) begin
                    fill_state <= FILL_ACTIVE;
                    wr_ptr <= {ADDR_WIDTH{1'b0}};
                    frame_bad <= 1'b0;
                end
            end else if (input_accept) begin
                frame_bad <= frame_bad || s_axis_terror || write_overflow;

                if (write_overflow) begin
                    fill_state <= FILL_DROP;
                    dropped_overflow_frames <= dropped_overflow_frames + 1'b1;
                end else if (s_axis_tlast) begin
                    if (frame_bad || s_axis_terror) begin
                        dropped_bad_frames <= dropped_bad_frames + 1'b1;
                    end else begin
                        slot_len[fill_slot] <= {1'b0, wr_ptr} + 1'b1;
                        inc_full_count = 1'b1;
                        fill_slot <= (fill_slot == (SLOT_COUNT-1)) ?
                                     {SLOT_BITS{1'b0}} : fill_slot + 1'b1;
                        good_frames <= good_frames + 1'b1;
                    end
                    wr_ptr <= {ADDR_WIDTH{1'b0}};
                    frame_bad <= 1'b0;
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end

            if (!drain_active && (full_count != {SLOT_BITS+1{1'b0}})) begin
                drain_active <= 1'b1;
                drain_len <= slot_len[drain_slot];
                rd_count <= {ADDR_WIDTH+1{1'b0}};
                drain_cycles_current <= 32'd0;
                drain_tready_low_current <= 32'd0;
                ram_rd_pending <= 1'b0;
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
                m_axis_tsof <= 1'b0;
            end else if (drain_active) begin
                if (finish_drain) begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                    m_axis_tsof <= 1'b0;
                    drain_active <= 1'b0;
                    ram_rd_pending <= 1'b0;
                    dec_full_count = 1'b1;
                    drain_slot <= (drain_slot == (SLOT_COUNT-1)) ?
                                  {SLOT_BITS{1'b0}} : drain_slot + 1'b1;
                    drain_samples <= drain_samples + 1'b1;
                    drain_cycles_total <= drain_cycles_total + drain_cycles_current + 1'b1;
                    if ((drain_cycles_current + 1'b1) > drain_cycles_max) begin
                        drain_cycles_max <= drain_cycles_current + 1'b1;
                    end
                    if (drain_tready_low_current > drain_tready_low_cycles_max) begin
                        drain_tready_low_cycles_max <= drain_tready_low_current;
                    end
                    if ((drain_cycles_current + 1'b1) < 32'd5000) begin
                        drain_lt_50us <= drain_lt_50us + 1'b1;
                    end else if ((drain_cycles_current + 1'b1) < 32'd10000) begin
                        drain_50_100us <= drain_50_100us + 1'b1;
                    end else if ((drain_cycles_current + 1'b1) < 32'd20000) begin
                        drain_100_200us <= drain_100_200us + 1'b1;
                    end else if ((drain_cycles_current + 1'b1) < 32'd50000) begin
                        drain_200_500us <= drain_200_500us + 1'b1;
                    end else begin
                        drain_ge_500us <= drain_ge_500us + 1'b1;
                    end
                end else begin
                    if (output_accept) begin
                        m_axis_tvalid <= 1'b0;
                    end
                    if (ram_rd_pending) begin
                        {m_axis_tsof, m_axis_terror, m_axis_tlast, m_axis_tdata} <= ram_dout;
                        m_axis_tvalid <= 1'b1;
                        ram_rd_pending <= 1'b0;
                    end
                    if (ram_rd_fire) begin
                        ram_rd_pending <= 1'b1;
                        rd_count <= rd_count + 1'b1;
                    end
                end
            end else begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
                m_axis_tsof <= 1'b0;
            end

            case ({inc_full_count, dec_full_count})
                2'b10: full_count <= full_count + 1'b1;
                2'b01: full_count <= full_count - 1'b1;
                default: full_count <= full_count;
            endcase
        end
    end

endmodule
