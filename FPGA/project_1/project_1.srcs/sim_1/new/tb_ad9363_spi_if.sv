`timescale 1ns / 1ps

module tb_ad9363_spi_if;

    localparam logic [7:0] READ_DATA = 8'h3C;

    logic        sys_clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        reg_cmd_fifo_rd_en;
    logic [31:0] reg_cmd_fifo_rd_data = 32'd0;
    logic        reg_cmd_fifo_empty = 1'b1;
    logic        reg_cmd_fifo_valid = 1'b0;
    logic        tx_reg_cmd_fifo_wr_en;
    logic [31:0] tx_reg_cmd_fifo_wr_data;
    logic        tx_reg_cmd_fifo_wr_ready = 1'b1;
    logic        spi_csn;
    logic        spi_sclk;
    logic        spi_mosi;
    logic        spi_miso = 1'b0;
    logic        busy;

    logic [23:0] captured_mosi;
    integer      captured_bits;
    integer      slave_falling_edges;
    time         previous_rising_edge;

    always #10 sys_clk = ~sys_clk;

    ad9363_spi_if dut (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .reg_cmd_fifo_rd_en(reg_cmd_fifo_rd_en),
        .reg_cmd_fifo_rd_data(reg_cmd_fifo_rd_data),
        .reg_cmd_fifo_empty(reg_cmd_fifo_empty),
        .reg_cmd_fifo_valid(reg_cmd_fifo_valid),
        .tx_reg_cmd_fifo_wr_en(tx_reg_cmd_fifo_wr_en),
        .tx_reg_cmd_fifo_wr_data(tx_reg_cmd_fifo_wr_data),
        .tx_reg_cmd_fifo_wr_ready(tx_reg_cmd_fifo_wr_ready),
        .spi_csn(spi_csn),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .busy(busy)
    );

    always @(negedge spi_csn) begin
        captured_mosi       = 24'd0;
        captured_bits       = 0;
        slave_falling_edges = 0;
        previous_rising_edge = 0;
        spi_miso            = 1'b0;
    end

    always @(posedge spi_sclk) begin
        if (!spi_csn) begin
            if (previous_rising_edge != 0) begin
                assert(($time - previous_rising_edge) == 100ns)
                    else $fatal(1, "SPI period is %0t, expected 100 ns",
                                $time - previous_rising_edge);
            end
            previous_rising_edge = $time;

            // UG-1040: AD9363 launches SPI_DO on the rising edge and the
            // baseband processor samples it on the falling edge.
            if (slave_falling_edges >= 16 && slave_falling_edges < 24) begin
                spi_miso = READ_DATA[23 - slave_falling_edges];
            end else begin
                spi_miso = 1'b0;
            end
        end
    end

    // UG-1040: AD9363 samples SPI_DI on falling edges.  Read data occupies
    // transfer bits 16 through 23.
    always @(negedge spi_sclk) begin
        if (!spi_csn) begin
            captured_mosi = {captured_mosi[22:0], spi_mosi};
            captured_bits = captured_bits + 1;
            slave_falling_edges = slave_falling_edges + 1;
        end
    end

    task automatic send_command(input logic [31:0] command);
        int timeout;

        reg_cmd_fifo_rd_data = command;
        reg_cmd_fifo_empty   = 1'b0;
        timeout = 0;
        while (!reg_cmd_fifo_rd_en) begin
            @(posedge sys_clk);
            timeout++;
            if (timeout > 20) begin
                $fatal(1, "timeout waiting for command FIFO read");
            end
        end

        @(posedge sys_clk);
        reg_cmd_fifo_empty = 1'b1;
        reg_cmd_fifo_valid = 1'b1;
        @(posedge sys_clk);
        reg_cmd_fifo_valid = 1'b0;
    endtask

    task automatic wait_transfer_done;
        int timeout;

        timeout = 0;
        while (spi_csn) begin
            @(posedge sys_clk);
            timeout++;
            if (timeout > 20) begin
                $fatal(1, "timeout waiting for SPI CS assertion");
            end
        end

        while (!spi_csn) begin
            @(posedge sys_clk);
            timeout++;
            if (timeout > 200) begin
                $fatal(1, "timeout waiting for SPI transfer completion");
            end
        end

        assert(captured_bits == 24)
            else $fatal(1, "captured %0d SPI bits, expected 24", captured_bits);
    endtask

    initial begin
        repeat (5) @(posedge sys_clk);
        rst_n = 1'b1;
        repeat (2) @(posedge sys_clk);

        // Write register 0x155 = 0xA5.  Writes do not enter TX_REG_DATA.
        send_command({1'b1, 13'd0, 8'hA5, 10'h155});
        wait_transfer_done();
        assert(captured_mosi == {1'b1, 5'd0, 10'h155, 8'hA5})
            else $fatal(1, "write frame mismatch: %h", captured_mosi);
        assert(!tx_reg_cmd_fifo_wr_en)
            else $fatal(1, "write command unexpectedly returned data");

        repeat (2) @(posedge sys_clk);

        // Read register 0x2AA and hold return FIFO backpressure briefly.
        tx_reg_cmd_fifo_wr_ready = 1'b0;
        send_command({1'b0, 13'd0, 8'd0, 10'h2AA});
        wait_transfer_done();
        assert(captured_mosi == {1'b0, 5'd0, 10'h2AA, 8'd0})
            else $fatal(1, "read frame mismatch: %h", captured_mosi);
        repeat (5) @(posedge sys_clk);
        assert(!tx_reg_cmd_fifo_wr_en)
            else $fatal(1, "return FIFO backpressure was ignored");

        @(negedge sys_clk);
        tx_reg_cmd_fifo_wr_ready = 1'b1;
        @(posedge sys_clk);
        #1;
        assert(tx_reg_cmd_fifo_wr_en)
            else $fatal(1, "missing read result write enable");
        assert(tx_reg_cmd_fifo_wr_data == {14'd0, READ_DATA, 10'h2AA})
            else $fatal(1, "read result mismatch: %h", tx_reg_cmd_fifo_wr_data);

        $display("tb_ad9363_spi_if PASS");
        $finish;
    end

endmodule
