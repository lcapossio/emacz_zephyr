// =============================================================================
// tb_emaczero_rx_burst_backpressure_bug.v
//
// Regression for Bug B: a clean Ethernet frame must not become a MAC RX error
// or lose its first bytes merely because downstream AXI-stream backpressures.
// Keep this as the executable regression for the FIFO/backpressure bug.
// =============================================================================
`timescale 1ns / 1ps

module tb_emaczero_rx_burst_backpressure_bug;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;

    reg  [7:0] tx_tdata;
    reg        tx_tvalid;
    wire       tx_tready;
    reg        tx_tlast;

    wire [7:0] gmii_txd;
    wire       gmii_tx_en;
    wire       gmii_tx_er;

    eth_mac_tx u_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .tx_start_ok   (1'b1),
        .gmii_txd      (gmii_txd),
        .gmii_tx_en    (gmii_tx_en),
        .gmii_tx_er    (gmii_tx_er),
        .s_axis_tdata  (tx_tdata),
        .s_axis_tvalid (tx_tvalid),
        .s_axis_tready (tx_tready),
        .s_axis_tkeep  (1'b1),
        .s_axis_tlast  (tx_tlast),
        .tx_active     (),
        .dbg_state     (),
        .dbg_stall_cnt ()
    );

    reg [7:0] lb_rxd;
    reg       lb_rx_dv;
    reg       lb_rx_er;
    always @(negedge clk) begin
        lb_rxd   <= gmii_txd;
        lb_rx_dv <= gmii_tx_en;
        lb_rx_er <= gmii_tx_er;
    end

    wire [7:0] rx_tdata;
    wire       rx_tvalid;
    reg        rx_tready;
    wire       rx_tlast;
    wire       rx_terror;
    wire       rx_tsof;

    eth_mac_rx u_rx (
        .clk              (clk),
        .rst_n            (rst_n),
        .gmii_rxd         (lb_rxd),
        .gmii_rx_dv       (lb_rx_dv),
        .gmii_rx_er       (lb_rx_er),
        .our_mac          (48'hFF_FF_FF_FF_FF_FF),
        .promisc          (1'b0),
        .passthrough      (1'b0),
        .jumbo_en         (1'b1),
        .mcast_hash_table (64'd0),
        .m_axis_tdata     (rx_tdata),
        .m_axis_tvalid    (rx_tvalid),
        .m_axis_tready    (rx_tready),
        .m_axis_tlast     (rx_tlast),
        .m_axis_terror    (rx_terror),
        .m_axis_tsof      (rx_tsof),
        .stat_done         (),
        .stat_len          (),
        .stat_err_fcs      (),
        .stat_err_align    (),
        .stat_err_overflow (),
        .stat_err_oversize (),
        .stat_is_bcast     (),
        .stat_is_mcast     ()
    );

    localparam FRAME_LEN = 1514;
    reg [7:0] rx_buf [0:FRAME_LEN-1];
    integer rx_count;
    integer fail_cnt;
    reg saw_terror;
    reg saw_tlast;

    function [7:0] frame_byte;
        input integer idx;
        begin
            case (idx)
                0, 1, 2, 3, 4, 5: frame_byte = 8'hFF;
                6:  frame_byte = 8'h02;
                7:  frame_byte = 8'h00;
                8:  frame_byte = 8'h00;
                9:  frame_byte = 8'h00;
                10: frame_byte = 8'h00;
                11: frame_byte = 8'h01;
                12: frame_byte = 8'h08;
                13: frame_byte = 8'h00;
                default: frame_byte = idx[7:0];
            endcase
        end
    endfunction

    task send_frame;
        integer k;
        begin
            for (k = 0; k < FRAME_LEN; k = k + 1) begin
                @(negedge clk);
                tx_tdata = frame_byte(k);
                tx_tvalid = 1'b1;
                tx_tlast = (k == FRAME_LEN - 1);
                @(posedge clk);
                while (!tx_tready) @(posedge clk);
            end
            @(negedge clk);
            tx_tvalid = 1'b0;
            tx_tlast = 1'b0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_count <= 0;
            saw_terror <= 1'b0;
            saw_tlast <= 1'b0;
        end else if (rx_tvalid && rx_tready) begin
            if (rx_count < FRAME_LEN)
                rx_buf[rx_count] <= rx_tdata;
            rx_count <= rx_count + 1;
            if (rx_terror)
                saw_terror <= 1'b1;
            if (rx_tlast)
                saw_tlast <= 1'b1;
        end
    end

    initial begin
        $dumpfile("tb_emaczero_rx_burst_backpressure_bug.vcd");
        $dumpvars(0, tb_emaczero_rx_burst_backpressure_bug);

        fail_cnt = 0;
        tx_tdata = 8'd0;
        tx_tvalid = 1'b0;
        tx_tlast = 1'b0;
        rx_tready = 1'b1;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        fork
            begin
                send_frame();
            end
            begin
                wait (rx_tvalid && rx_tsof);
                repeat (32) @(posedge clk);
                rx_tready = 1'b0;
                repeat (350) @(posedge clk);
                rx_tready = 1'b1;
            end
        join

        repeat (3000) @(posedge clk);

        if (saw_terror) begin
            $display("FAIL: clean frame raised m_axis_terror under backpressure");
            fail_cnt = fail_cnt + 1;
        end
        if (!saw_tlast) begin
            $display("FAIL: no tlast observed after backpressure");
            fail_cnt = fail_cnt + 1;
        end
        if (rx_count < 16) begin
            $display("FAIL: received too few bytes: %0d", rx_count);
            fail_cnt = fail_cnt + 1;
        end else if (rx_buf[0] !== 8'hFF || rx_buf[1] !== 8'hFF ||
                     rx_buf[2] !== 8'hFF || rx_buf[3] !== 8'hFF ||
                     rx_buf[4] !== 8'hFF || rx_buf[5] !== 8'hFF ||
                     rx_buf[12] !== 8'h08 || rx_buf[13] !== 8'h00) begin
            $display("FAIL: Ethernet header shifted/corrupted at RX output");
            $display("      first16=%02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x",
                     rx_buf[0], rx_buf[1], rx_buf[2], rx_buf[3],
                     rx_buf[4], rx_buf[5], rx_buf[6], rx_buf[7],
                     rx_buf[8], rx_buf[9], rx_buf[10], rx_buf[11],
                     rx_buf[12], rx_buf[13], rx_buf[14], rx_buf[15]);
            fail_cnt = fail_cnt + 1;
        end

        if (fail_cnt == 0) begin
            $display("EMACZERO-RX-BURST-BACKPRESSURE-BUG: ALL TESTS PASSED");
            $finish;
        end else begin
            $display("EMACZERO-RX-BURST-BACKPRESSURE-BUG: TESTS FAILED");
            $finish_and_return(1);
        end
    end
endmodule
