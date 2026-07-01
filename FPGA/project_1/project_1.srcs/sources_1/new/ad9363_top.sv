`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/29 21:38:25
// Design Name: 
// Module Name: ad9363_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ad9363_top(
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

    input  logic        rx_data_fifo_rd_en,
    output logic [31:0] rx_data_fifo_rd_data,
    output logic        rx_data_fifo_empty,
    output logic        rx_data_fifo_almost_empty,
    output logic        rx_data_fifo_valid,
    output logic [9:0]  rx_data_fifo_data_count,

    input  logic        tx_data_fifo_wr_en,
    input  logic [31:0] tx_data_fifo_wr_data,
    output logic        tx_data_fifo_wr_ready,
    output logic        tx_data_fifo_full,
    output logic        tx_data_fifo_almost_full,
    output logic [9:0]  tx_data_fifo_data_count,
    output logic [10:0] tx_data_fifo_free_words,
    output logic [10:0] usb_tx_fifo_free_words,

    output logic        rx_start_stream_valid,
    output logic        rx_stop_stream_valid,
    output logic        rx_frame_error,

    output logic        ad9363_spi_csn,
    output logic        ad9363_spi_sclk,
    output logic        ad9363_spi_mosi,
    input  logic        ad9363_spi_miso,
    output logic        ad9363_spi_busy
);

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

    usb_rx_top u_usb_rx_top (
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

endmodule
