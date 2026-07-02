`timescale 1ns / 1ps

// AD9363 device wrapper.  USB and system-level stream routing belong in
// sdr_top; this module only groups the SPI and parallel data interfaces.
module ad9363_top (
    input  logic        rst_n,
    input  logic        sys_clk,

    // AD9363 CMOS dual-port, full-duplex data interface
    input  logic        ad9363_data_clk,
    input  logic        ad9363_rx_frame,
    input  logic [11:0] ad9363_p0_rx_data,
    output logic        ad9363_fb_clk,
    output logic        ad9363_tx_frame,
    output logic [11:0] ad9363_p1_tx_data,
    output logic        ad9363_enable,
    output logic        ad9363_txnrx,

    // AD9363 software-controlled SPI interface
    output logic        ad9363_spi_csn,
    output logic        ad9363_spi_sclk,
    output logic        ad9363_spi_mosi,
    input  logic        ad9363_spi_miso,
    output logic        ad9363_spi_busy,

    // SPI command FIFO: Packet Layer -> AD9363
    output logic        reg_cmd_fifo_rd_en,
    input  logic [31:0] reg_cmd_fifo_rd_data,
    input  logic        reg_cmd_fifo_empty,
    input  logic        reg_cmd_fifo_valid,

    // SPI result FIFO: AD9363 -> Packet Layer
    output logic        tx_reg_cmd_fifo_wr_en,
    output logic [31:0] tx_reg_cmd_fifo_wr_data,
    input  logic        tx_reg_cmd_fifo_wr_ready,

    // Received IQ FIFO: AD9363 -> sys_clk
    input  logic        rx_fifo_rd_en,
    output logic [23:0] rx_fifo_data,
    output logic        rx_fifo_empty,
    output logic        rx_fifo_almost_empty,
    output logic        rx_fifo_valid,
    output logic [6:0]  rx_fifo_data_count,
    output logic        rx_fifo_overflow,

    // Transmit IQ FIFO: sys_clk -> AD9363
    input  logic        tx_fifo_wr_en,
    input  logic [23:0] tx_fifo_data,
    output logic        tx_fifo_wr_ready,
    output logic        tx_fifo_full,
    output logic        tx_fifo_almost_full,
    output logic [6:0]  tx_fifo_data_count,
    output logic        tx_fifo_underflow
);

    ad9363_spi_if u_ad9363_spi_if (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .reg_cmd_fifo_rd_en(reg_cmd_fifo_rd_en),
        .reg_cmd_fifo_rd_data(reg_cmd_fifo_rd_data),
        .reg_cmd_fifo_empty(reg_cmd_fifo_empty),
        .reg_cmd_fifo_valid(reg_cmd_fifo_valid),
        .tx_reg_cmd_fifo_wr_en(tx_reg_cmd_fifo_wr_en),
        .tx_reg_cmd_fifo_wr_data(tx_reg_cmd_fifo_wr_data),
        .tx_reg_cmd_fifo_wr_ready(tx_reg_cmd_fifo_wr_ready),
        .spi_csn(ad9363_spi_csn),
        .spi_sclk(ad9363_spi_sclk),
        .spi_mosi(ad9363_spi_mosi),
        .spi_miso(ad9363_spi_miso),
        .busy(ad9363_spi_busy)
    );

    ad9363_data_if u_ad9363_data_if (
        .rst_n(rst_n),
        .sys_clk(sys_clk),
        .ad_data_clk(ad9363_data_clk),
        .ad_rx_frame(ad9363_rx_frame),
        .ad_p0_rx_data(ad9363_p0_rx_data),
        .ad_fb_clk(ad9363_fb_clk),
        .ad_tx_frame(ad9363_tx_frame),
        .ad_p1_tx_data(ad9363_p1_tx_data),
        .ad_enable(ad9363_enable),
        .ad_txnrx(ad9363_txnrx),
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

endmodule
