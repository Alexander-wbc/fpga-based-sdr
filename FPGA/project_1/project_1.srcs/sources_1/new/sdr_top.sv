`timescale 1ns / 1ps

// Board-level integration: FT601 transport, packet processing, AD9363 wrapper
// and the bidirectional IQ stream bridge.
module sdr_top (
    input  logic        rst_n,
    input  logic        sys_clk,

    input  logic        FT601_clk,
    inout  wire  [31:0] FT601_DATA,
    inout  wire  [3:0]  FT601_BE,
    input  logic        FT601_TXE_N,
    input  logic        FT601_RXF_N,
    output logic        FT601_WR_N,
    output logic        FT601_RD_N,
    output logic        FT601_OE_N,
    output logic        FT601_SIWU_N,

    input  logic        ad9363_data_clk,
    input  logic        ad9363_rx_frame,
    input  logic [11:0] ad9363_p0_rx_data,
    output logic        ad9363_fb_clk,
    output logic        ad9363_tx_frame,
    output logic [11:0] ad9363_p1_tx_data,
    output logic        ad9363_enable,
    output logic        ad9363_txnrx,

    output logic        ad9363_spi_csn,
    output logic        ad9363_spi_sclk,
    output logic        ad9363_spi_mosi,
    input  logic        ad9363_spi_miso
);

    // PC -> AD9363 packet data FIFO
    logic        pc_tx_fifo_rd_en;
    logic [31:0] pc_tx_fifo_rd_data;
    logic        pc_tx_fifo_empty;
    logic        pc_tx_fifo_almost_empty;
    logic        pc_tx_fifo_valid;
    logic [9:0]  pc_tx_fifo_data_count;

    // AD9363 -> PC packet data FIFO
    logic        pc_rx_fifo_wr_en;
    logic [31:0] pc_rx_fifo_wr_data;
    logic        pc_rx_fifo_wr_ready;
    logic        pc_rx_fifo_full;
    logic        pc_rx_fifo_almost_full;
    logic [9:0]  pc_rx_fifo_data_count;
    logic [10:0] pc_rx_fifo_free_words;
    logic [10:0] usb_tx_fifo_free_words;

    // Packet Layer <-> AD9363 SPI
    logic        reg_cmd_fifo_rd_en;
    logic [31:0] reg_cmd_fifo_rd_data;
    logic        reg_cmd_fifo_full;
    logic        reg_cmd_fifo_almost_full;
    logic        reg_cmd_fifo_empty;
    logic        reg_cmd_fifo_almost_empty;
    logic        reg_cmd_fifo_valid;
    logic [6:0]  reg_cmd_fifo_data_count;
    logic        tx_reg_cmd_fifo_wr_en;
    logic [31:0] tx_reg_cmd_fifo_wr_data;
    logic        tx_reg_cmd_fifo_wr_ready;
    logic        tx_reg_cmd_fifo_full;
    logic        tx_reg_cmd_fifo_almost_full;
    logic [6:0]  tx_reg_cmd_fifo_data_count;

    // AD9363 data-interface CDC FIFOs
    logic        ad_rx_fifo_rd_en;
    logic [23:0] ad_rx_fifo_data;
    logic        ad_rx_fifo_empty;
    logic        ad_rx_fifo_almost_empty;
    logic        ad_rx_fifo_valid;
    logic [6:0]  ad_rx_fifo_data_count;
    logic        ad_rx_fifo_overflow;
    logic        ad_tx_fifo_wr_en;
    logic [23:0] ad_tx_fifo_data;
    logic        ad_tx_fifo_wr_ready;
    logic        ad_tx_fifo_full;
    logic        ad_tx_fifo_almost_full;
    logic [6:0]  ad_tx_fifo_data_count;
    logic        ad_tx_fifo_underflow;

    logic        start_stream;
    logic        stop_stream;
    logic        stream_active;
    logic        rx_frame_error;
    logic        ad9363_spi_busy;

    // FT601 clock-domain crossing FIFO interface
    logic        usb_rx_fifo_rd_en;
    logic [31:0] usb_rx_fifo_rd_data;
    logic        usb_rx_fifo_empty;
    logic        usb_rx_fifo_almost_empty;
    logic        usb_rx_fifo_valid;
    logic        usb_tx_fifo_wr_en;
    logic [31:0] usb_tx_fifo_wr_data;
    logic        usb_tx_fifo_full;
    logic        usb_tx_fifo_almost_full;

    // One-word holding registers for the two standard-read FIFO paths.
    logic        pc_tx_read_pending;
    logic        pc_tx_word_valid;
    logic [23:0] pc_tx_word;
    logic        ad_rx_read_pending;
    logic        ad_rx_word_valid;
    logic [23:0] ad_rx_word;

    usb_fifo_layer u_usb_fifo_layer (
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
        .rx_fifo_rd_en(usb_rx_fifo_rd_en),
        .rx_fifo_rd_data(usb_rx_fifo_rd_data),
        .rx_fifo_empty(usb_rx_fifo_empty),
        .rx_fifo_almost_empty(usb_rx_fifo_almost_empty),
        .rx_fifo_valid(usb_rx_fifo_valid),
        .tx_fifo_wr_en(usb_tx_fifo_wr_en),
        .tx_fifo_wr_data(usb_tx_fifo_wr_data),
        .tx_fifo_full(usb_tx_fifo_full),
        .tx_fifo_almost_full(usb_tx_fifo_almost_full),
        .tx_fifo_free_words(usb_tx_fifo_free_words)
    );

    usb_packet_layer u_usb_packet_layer (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .rx_fifo_rd_en(usb_rx_fifo_rd_en),
        .rx_fifo_rd_data(usb_rx_fifo_rd_data),
        .rx_fifo_empty(usb_rx_fifo_empty),
        .rx_fifo_valid(usb_rx_fifo_valid),
        .tx_fifo_wr_en(usb_tx_fifo_wr_en),
        .tx_fifo_wr_data(usb_tx_fifo_wr_data),
        .tx_fifo_full(usb_tx_fifo_full),
        .tx_fifo_almost_full(usb_tx_fifo_almost_full),
        .tx_fifo_free_words(usb_tx_fifo_free_words),
        .rx_data_fifo_rd_en(pc_tx_fifo_rd_en),
        .rx_data_fifo_rd_data(pc_tx_fifo_rd_data),
        .rx_data_fifo_empty(pc_tx_fifo_empty),
        .rx_data_fifo_almost_empty(pc_tx_fifo_almost_empty),
        .rx_data_fifo_valid(pc_tx_fifo_valid),
        .rx_data_fifo_data_count(pc_tx_fifo_data_count),
        .reg_cmd_fifo_rd_en(reg_cmd_fifo_rd_en),
        .reg_cmd_fifo_rd_data(reg_cmd_fifo_rd_data),
        .reg_cmd_fifo_full(reg_cmd_fifo_full),
        .reg_cmd_fifo_almost_full(reg_cmd_fifo_almost_full),
        .reg_cmd_fifo_empty(reg_cmd_fifo_empty),
        .reg_cmd_fifo_almost_empty(reg_cmd_fifo_almost_empty),
        .reg_cmd_fifo_valid(reg_cmd_fifo_valid),
        .reg_cmd_fifo_data_count(reg_cmd_fifo_data_count),
        .tx_data_fifo_wr_en(pc_rx_fifo_wr_en),
        .tx_data_fifo_wr_data(pc_rx_fifo_wr_data),
        .tx_data_fifo_wr_ready(pc_rx_fifo_wr_ready),
        .tx_data_fifo_full(pc_rx_fifo_full),
        .tx_data_fifo_almost_full(pc_rx_fifo_almost_full),
        .tx_data_fifo_data_count(pc_rx_fifo_data_count),
        .tx_data_fifo_free_words(pc_rx_fifo_free_words),
        .tx_reg_cmd_fifo_wr_en(tx_reg_cmd_fifo_wr_en),
        .tx_reg_cmd_fifo_wr_data(tx_reg_cmd_fifo_wr_data),
        .tx_reg_cmd_fifo_wr_ready(tx_reg_cmd_fifo_wr_ready),
        .tx_reg_cmd_fifo_full(tx_reg_cmd_fifo_full),
        .tx_reg_cmd_fifo_almost_full(tx_reg_cmd_fifo_almost_full),
        .tx_reg_cmd_fifo_data_count(tx_reg_cmd_fifo_data_count),
        .rx_start_stream_valid(start_stream),
        .rx_stop_stream_valid(stop_stream),
        .rx_frame_error(rx_frame_error)
    );

    ad9363_top u_ad9363_top (
        .rst_n(rst_n),
        .sys_clk(sys_clk),
        .ad9363_data_clk(ad9363_data_clk),
        .ad9363_rx_frame(ad9363_rx_frame),
        .ad9363_p0_rx_data(ad9363_p0_rx_data),
        .ad9363_fb_clk(ad9363_fb_clk),
        .ad9363_tx_frame(ad9363_tx_frame),
        .ad9363_p1_tx_data(ad9363_p1_tx_data),
        .ad9363_enable(ad9363_enable),
        .ad9363_txnrx(ad9363_txnrx),
        .ad9363_spi_csn(ad9363_spi_csn),
        .ad9363_spi_sclk(ad9363_spi_sclk),
        .ad9363_spi_mosi(ad9363_spi_mosi),
        .ad9363_spi_miso(ad9363_spi_miso),
        .ad9363_spi_busy(ad9363_spi_busy),
        .reg_cmd_fifo_rd_en(reg_cmd_fifo_rd_en),
        .reg_cmd_fifo_rd_data(reg_cmd_fifo_rd_data),
        .reg_cmd_fifo_empty(reg_cmd_fifo_empty),
        .reg_cmd_fifo_valid(reg_cmd_fifo_valid),
        .tx_reg_cmd_fifo_wr_en(tx_reg_cmd_fifo_wr_en),
        .tx_reg_cmd_fifo_wr_data(tx_reg_cmd_fifo_wr_data),
        .tx_reg_cmd_fifo_wr_ready(tx_reg_cmd_fifo_wr_ready),
        .rx_fifo_rd_en(ad_rx_fifo_rd_en),
        .rx_fifo_data(ad_rx_fifo_data),
        .rx_fifo_empty(ad_rx_fifo_empty),
        .rx_fifo_almost_empty(ad_rx_fifo_almost_empty),
        .rx_fifo_valid(ad_rx_fifo_valid),
        .rx_fifo_data_count(ad_rx_fifo_data_count),
        .rx_fifo_overflow(ad_rx_fifo_overflow),
        .tx_fifo_wr_en(ad_tx_fifo_wr_en),
        .tx_fifo_data(ad_tx_fifo_data),
        .tx_fifo_wr_ready(ad_tx_fifo_wr_ready),
        .tx_fifo_full(ad_tx_fifo_full),
        .tx_fifo_almost_full(ad_tx_fifo_almost_full),
        .tx_fifo_data_count(ad_tx_fifo_data_count),
        .tx_fifo_underflow(ad_tx_fifo_underflow)
    );

    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            stream_active <= 1'b0;
        end else begin
            if (start_stream) stream_active <= 1'b1;
            if (stop_stream)  stream_active <= 1'b0;
        end
    end

    // PC -> AD9363: only consume Packet Layer data when the AD9363 TX CDC
    // FIFO has room.  The holding register covers standard FIFO read latency.
    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_tx_fifo_rd_en   <= 1'b0;
            pc_tx_read_pending <= 1'b0;
            pc_tx_word_valid   <= 1'b0;
            pc_tx_word         <= 24'd0;
            ad_tx_fifo_wr_en   <= 1'b0;
            ad_tx_fifo_data    <= 24'd0;
        end else begin
            pc_tx_fifo_rd_en <= 1'b0;
            ad_tx_fifo_wr_en <= 1'b0;

            if (pc_tx_fifo_valid) begin
                pc_tx_word         <= pc_tx_fifo_rd_data[23:0];
                pc_tx_word_valid   <= 1'b1;
                pc_tx_read_pending <= 1'b0;
            end

            if (pc_tx_word_valid && ad_tx_fifo_wr_ready) begin
                ad_tx_fifo_wr_en <= 1'b1;
                ad_tx_fifo_data  <= pc_tx_word;
                pc_tx_word_valid <= 1'b0;
            end

            if (!pc_tx_word_valid && !pc_tx_read_pending &&
                    !pc_tx_fifo_valid && !pc_tx_fifo_empty &&
                    ad_tx_fifo_wr_ready) begin
                pc_tx_fifo_rd_en   <= 1'b1;
                pc_tx_read_pending <= 1'b1;
            end
        end
    end

    // AD9363 -> PC: only consume RX samples when Packet Layer has room.
    // While stopped, drain and discard samples so the next START is current.
    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            ad_rx_fifo_rd_en   <= 1'b0;
            ad_rx_read_pending <= 1'b0;
            ad_rx_word_valid   <= 1'b0;
            ad_rx_word         <= 24'd0;
            pc_rx_fifo_wr_en   <= 1'b0;
            pc_rx_fifo_wr_data <= 32'd0;
        end else begin
            ad_rx_fifo_rd_en <= 1'b0;
            pc_rx_fifo_wr_en <= 1'b0;

            if (ad_rx_fifo_valid) begin
                ad_rx_read_pending <= 1'b0;
                if (stream_active) begin
                    ad_rx_word       <= ad_rx_fifo_data;
                    ad_rx_word_valid <= 1'b1;
                end
            end

            if (!stream_active) begin
                ad_rx_word_valid <= 1'b0;
            end else if (ad_rx_word_valid && pc_rx_fifo_wr_ready) begin
                pc_rx_fifo_wr_en   <= 1'b1;
                pc_rx_fifo_wr_data <= {8'd0, ad_rx_word};
                ad_rx_word_valid   <= 1'b0;
            end

            if (!ad_rx_word_valid && !ad_rx_read_pending &&
                    !ad_rx_fifo_valid && !ad_rx_fifo_empty &&
                    (!stream_active || pc_rx_fifo_wr_ready)) begin
                ad_rx_fifo_rd_en   <= 1'b1;
                ad_rx_read_pending <= 1'b1;
            end
        end
    end

endmodule
