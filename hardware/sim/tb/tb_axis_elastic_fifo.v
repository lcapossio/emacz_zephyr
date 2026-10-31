// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
//
// axis_elastic_fifo, generic (non-XPM) branch: every word comes out once, in
// order, with its sideband bits, under full-rate, random and stalled traffic;
// the FIFO holds exactly DEPTH words; a word written into an empty FIFO is
// presented correctly, which is where a one-cycle-late read goes wrong.
`timescale 1ns / 1ps

module tb_axis_elastic_fifo;
    localparam ADDR_WIDTH = 4;
    localparam DEPTH = 1 << ADDR_WIDTH;
    localparam TOTAL = 4000;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;

    reg  [7:0] s_tdata = 0;
    reg        s_tvalid = 0;
    wire       s_tready;
    reg        s_tlast = 0;
    reg        s_terror = 0;
    reg        s_tsof = 0;

    wire [7:0] m_tdata;
    wire       m_tvalid;
    reg        m_tready = 0;
    wire       m_tlast;
    wire       m_terror;
    wire       m_tsof;

    axis_elastic_fifo #(.ADDR_WIDTH(ADDR_WIDTH)) dut (
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
        .m_axis_tsof(m_tsof)
    );

    // Word n of the stream: data n[7:0], a frame every 7 words (tsof on the
    // first, tlast on the last) and terror on every 13th word
    function [10:0] word;
        input integer n;
        begin
            word = {(n % 7) == 0, (n % 13) == 5, (n % 7) == 6, n[7:0]};
        end
    endfunction

    integer sent = 0;
    integer received = 0;
    integer errors = 0;
    integer limit = 0;
    integer valid_pct = 100;
    integer ready_pct = 100;
    reg     took = 0;

    // Producer and consumer change their signals on the falling edge; the
    // producer moves on only after a handshake on the rising edge before it
    always @(negedge clk) begin
        if (rst_n) begin
            if (!s_tvalid || took) begin
                if (sent < limit && ($urandom % 100) < valid_pct) begin
                    {s_tsof, s_terror, s_tlast, s_tdata} <= word(sent);
                    s_tvalid <= 1'b1;
                end else begin
                    s_tvalid <= 1'b0;
                end
            end
            m_tready <= ($urandom % 100) < ready_pct;
        end
    end

    always @(posedge clk) begin
        took <= s_tvalid && s_tready;
        if (s_tvalid && s_tready) begin
            sent <= sent + 1;
        end
        if (m_tvalid && m_tready) begin
            if ({m_tsof, m_terror, m_tlast, m_tdata} !== word(received)) begin
                if (errors < 10) begin
                    $display("FAIL: word %0d is %03h, expected %03h", received,
                             {m_tsof, m_terror, m_tlast, m_tdata}, word(received));
                end
                errors = errors + 1;
            end
            received <= received + 1;
        end
    end

    task run_until;
        input integer target;
        integer guard;
        begin
            guard = 0;
            while (received < target && guard < 200000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (received < target) begin
                $display("FAIL: stalled at %0d of %0d words", received, target);
                errors = errors + 1;
            end
        end
    endtask

    integer i;
    integer full_ok;

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;

        // 1: one word at a time through an empty FIFO
        valid_pct = 100;
        ready_pct = 100;
        for (i = 1; i <= 20; i = i + 1) begin
            limit = i;
            run_until(i);
            repeat (3) @(posedge clk);
        end

        // 2: back to back at full rate
        limit = TOTAL;
        run_until(1000);

        // 3: random gaps on both sides
        valid_pct = 60;
        ready_pct = 40;
        run_until(2500);

        // 4: consumer stalled: the FIFO takes exactly DEPTH words
        ready_pct = 0;
        valid_pct = 100;
        repeat (3 * DEPTH) @(posedge clk);
        full_ok = (sent - received == DEPTH) && !s_tready;
        if (!full_ok) begin
            $display("FAIL: holding %0d words with tready=%0b, expected %0d and 0",
                     sent - received, s_tready, DEPTH);
            errors = errors + 1;
        end

        // 5: drain while the producer keeps it near full
        ready_pct = 70;
        valid_pct = 90;
        run_until(TOTAL);

        repeat (10) @(posedge clk);
        if (m_tvalid) begin
            $display("FAIL: tvalid still high after the last word");
            errors = errors + 1;
        end
        if (errors == 0 && received == TOTAL) begin
            $display("AXIS-ELASTIC-FIFO: ALL TESTS PASSED (%0d words)", received);
        end else begin
            $display("AXIS-ELASTIC-FIFO: %0d ERRORS", errors);
        end
        $finish;
    end
endmodule
