`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/13 19:27:40
// Design Name: 
// Module Name: usb_rx_top
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


module usb_rx_top(
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

    input  logic        reg_cmd_fifo_rd_en,
    output logic [31:0] reg_cmd_fifo_rd_data,
    output logic        reg_cmd_fifo_full,
    output logic        reg_cmd_fifo_almost_full,
    output logic        reg_cmd_fifo_empty,
    output logic        reg_cmd_fifo_almost_empty,
    output logic        reg_cmd_fifo_valid,
    output logic [6:0]  reg_cmd_fifo_data_count,

    input  logic        tx_data_fifo_wr_en,
    input  logic [31:0] tx_data_fifo_wr_data,
    output logic        tx_data_fifo_wr_ready,
    output logic        tx_data_fifo_full,
    output logic        tx_data_fifo_almost_full,
    output logic [9:0]  tx_data_fifo_data_count,
    output logic [10:0] tx_data_fifo_free_words,

    input  logic        tx_reg_cmd_fifo_wr_en,
    input  logic [31:0] tx_reg_cmd_fifo_wr_data,
    output logic        tx_reg_cmd_fifo_wr_ready,
    output logic        tx_reg_cmd_fifo_full,
    output logic        tx_reg_cmd_fifo_almost_full,
    output logic [6:0]  tx_reg_cmd_fifo_data_count,

    output logic [10:0] usb_tx_fifo_free_words,

    output logic        rx_start_stream_valid,
    output logic        rx_stop_stream_valid,

    output logic        rx_frame_error
);

    logic        rx_fifo_rd_en;
    logic [31:0] rx_fifo_rd_data;
    logic        rx_fifo_empty;
    logic        rx_fifo_almost_empty;
    logic        rx_fifo_valid;

    logic        tx_fifo_wr_en;
    logic [31:0] tx_fifo_wr_data;
    logic        tx_fifo_full;
    logic        tx_fifo_almost_full;

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

        .rx_fifo_rd_en(rx_fifo_rd_en),
        .rx_fifo_rd_data(rx_fifo_rd_data),
        .rx_fifo_empty(rx_fifo_empty),
        .rx_fifo_almost_empty(rx_fifo_almost_empty),
        .rx_fifo_valid(rx_fifo_valid),

        .tx_fifo_wr_en(tx_fifo_wr_en),
        .tx_fifo_wr_data(tx_fifo_wr_data),
        .tx_fifo_full(tx_fifo_full),
        .tx_fifo_almost_full(tx_fifo_almost_full),
        .tx_fifo_free_words(usb_tx_fifo_free_words)
    );

    usb_packet_layer u_usb_packet_layer (
        .sys_clk(sys_clk),
        .rst_n(rst_n),

        .rx_fifo_rd_en(rx_fifo_rd_en),
        .rx_fifo_rd_data(rx_fifo_rd_data),
        .rx_fifo_empty(rx_fifo_empty),
        .rx_fifo_valid(rx_fifo_valid),

        .tx_fifo_wr_en(tx_fifo_wr_en),
        .tx_fifo_wr_data(tx_fifo_wr_data),
        .tx_fifo_full(tx_fifo_full),
        .tx_fifo_almost_full(tx_fifo_almost_full),
        .tx_fifo_free_words(usb_tx_fifo_free_words),

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

        .rx_start_stream_valid(rx_start_stream_valid),
        .rx_stop_stream_valid(rx_stop_stream_valid),

        .rx_frame_error(rx_frame_error)
    );

endmodule
