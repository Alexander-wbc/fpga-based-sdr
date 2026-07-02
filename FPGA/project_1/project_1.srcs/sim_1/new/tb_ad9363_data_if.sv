`timescale 1ns / 1ps

module tb_ad9363_data_if;

    localparam int PAIR_COUNT = 8;

    logic        rst_n = 1'b0;
    logic        sys_clk = 1'b0;
    logic        ad_data_clk = 1'b0;
    logic        ad_rx_frame = 1'b0;
    logic [11:0] ad_p0_rx_data = 12'd0;
    logic        ad_fb_clk;
    logic        ad_tx_frame;
    logic [11:0] ad_p1_tx_data;
    logic        ad_enable;
    logic        ad_txnrx;
    logic        rx_fifo_rd_en = 1'b0;
    logic [23:0] rx_fifo_data;
    logic        rx_fifo_empty;
    logic        rx_fifo_almost_empty;
    logic        rx_fifo_valid;
    logic [6:0]  rx_fifo_data_count;
    logic        rx_fifo_overflow;
    logic        tx_fifo_wr_en = 1'b0;
    logic [23:0] tx_fifo_data = 24'd0;
    logic        tx_fifo_wr_ready;
    logic        tx_fifo_full;
    logic        tx_fifo_almost_full;
    logic [6:0]  tx_fifo_data_count;
    logic        tx_fifo_underflow;

    integer tx_pair_index = 0;
    logic   tx_expect_q = 1'b0;

    always #10 sys_clk = ~sys_clk;
    always #25 ad_data_clk = ~ad_data_clk;

    ad9363_data_if dut (
        .rst_n(rst_n),
        .sys_clk(sys_clk),
        .ad_data_clk(ad_data_clk),
        .ad_rx_frame(ad_rx_frame),
        .ad_p0_rx_data(ad_p0_rx_data),
        .ad_fb_clk(ad_fb_clk),
        .ad_tx_frame(ad_tx_frame),
        .ad_p1_tx_data(ad_p1_tx_data),
        .ad_enable(ad_enable),
        .ad_txnrx(ad_txnrx),
        .rx_fifo_rd_en(rx_fifo_rd_en),
        .rx_fifo_data(rx_fifo_data),
        .rx_fifo_empty(rx_fifo_empty),
        .rx_fifo_almost_empty(rx_fifo_almost_empty),
        .rx_fifo_valid(rx_fifo_valid),
        .rx_fifo_data_count(rx_fifo_data_count),
        .rx_fifo_overflow(rx_fifo_overflow),
        .tx_fifo_wr_en(tx_fifo_wr_en),
        .tx_fifo_data(tx_fifo_data),
        .tx_fifo_wr_ready(tx_fifo_wr_ready),
        .tx_fifo_full(tx_fifo_full),
        .tx_fifo_almost_full(tx_fifo_almost_full),
        .tx_fifo_data_count(tx_fifo_data_count),
        .tx_fifo_underflow(tx_fifo_underflow)
    );

    task automatic drive_rx_pair(input int index);
        @(negedge ad_data_clk);
        #1;
        ad_rx_frame   = 1'b1;
        ad_p0_rx_data = 12'h100 + index;
        @(posedge ad_data_clk);

        @(negedge ad_data_clk);
        #1;
        ad_rx_frame   = 1'b0;
        ad_p0_rx_data = 12'h200 + index;
        @(posedge ad_data_clk);
    endtask

    task automatic write_tx_pair(input int index);
        while (tx_fifo_wr_ready !== 1'b1) begin
            @(posedge sys_clk);
        end

        @(negedge sys_clk);
        tx_fifo_data[23:12] = 12'h300 + index;
        tx_fifo_data[11:0]  = 12'h400 + index;
        tx_fifo_wr_en = 1'b1;
        @(negedge sys_clk);
        tx_fifo_wr_en = 1'b0;
    endtask

    task automatic read_and_check_rx_pair(input int index);
        int timeout;
        logic [23:0] expected;

        expected[23:12] = 12'h100 + index;
        expected[11:0]  = 12'h200 + index;

        timeout = 0;
        while (rx_fifo_empty) begin
            @(posedge sys_clk);
            timeout++;
            if (timeout > 500) begin
                $fatal(1, "timeout waiting for RX pair %0d", index);
            end
        end

        @(negedge sys_clk);
        rx_fifo_rd_en = 1'b1;
        @(negedge sys_clk);
        rx_fifo_rd_en = 1'b0;

        timeout = 0;
        while (!rx_fifo_valid) begin
            @(posedge sys_clk);
            timeout++;
            if (timeout > 50) begin
                $fatal(1, "timeout waiting for RX FIFO valid");
            end
        end

        assert(rx_fifo_data == expected)
            else $fatal(1, "RX IQ mismatch: got %h", rx_fifo_data);
    endtask

    always @(posedge ad_fb_clk) begin
        #1;
        if (ad_tx_frame) begin
            assert(!tx_expect_q)
                else $fatal(1, "TX_FRAME asserted before Q was sent");
            assert(ad_p1_tx_data == 12'h300 + tx_pair_index)
                else $fatal(1, "TX I mismatch: got %h", ad_p1_tx_data);
            tx_expect_q = 1'b1;
        end else if (tx_expect_q) begin
            assert(ad_p1_tx_data == 12'h400 + tx_pair_index)
                else $fatal(1, "TX Q mismatch: got %h", ad_p1_tx_data);
            tx_expect_q = 1'b0;
            tx_pair_index = tx_pair_index + 1;
        end
    end

    initial begin
        #20000;
        $fatal(1, "simulation timeout");
    end

    initial begin
        repeat (10) @(posedge sys_clk);
        rst_n = 1'b1;

        repeat (10) @(posedge ad_data_clk);
        assert(ad_enable && ad_txnrx)
            else $fatal(1, "FDD control outputs are not asserted");
        while (dut.rx_fifo_wr_rst_busy !== 1'b0) begin
            @(posedge ad_data_clk);
        end

        fork
            begin
                for (int i = 0; i < PAIR_COUNT; i++) begin
                    drive_rx_pair(i);
                end
            end
            begin
                for (int i = 0; i < PAIR_COUNT; i++) begin
                    write_tx_pair(i);
                end
            end
        join

        for (int i = 0; i < PAIR_COUNT; i++) begin
            read_and_check_rx_pair(i);
        end

        wait(tx_pair_index == PAIR_COUNT);
        assert(!rx_fifo_overflow)
            else $fatal(1, "unexpected RX overflow");

        $display("tb_ad9363_data_if PASS");
        $finish;
    end

endmodule
