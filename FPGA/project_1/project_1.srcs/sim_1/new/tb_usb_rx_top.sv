`timescale 1ns / 1ps

module tb_usb_rx_top;

    localparam logic [31:0] FRAME_MAGIC          = 32'hAAAA5555;
    localparam logic [7:0]  FRAME_TYPE_WRITE_REG = 8'h01;
    localparam logic [7:0]  FRAME_TYPE_READ_REG  = 8'h02;
    localparam logic [7:0]  FRAME_TYPE_TX_DATA   = 8'h10;
    localparam int          DATA_WORDS           = 256;
    localparam int          DATA_PACKETS         = 5;
    localparam int          TOTAL_DATA_WORDS     = DATA_WORDS * DATA_PACKETS;
    localparam int          BACKPRESSURE_COUNT   = 1024 - (DATA_WORDS / 2) + 1;

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

    logic        reg_write_start;
    logic [9:0]  reg_addr;
    logic [7:0]  reg_write_data;
    logic        reg_read_start;
    logic        write_reg_fifo_rd_en;
    logic [17:0] write_reg_fifo_rd_data;
    logic        write_reg_fifo_full;
    logic        write_reg_fifo_almost_full;
    logic        write_reg_fifo_empty;
    logic        write_reg_fifo_almost_empty;
    logic        write_reg_fifo_valid;
    logic [6:0]  write_reg_fifo_data_count;
    logic        rx_start_stream_valid;
    logic        rx_stop_stream_valid;
    logic        rx_frame_error;

    logic        ft601_drive_en = 1'b0;
    logic [31:0] ft601_drive_data = 32'd0;
    logic        data_send_done = 1'b0;

    assign FT601_DATA = ft601_drive_en ? ft601_drive_data : 32'hZZZZ_ZZZZ;
    assign FT601_BE   = ft601_drive_en ? 4'hF : 4'hZ;

    always #5 sys_clk = ~sys_clk;
    always #4 FT601_clk = ~FT601_clk;

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
        .reg_write_start(reg_write_start),
        .reg_addr(reg_addr),
        .reg_write_data(reg_write_data),
        .reg_read_start(reg_read_start),
        .write_reg_fifo_rd_en(write_reg_fifo_rd_en),
        .write_reg_fifo_rd_data(write_reg_fifo_rd_data),
        .write_reg_fifo_full(write_reg_fifo_full),
        .write_reg_fifo_almost_full(write_reg_fifo_almost_full),
        .write_reg_fifo_empty(write_reg_fifo_empty),
        .write_reg_fifo_almost_empty(write_reg_fifo_almost_empty),
        .write_reg_fifo_valid(write_reg_fifo_valid),
        .write_reg_fifo_data_count(write_reg_fifo_data_count),
        .rx_start_stream_valid(rx_start_stream_valid),
        .rx_stop_stream_valid(rx_stop_stream_valid),
        .rx_frame_error(rx_frame_error)
    );

    task automatic ft601_write_word(input logic [31:0] word);
        @(negedge FT601_clk);
        ft601_drive_data = word;
        ft601_drive_en   = 1'b1;
        FT601_RXF_N      = 1'b0;

        wait (FT601_OE_N == 1'b0 && FT601_RD_N == 1'b0);
        @(negedge FT601_clk);
        ft601_drive_en = 1'b0;
        FT601_RXF_N    = 1'b1;
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

    task automatic send_data(input int words, input int base);
        send_header(FRAME_TYPE_TX_DATA, words);
        for (int i = 0; i < words; i++) begin
            ft601_write_word(32'hD0000000 + base + i);
        end
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
        write_reg_fifo_rd_en = 1'b0;

        repeat (20) @(posedge sys_clk);
        rst_n = 1'b1;
        repeat (20) @(posedge sys_clk);

        send_write_reg(10'h155, 8'hA5);
        wait (reg_write_start);
        assert(reg_addr == 10'h155 && reg_write_data == 8'hA5)
            else $fatal(1, "write reg check failed");

        wait (!write_reg_fifo_empty);
        write_reg_fifo_rd_en <= 1'b1;
        @(posedge sys_clk);
        write_reg_fifo_rd_en <= 1'b0;
        wait (write_reg_fifo_valid);
        assert(write_reg_fifo_rd_data == {8'hA5, 10'h155})
            else $fatal(1, "write reg fifo check failed: %h", write_reg_fifo_rd_data);

        send_read_reg(10'h2AA);
        wait (reg_read_start);
        assert(reg_addr == 10'h2AA)
            else $fatal(1, "read reg check failed");

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

        assert(!rx_frame_error)
            else $fatal(1, "rx_frame_error asserted");

        $display("tb_usb_rx_top PASS");
        $finish;
    end

endmodule
