`timescale 1ns / 1ps

module tb_sdr_top;
    localparam logic [31:0] FRAME_MAGIC = 32'hAAAA5555;
    localparam logic [7:0]  FRAME_TYPE_DATA = 8'h10;
    localparam logic [7:0]  FRAME_TYPE_START = 8'h20;
    localparam logic [7:0]  TX_FRAME_TYPE_ACK = 8'h30;
    localparam int RX_IQ_WORDS = 256;
    localparam int PC_TX_IQ_WORDS = 4;

    logic rst_n = 1'b0;
    logic sys_clk = 1'b0;
    logic FT601_clk = 1'b0;
    logic ad9363_data_clk = 1'b0;

    wire [31:0] FT601_DATA;
    wire [3:0]  FT601_BE;
    logic FT601_TXE_N = 1'b0;
    logic FT601_RXF_N = 1'b1;
    logic FT601_WR_N;
    logic FT601_RD_N;
    logic FT601_OE_N;
    logic FT601_SIWU_N;

    logic        ad9363_rx_frame = 1'b0;
    logic [11:0] ad9363_p0_rx_data = 12'd0;
    logic        ad9363_fb_clk;
    logic        ad9363_tx_frame;
    logic [11:0] ad9363_p1_tx_data;
    logic        ad9363_enable;
    logic        ad9363_txnrx;
    logic        ad9363_spi_csn;
    logic        ad9363_spi_sclk;
    logic        ad9363_spi_mosi;
    logic        ad9363_spi_miso = 1'b0;

    logic        pc_bus_drive = 1'b0;
    logic [31:0] pc_bus_data = 32'd0;
    logic [31:0] pc_rx_words [0:511];
    logic [23:0] pc_tx_iq [0:PC_TX_IQ_WORDS-1];
    int pc_rx_count = 0;
    int ad_tx_iq_count = 0;
    int main_timeout = 0;
    bit ad_tx_wait_q = 1'b0;

    assign FT601_DATA = pc_bus_drive ? pc_bus_data : 32'hZZZZ_ZZZZ;
    assign FT601_BE   = pc_bus_drive ? 4'hF : 4'hZ;

    always #10 sys_clk = ~sys_clk;           // 50 MHz
    always #5  FT601_clk = ~FT601_clk;       // 100 MHz
    always #25 ad9363_data_clk = ~ad9363_data_clk; // 20 MHz, 10 MSPS IQ

    sdr_top dut (.*);

    // Capture every FPGA -> FT601 word after registered bus outputs settle.
    always begin
        @(posedge FT601_clk);
        #1;
        if (rst_n && !FT601_WR_N) begin
            assert(!pc_bus_drive) else $fatal(1, "FT601 bus contention");
            pc_rx_words[pc_rx_count] = FT601_DATA;
            pc_rx_count++;
        end
    end

    // Check the complete PC -> AD9363 IQ stream at the AD9363 sample edge.
    always begin
        @(posedge ad9363_data_clk);
        #1;
        if (rst_n && ad9363_tx_frame) begin
            assert(!ad_tx_wait_q) else $fatal(1, "two consecutive TX I words");
            assert(ad9363_p1_tx_data == pc_tx_iq[ad_tx_iq_count][23:12])
                else $fatal(1, "AD9363 TX I mismatch at %0d", ad_tx_iq_count);
            ad_tx_wait_q = 1'b1;
        end else if (rst_n && ad_tx_wait_q) begin
            assert(ad9363_p1_tx_data == pc_tx_iq[ad_tx_iq_count][11:0])
                else $fatal(1, "AD9363 TX Q mismatch at %0d", ad_tx_iq_count);
            ad_tx_wait_q = 1'b0;
            ad_tx_iq_count++;
        end
    end

    task automatic ft601_write_word(input logic [31:0] word);
        int timeout;
        @(negedge FT601_clk);
        pc_bus_data   = word;
        pc_bus_drive  = 1'b1;
        FT601_RXF_N   = 1'b0;

        timeout = 0;
        do begin
            @(posedge FT601_clk);
            #1;
            timeout++;
            if (timeout > 10000) $fatal(1, "FT601 input timeout");
        end while (FT601_OE_N || FT601_RD_N);

        @(negedge FT601_clk);
        pc_bus_drive = 1'b0;
        FT601_RXF_N  = 1'b1;
        pc_bus_data  = 32'd0;
    endtask

    task automatic send_header(
        input logic [7:0] frame_type,
        input logic [31:0] payload_words
    );
        ft601_write_word(FRAME_MAGIC);
        ft601_write_word({24'd0, frame_type});
        ft601_write_word(payload_words);
    endtask

    task automatic drive_ad9363_iq(
        input logic [11:0] i_data,
        input logic [11:0] q_data
    );
        @(negedge ad9363_data_clk);
        ad9363_rx_frame   = 1'b1;
        ad9363_p0_rx_data = i_data;
        @(negedge ad9363_data_clk);
        ad9363_rx_frame   = 1'b0;
        ad9363_p0_rx_data = q_data;
    endtask

    task automatic wait_for_pc_words(input int target);
        int timeout;
        timeout = 0;
        while (pc_rx_count < target && timeout < 500000) begin
            @(posedge FT601_clk);
            timeout++;
        end
        assert(pc_rx_count >= target)
            else $fatal(1, "timeout waiting for %0d PC words", target);
    endtask

    function automatic logic [31:0] expected_rx_word(input int index);
        logic [11:0] i_data;
        logic [11:0] q_data;
        begin
            i_data = 12'h100 + index;
            q_data = 12'h500 + index;
            expected_rx_word = {8'd0, i_data, q_data};
        end
    endfunction

    initial begin
        pc_tx_iq[0] = 24'h112233;
        pc_tx_iq[1] = 24'hABCDEF;
        pc_tx_iq[2] = 24'h001FFF;
        pc_tx_iq[3] = 24'h8007FF;

        repeat (20) @(posedge sys_clk);
        @(negedge sys_clk);
        rst_n = 1'b1;
        repeat (20) @(posedge sys_clk);

        assert(ad9363_enable && ad9363_txnrx)
            else $fatal(1, "AD9363 FDD controls are inactive");

        // Direction 1: PC -> FT601 -> Packet Layer -> AD9363 TX.
        send_header(FRAME_TYPE_DATA, PC_TX_IQ_WORDS);
        for (int i = 0; i < PC_TX_IQ_WORDS; i++) begin
            ft601_write_word({8'd0, pc_tx_iq[i]});
        end

        main_timeout = 0;
        while (ad_tx_iq_count < PC_TX_IQ_WORDS && main_timeout < 10000) begin
            @(posedge sys_clk);
            main_timeout++;
        end
        assert(ad_tx_iq_count == PC_TX_IQ_WORDS)
            else $fatal(1,
                "PC->AD timeout: packet_count=%0d ad_tx_count=%0d ready=%b inner_ready=%b full=%b rst_busy=%b fifo_rst=%b rd_en=%b pending=%b IQ_seen=%0d",
                dut.pc_tx_fifo_data_count,
                dut.ad_tx_fifo_data_count,
                dut.ad_tx_fifo_wr_ready,
                dut.u_ad9363_top.u_ad9363_data_if.tx_fifo_wr_ready,
                dut.ad_tx_fifo_full,
                dut.u_ad9363_top.u_ad9363_data_if.tx_fifo_wr_rst_busy,
                dut.u_ad9363_top.u_ad9363_data_if.fifo_rst,
                dut.pc_tx_fifo_rd_en,
                dut.pc_tx_read_pending,
                ad_tx_iq_count);

        // Enable AD9363 -> PC streaming and verify the ACK first.
        send_header(FRAME_TYPE_START, 32'd0);
        wait_for_pc_words(4);
        assert(pc_rx_words[0] == FRAME_MAGIC);
        assert(pc_rx_words[1][7:0] == TX_FRAME_TYPE_ACK);
        assert(pc_rx_words[2] == 32'd1);
        assert(pc_rx_words[3][7:0] == FRAME_TYPE_START);

        // Direction 2: AD9363 RX -> Packet Layer -> FT601 -> PC.
        for (int i = 0; i < RX_IQ_WORDS; i++) begin
            drive_ad9363_iq(12'h100 + i, 12'h500 + i);
        end
        @(negedge ad9363_data_clk);
        ad9363_rx_frame   = 1'b0;
        ad9363_p0_rx_data = 12'd0;

        wait_for_pc_words(4 + 3 + RX_IQ_WORDS);
        assert(pc_rx_words[4] == FRAME_MAGIC);
        assert(pc_rx_words[5][7:0] == FRAME_TYPE_DATA);
        assert(pc_rx_words[6] == RX_IQ_WORDS);

        for (int i = 0; i < RX_IQ_WORDS; i++) begin
            assert(pc_rx_words[7+i] == expected_rx_word(i))
                else $fatal(1, "PC RX IQ mismatch at %0d: %h", i, pc_rx_words[7+i]);
        end

        assert(!dut.ad_rx_fifo_overflow)
            else $fatal(1, "AD9363 RX CDC FIFO overflowed");

        $display("tb_sdr_top BIDIRECTIONAL PASS");
        $finish;
    end
endmodule
