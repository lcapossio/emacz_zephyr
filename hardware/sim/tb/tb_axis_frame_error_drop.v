`timescale 1ns / 1ps

module tb_axis_frame_error_drop;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;

    reg  [7:0] s_tdata;
    reg        s_tvalid;
    wire       s_tready;
    reg        s_tlast;
    reg        s_terror;
    reg        s_tsof;

    wire [7:0] m_tdata;
    wire       m_tvalid;
    reg        m_tready;
    wire       m_tlast;
    wire       m_terror;
    wire       m_tsof;

    wire [31:0] good_frames;
    wire [31:0] dropped_bad_frames;
    wire [31:0] dropped_overflow_frames;
    wire [31:0] drain_tready_low_cycles;
    wire [31:0] drain_tready_low_cycles_max;
    wire [31:0] drain_tready_low_samples;

    axis_frame_error_drop #(.ADDR_WIDTH(6)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_tdata),
        .s_axis_tvalid(s_tvalid),
        .s_axis_tready(s_tready),
        .s_axis_tlast(s_tlast),
        .s_axis_terror(s_terror),
        .s_axis_tsof(s_tsof),
        .m_axis_tdata(m_tdata),
        .m_axis_tvalid(m_tvalid),
        .m_axis_tready(m_tready),
        .m_axis_tlast(m_tlast),
        .m_axis_terror(m_terror),
        .m_axis_tsof(m_tsof),
        .good_frames(good_frames),
        .dropped_bad_frames(dropped_bad_frames),
        .dropped_overflow_frames(dropped_overflow_frames),
        .drain_samples(),
        .drain_cycles_total(),
        .drain_cycles_max(),
        .drain_lt_50us(),
        .drain_50_100us(),
        .drain_100_200us(),
        .drain_200_500us(),
        .drain_ge_500us(),
        .drain_tready_low_cycles(drain_tready_low_cycles),
        .drain_tready_low_cycles_max(drain_tready_low_cycles_max),
        .drain_tready_low_samples(drain_tready_low_samples)
    );

    integer rx_count;
    reg [7:0] rx_buf [0:31];
    integer fail_cnt;
    integer i;

    task send_frame;
        input integer len;
        input integer mark_bad;
        integer k;
        begin
            for (k = 0; k < len; k = k + 1) begin
                @(negedge clk);
                s_tdata = k[7:0];
                s_tvalid = 1'b1;
                s_tsof = (k == 0);
                s_tlast = (k == len - 1);
                s_terror = mark_bad && (k == len - 1);
                @(posedge clk);
                while (!s_tready) @(posedge clk);
            end
            @(negedge clk);
            s_tvalid = 1'b0;
            s_tsof = 1'b0;
            s_tlast = 1'b0;
            s_terror = 1'b0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_count <= 0;
        end else if (m_tvalid && m_tready) begin
            if (rx_count < 32)
                rx_buf[rx_count] <= m_tdata;
            rx_count <= rx_count + 1;
        end
    end

    initial begin
        $dumpfile("tb_axis_frame_error_drop.vcd");
        $dumpvars(0, tb_axis_frame_error_drop);

        fail_cnt = 0;
        s_tdata = 8'd0;
        s_tvalid = 1'b0;
        s_tlast = 1'b0;
        s_terror = 1'b0;
        s_tsof = 1'b0;
        m_tready = 1'b1;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        send_frame(16, 0);
        repeat (80) @(posedge clk);

        if (rx_count != 16) begin
            $display("FAIL: good frame output count %0d", rx_count);
            fail_cnt = fail_cnt + 1;
        end
        for (i = 0; i < 16; i = i + 1) begin
            if (rx_buf[i] !== i[7:0]) begin
                $display("FAIL: good byte %0d got %02x", i, rx_buf[i]);
                fail_cnt = fail_cnt + 1;
            end
        end
        if (good_frames != 32'd1 || dropped_bad_frames != 32'd0) begin
            $display("FAIL: counters after good frame good=%0d bad=%0d",
                     good_frames, dropped_bad_frames);
            fail_cnt = fail_cnt + 1;
        end

        rx_count = 0;
        send_frame(16, 1);
        repeat (80) @(posedge clk);

        if (rx_count != 0) begin
            $display("FAIL: bad frame leaked %0d bytes", rx_count);
            fail_cnt = fail_cnt + 1;
        end
        if (good_frames != 32'd1 || dropped_bad_frames != 32'd1) begin
            $display("FAIL: counters after bad frame good=%0d bad=%0d",
                     good_frames, dropped_bad_frames);
            fail_cnt = fail_cnt + 1;
        end

        rx_count = 0;
        send_frame(80, 0);
        repeat (120) @(posedge clk);

        if (rx_count != 0) begin
            $display("FAIL: overflow frame leaked %0d bytes", rx_count);
            fail_cnt = fail_cnt + 1;
        end
        if (dropped_overflow_frames != 32'd1) begin
            $display("FAIL: overflow counter %0d", dropped_overflow_frames);
            fail_cnt = fail_cnt + 1;
        end

        if (fail_cnt == 0) begin
            $display("AXIS-FRAME-ERROR-DROP: ALL TESTS PASSED");
            $finish;
        end else begin
            $display("AXIS-FRAME-ERROR-DROP: TESTS FAILED");
            $finish_and_return(1);
        end
    end
endmodule
