`timescale 1ns / 1ps

module tb_usb_rx_top;

    localparam logic [31:0] FRAME_MAGIC          = 32'hAAAA5555;
    localparam logic [7:0]  FRAME_TYPE_WRITE_REG = 8'h01;
    localparam logic [7:0]  FRAME_TYPE_READ_REG  = 8'h02;
    localparam logic [7:0]  FRAME_TYPE_TX_DATA   = 8'h10;
    localparam logic [7:0]  FRAME_TYPE_START_STREAM = 8'h20;
    localparam logic [7:0]  FRAME_TYPE_STOP_STREAM  = 8'h21;
    localparam logic [7:0]  TX_FRAME_TYPE_REG_DATA  = 8'h03;
    localparam logic [7:0]  TX_FRAME_TYPE_ACK       = 8'h30;
    localparam logic [3:0]  REG_CMD_WRITE        = 4'h1;
    localparam logic [3:0]  REG_CMD_READ         = 4'h2;
    localparam int          DATA_WORDS           = 256;
    localparam int          DATA_PACKETS         = 5;
    localparam int          TOTAL_DATA_WORDS     = DATA_WORDS * DATA_PACKETS;
    localparam int          BACKPRESSURE_COUNT   = 1024 - DATA_WORDS;
    localparam int          REG_CMD_COUNT        = 64;
    localparam logic [9:0]  READ_REG_BASE        = 10'h100;
    localparam logic [9:0]  WRITE_REG_BASE       = 10'h200;
    localparam logic [7:0]  WRITE_DATA_BASE      = 8'h80;

    logic        rst_n = 1'b0;
    logic        sys_clk = 1'b0;
    logic        FT601_clk = 1'b0;
    wire [31:0]  FT601_DATA;
    wire [3:0]   FT601_BE;
    logic        FT601_TXE_N = 1'b1;
    logic        FT601_RXF_N = 1'b1;
    logic        FT601_WR_N;
    logic        FT601_RD_N;
    logic        FT601_OE_N;
    logic        FT601_SIWU_N;

    logic        rx_data_fifo_rd_en;
    logic [31:0] rx_data_fifo_rd_data;
    logic        rx_data_fifo_empty;
    logic        rx_data_fifo_almost_empty;
    logic        rx_data_fifo_valid;
    logic [9:0]  rx_data_fifo_data_count;

    logic        reg_cmd_fifo_rd_en;
    logic [31:0] reg_cmd_fifo_rd_data;
    logic        reg_cmd_fifo_full;
    logic        reg_cmd_fifo_almost_full;
    logic        reg_cmd_fifo_empty;
    logic        reg_cmd_fifo_almost_empty;
    logic        reg_cmd_fifo_valid;
    logic [6:0]  reg_cmd_fifo_data_count;
    logic        tx_data_fifo_wr_en;
    logic [31:0] tx_data_fifo_wr_data;
    logic        tx_data_fifo_wr_ready;
    logic        tx_data_fifo_full;
    logic        tx_data_fifo_almost_full;
    logic [9:0]  tx_data_fifo_data_count;
    logic [10:0] tx_data_fifo_free_words;
    logic        tx_reg_cmd_fifo_wr_en;
    logic [31:0] tx_reg_cmd_fifo_wr_data;
    logic        tx_reg_cmd_fifo_wr_ready;
    logic        tx_reg_cmd_fifo_full;
    logic        tx_reg_cmd_fifo_almost_full;
    logic [6:0]  tx_reg_cmd_fifo_data_count;
    logic [10:0] usb_tx_fifo_free_words;
    logic        rx_start_stream_valid;
    logic        rx_stop_stream_valid;
    logic        rx_frame_error;

    logic        ft601_drive_en = 1'b0;
    logic [31:0] ft601_drive_data = 32'd0;
    logic        data_send_done = 1'b0;

    assign FT601_DATA = ft601_drive_en ? ft601_drive_data : 32'hZZZZ_ZZZZ;
    assign FT601_BE   = ft601_drive_en ? 4'hF : 4'hZ;

    always #10 sys_clk = ~sys_clk;    // 50 MHz FPGA system clock
    always #5  FT601_clk = ~FT601_clk; // 100 MHz FT601 clock

    usb_rx_top dut (
        .rst_n(rst_n),
        .sys_clk(sys_clk),
        .FT601_clk(FT601_clk),
        .FT601_DATA(FT601_DATA),
        .FT601_BE(FT601_BE),
        .FT601_TXE_N(FT601_TXE_N),
        .FT601_RXF_N(FT601_RXF_N),
        .FT601_WR_N(FT601_WR_N),
        .FT601_RD_N(FT601_RD_N),
        .FT601_OE_N(FT601_OE_N),
        .FT601_SIWU_N(FT601_SIWU_N),
        .rx_data_fifo_rd_en(rx_data_fifo_rd_en),
        .rx_data_fifo_rd_data(rx_data_fifo_rd_data),
        .rx_data_fifo_empty(rx_data_fifo_empty),
        .rx_data_fifo_almost_empty(rx_data_fifo_almost_empty),
        .rx_data_fifo_valid(rx_data_fifo_valid),
        .rx_data_fifo_data_count(rx_data_fifo_data_count),
        .reg_cmd_fifo_rd_en(reg_cmd_fifo_rd_en),
        .reg_cmd_fifo_rd_data(reg_cmd_fifo_rd_data),
        .reg_cmd_fifo_full(reg_cmd_fifo_full),
        .reg_cmd_fifo_almost_full(reg_cmd_fifo_almost_full),
        .reg_cmd_fifo_empty(reg_cmd_fifo_empty),
        .reg_cmd_fifo_almost_empty(reg_cmd_fifo_almost_empty),
        .reg_cmd_fifo_valid(reg_cmd_fifo_valid),
        .reg_cmd_fifo_data_count(reg_cmd_fifo_data_count),
        .tx_data_fifo_wr_en(tx_data_fifo_wr_en),
        .tx_data_fifo_wr_data(tx_data_fifo_wr_data),
        .tx_data_fifo_wr_ready(tx_data_fifo_wr_ready),
        .tx_data_fifo_full(tx_data_fifo_full),
        .tx_data_fifo_almost_full(tx_data_fifo_almost_full),
        .tx_data_fifo_data_count(tx_data_fifo_data_count),
        .tx_data_fifo_free_words(tx_data_fifo_free_words),
        .tx_reg_cmd_fifo_wr_en(tx_reg_cmd_fifo_wr_en),
        .tx_reg_cmd_fifo_wr_data(tx_reg_cmd_fifo_wr_data),
        .tx_reg_cmd_fifo_wr_ready(tx_reg_cmd_fifo_wr_ready),
        .tx_reg_cmd_fifo_full(tx_reg_cmd_fifo_full),
        .tx_reg_cmd_fifo_almost_full(tx_reg_cmd_fifo_almost_full),
        .tx_reg_cmd_fifo_data_count(tx_reg_cmd_fifo_data_count),
        .usb_tx_fifo_free_words(usb_tx_fifo_free_words),
        .rx_start_stream_valid(rx_start_stream_valid),
        .rx_stop_stream_valid(rx_stop_stream_valid),
        .rx_frame_error(rx_frame_error)
    );

    task automatic ft601_write_word(input logic [31:0] word);
        ft601_burst_begin(word);
        ft601_burst_end();
    endtask

    task automatic ft601_burst_begin(input logic [31:0] word);
        @(negedge FT601_clk);
        ft601_drive_data = word;
        ft601_drive_en   = 1'b1;
        FT601_RXF_N      = 1'b0;
    endtask

    task automatic ft601_wait_accept;
        do begin
            @(posedge FT601_clk);
            #1;
        end while (!(FT601_OE_N == 1'b0 && FT601_RD_N == 1'b0));
    endtask

    task automatic ft601_burst_next(input logic [31:0] word);
        ft601_wait_accept();
        @(negedge FT601_clk);
        ft601_drive_data = word;
    endtask

    task automatic ft601_burst_end;
        ft601_wait_accept();
        @(negedge FT601_clk);
        ft601_drive_en   = 1'b0;
        FT601_RXF_N      = 1'b1;
        ft601_drive_data = 32'd0;
    endtask

    task automatic send_header(input logic [7:0] frame_type, input logic [31:0] len);
        ft601_write_word(FRAME_MAGIC);
        ft601_write_word({24'd0, frame_type});
        ft601_write_word(len);
    endtask

    task automatic send_write_reg(input logic [9:0] addr, input logic [7:0] data);
        send_header(FRAME_TYPE_WRITE_REG, 32'd1);
        ft601_write_word({14'd0, data, addr});
    endtask

    task automatic send_read_reg(input logic [9:0] addr);
        send_header(FRAME_TYPE_READ_REG, 32'd1);
        ft601_write_word({22'd0, addr});
    endtask

    task automatic send_start_stream;
        send_header(FRAME_TYPE_START_STREAM, 32'd0);
    endtask

    task automatic send_stop_stream;
        send_header(FRAME_TYPE_STOP_STREAM, 32'd0);
    endtask

    function automatic logic [31:0] make_reg_cmd(
        input logic [3:0] cmd_type,
        input logic [9:0] addr,
        input logic [7:0] data
    );
        make_reg_cmd = {cmd_type, addr, data, 10'd0};
    endfunction

    task automatic read_and_check_reg_cmd(input logic [31:0] expected_cmd);
        int timeout;

        timeout = 0;
        while (reg_cmd_fifo_empty) begin
            @(posedge sys_clk);
            timeout++;
            if (timeout > 10000) begin
                $fatal(1, "timeout waiting for reg cmd fifo data");
            end
        end

        reg_cmd_fifo_rd_en <= 1'b1;
        @(posedge sys_clk);
        reg_cmd_fifo_rd_en <= 1'b0;

        timeout = 0;
        while (!reg_cmd_fifo_valid) begin
            @(posedge sys_clk);
            timeout++;
            if (timeout > 10000) begin
                $fatal(1, "timeout waiting for reg cmd fifo valid");
            end
        end

        assert(reg_cmd_fifo_rd_data == expected_cmd)
            else $fatal(1, "reg cmd fifo check failed: got %h expected %h",
                        reg_cmd_fifo_rd_data, expected_cmd);

        @(posedge sys_clk);
    endtask

    task automatic send_data(input int words, input int base);
        send_header(FRAME_TYPE_TX_DATA, words);
        for (int i = 0; i < words; i++) begin
            ft601_write_word(32'hD0000000 + base + i);
        end
    endtask

    task automatic send_reg_command_burst;
        logic [9:0] addr;
        logic [7:0] data;

        ft601_burst_begin(FRAME_MAGIC);

        for (int i = 0; i < REG_CMD_COUNT; i++) begin
            addr = READ_REG_BASE + i;
            if (i != 0) begin
                ft601_burst_next(FRAME_MAGIC);
            end
            ft601_burst_next({24'd0, FRAME_TYPE_READ_REG});
            ft601_burst_next(32'd1);
            ft601_burst_next({22'd0, addr});
        end

        for (int i = 0; i < REG_CMD_COUNT; i++) begin
            addr = WRITE_REG_BASE + i;
            data = WRITE_DATA_BASE + i;
            ft601_burst_next(FRAME_MAGIC);
            ft601_burst_next({24'd0, FRAME_TYPE_WRITE_REG});
            ft601_burst_next(32'd1);
            ft601_burst_next({14'd0, data, addr});
        end

        ft601_burst_end();
    endtask

    task automatic read_and_check_data(input int words);
        int count;

        count = 0;
        rx_data_fifo_rd_en = 1'b0;
        while (count < words) begin
            @(posedge sys_clk);
            rx_data_fifo_rd_en <= !rx_data_fifo_empty;

            if (rx_data_fifo_valid) begin
                assert(rx_data_fifo_rd_data == 32'hD0000000 + count)
                    else $fatal(1, "data mismatch: got %h expected %h",
                                rx_data_fifo_rd_data, 32'hD0000000 + count);
                count++;
            end
        end
        rx_data_fifo_rd_en = 1'b0;
    endtask

    task automatic ft601_read_tx_word(output logic [31:0] word);
        int timeout;

        timeout = 0;
        do begin
            @(posedge FT601_clk);
            #1;
            timeout++;
            if (timeout > 10000) begin
                $fatal(1, "timeout waiting for FT601 TX word");
            end
        end while (FT601_WR_N != 1'b0);

        word = FT601_DATA;
    endtask

    task automatic read_and_check_tx_word(input logic [31:0] expected_word);
        logic [31:0] word;

        ft601_read_tx_word(word);
        assert(word == expected_word)
            else $fatal(1, "tx word mismatch: got %h expected %h",
                        word, expected_word);
    endtask

    task automatic push_tx_reg_data(input logic [31:0] reg_data);
        while (!tx_reg_cmd_fifo_wr_ready) begin
            @(posedge sys_clk);
        end

        tx_reg_cmd_fifo_wr_data <= reg_data;
        tx_reg_cmd_fifo_wr_en   <= 1'b1;
        @(posedge sys_clk);
        tx_reg_cmd_fifo_wr_en   <= 1'b0;
        tx_reg_cmd_fifo_wr_data <= 32'd0;
    endtask

    task automatic push_tx_data_packet(input int words, input int base);
        for (int i = 0; i < words; i++) begin
            while (!tx_data_fifo_wr_ready) begin
                @(posedge sys_clk);
            end

            tx_data_fifo_wr_data <= 32'hE0000000 + base + i;
            tx_data_fifo_wr_en   <= 1'b1;
            @(posedge sys_clk);
            tx_data_fifo_wr_en   <= 1'b0;
        end
        tx_data_fifo_wr_data <= 32'd0;
    endtask

    task automatic read_and_check_tx_reg_data(input logic [31:0] reg_data);
        read_and_check_tx_word(FRAME_MAGIC);
        read_and_check_tx_word({24'd0, TX_FRAME_TYPE_REG_DATA});
        read_and_check_tx_word(32'd1);
        read_and_check_tx_word(reg_data);
    endtask

    task automatic read_and_check_tx_data(input int words, input int base);
        logic [31:0] word;

        read_and_check_tx_word(FRAME_MAGIC);
        ft601_read_tx_word(word);
        assert(word[7:0] == FRAME_TYPE_TX_DATA)
            else $fatal(1, "tx data info type mismatch: got %h", word);
        assert(word[18:8] == dut.u_usb_packet_layer.rx_data_fifo_free_words)
            else $fatal(1, "tx data info rx free mismatch: got %0d expected %0d",
                        word[18:8], dut.u_usb_packet_layer.rx_data_fifo_free_words);
        read_and_check_tx_word(words);

        for (int i = 0; i < words; i++) begin
            read_and_check_tx_word(32'hE0000000 + base + i);
        end
    endtask

    task automatic read_and_check_tx_ack(input logic [7:0] acked_frame_type);
        read_and_check_tx_word(FRAME_MAGIC);
        read_and_check_tx_word({24'd0, TX_FRAME_TYPE_ACK});
        read_and_check_tx_word(32'd1);
        read_and_check_tx_word({24'd0, acked_frame_type});
    endtask

    task automatic wait_fifo_pressure;
        int timeout;

        timeout = 0;
        while (rx_data_fifo_data_count < BACKPRESSURE_COUNT ||
                dut.u_usb_fifo_layer.rx_fifo_empty) begin
            @(posedge sys_clk);
            timeout++;
            if (timeout > 100000) begin
                $fatal(1, "timeout waiting for fifo pressure");
            end
        end

        repeat (100) @(posedge sys_clk);

        $display("before drain: rx_data_count=%0d rx_data_almost_full=%0b rx_fifo_empty=%0b rx_fifo_almost_empty=%0b",
                 rx_data_fifo_data_count,
                 dut.u_usb_packet_layer.rx_data_fifo_almost_full,
                 dut.u_usb_fifo_layer.rx_fifo_empty,
                 dut.u_usb_fifo_layer.rx_fifo_almost_empty);

        if (rx_data_fifo_data_count < BACKPRESSURE_COUNT) begin
            $display("note: rx_data_fifo did not reach backpressure count %0d",
                     BACKPRESSURE_COUNT);
        end

        if (dut.u_usb_packet_layer.rx_data_fifo_full) begin
            $display("rx_data_fifo is full");
        end else begin
            $display("rx_data_fifo is not full; packet layer stopped before full");
        end
    endtask

    initial begin
        rx_data_fifo_rd_en = 1'b0;
        reg_cmd_fifo_rd_en = 1'b0;
        tx_data_fifo_wr_en = 1'b0;
        tx_data_fifo_wr_data = 32'd0;
        tx_reg_cmd_fifo_wr_en = 1'b0;
        tx_reg_cmd_fifo_wr_data = 32'd0;

        repeat (20) @(posedge sys_clk);
        rst_n = 1'b1;
        repeat (20) @(posedge sys_clk);

        send_reg_command_burst();

        for (int i = 0; i < REG_CMD_COUNT; i++) begin
            read_and_check_reg_cmd(make_reg_cmd(REG_CMD_READ, READ_REG_BASE + i, 8'd0));
        end

        for (int i = 0; i < REG_CMD_COUNT; i++) begin
            read_and_check_reg_cmd(make_reg_cmd(REG_CMD_WRITE, WRITE_REG_BASE + i, WRITE_DATA_BASE + i));
        end

        fork
            begin
                for (int pkt = 0; pkt < DATA_PACKETS; pkt++) begin
                    send_data(DATA_WORDS, pkt * DATA_WORDS);
                end
                data_send_done = 1'b1;
            end

            begin
                wait_fifo_pressure();
                read_and_check_data(TOTAL_DATA_WORDS);
            end
        join

        FT601_TXE_N = 1'b0;

        push_tx_reg_data(32'h12345678);
        read_and_check_tx_reg_data(32'h12345678);

        push_tx_data_packet(DATA_WORDS, 0);
        read_and_check_tx_data(DATA_WORDS, 0);

        send_start_stream();
        read_and_check_tx_ack(FRAME_TYPE_START_STREAM);

        send_stop_stream();
        read_and_check_tx_ack(FRAME_TYPE_STOP_STREAM);

        FT601_TXE_N = 1'b1;

        assert(!rx_frame_error)
            else $fatal(1, "rx_frame_error asserted");

        $display("tb_usb_rx_top PASS");
        $finish;
    end

endmodule
