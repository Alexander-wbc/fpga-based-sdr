`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2026/04/28 19:23:16
// Design Name:
// Module Name: usb_fifo
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


module usb_fifo_layer (
    input  logic        rst_n,
    input  logic        sys_clk,

    // FT601 245 FIFO interface
    input  logic        FT601_clk,
    inout  wire  [31:0] FT601_DATA,
    inout  wire  [3:0]  FT601_BE,

    input  logic        FT601_TXE_N,   // 0: FT601 TX FIFO has space, FPGA can write
    input  logic        FT601_RXF_N,   // 0: FT601 RX FIFO has data, FPGA can read

    output logic        FT601_WR_N,    // write enable, active low
    output logic        FT601_RD_N,    // read enable, active low
    output logic        FT601_OE_N,    // output enable, active low
    output logic        FT601_SIWU_N,  // keep high in normal operation

    // RX data interface: FT601 -> async FIFO -> sys_clk domain
    input  logic        rx_fifo_rd_en,
    output logic [31:0] rx_fifo_rd_data,
    output logic        rx_fifo_empty,
    output logic        rx_fifo_almost_empty,
    output logic        rx_fifo_valid,

    // TX data interface: sys_clk domain -> async FIFO -> FT601
    input  logic        tx_fifo_wr_en,
    input  logic [31:0] tx_fifo_wr_data,
    output logic        tx_fifo_full,
    output logic        tx_fifo_almost_full,
    output logic [10:0] tx_fifo_free_words
);

    localparam logic [10:0] TX_FIFO_DEPTH_WORDS = 11'd1024;

    typedef enum logic [2:0] {
        FT601_IDLE,
        FT601_WRITE_WAIT,
        FT601_WRITE,
        FT601_READ_OE,
        FT601_READ
    } ft601_state_t;

    ft601_state_t state, next_state;

    logic        data_oe;
    logic [31:0] data_out;
    logic [3:0]  be_out;

    logic        rx_fifo_wr_en;
    logic        rx_fifo_almost_full;
    logic [31:0] rx_fifo_wr_data;

    logic        tx_fifo_rd_en;
    logic        tx_fifo_empty;
    logic        tx_fifo_valid;
    logic [31:0] tx_fifo_rd_data;
    logic [9:0]  tx_fifo_wr_data_count;
    logic [31:0] tx_word;

    assign FT601_SIWU_N = 1'b1;
    assign tx_fifo_free_words = TX_FIFO_DEPTH_WORDS - {1'b0, tx_fifo_wr_data_count};

    assign FT601_DATA = data_oe ? data_out : 32'hZZZZ_ZZZZ;
    assign FT601_BE   = data_oe ? be_out   : 4'hZ;

    always_ff @(posedge FT601_clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= FT601_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;

        case (state)
            FT601_IDLE: begin
                if (FT601_TXE_N == 1'b0 && !tx_fifo_empty) begin
                    next_state = FT601_WRITE_WAIT;
                end else if (FT601_RXF_N == 1'b0 && !rx_fifo_almost_full) begin
                    next_state = FT601_READ_OE;
                end
            end

            FT601_WRITE_WAIT: begin
                if (tx_fifo_valid) begin
                    next_state = FT601_WRITE;
                end
            end

            FT601_WRITE: begin
                if (FT601_TXE_N == 1'b1) begin
                    // Hold the prefetched word until FT601 has room again.
                    next_state = FT601_WRITE;
                end else if (!tx_fifo_empty) begin
                    next_state = FT601_WRITE_WAIT;
                end else begin
                    next_state = FT601_IDLE;
                end
            end

            FT601_READ_OE: begin
                if (FT601_RXF_N == 1'b0 && !rx_fifo_almost_full) begin
                    next_state = FT601_READ;
                end else begin
                    next_state = FT601_IDLE;
                end
            end

            FT601_READ: begin
                if (FT601_RXF_N == 1'b0 && !rx_fifo_almost_full) begin
                    next_state = FT601_READ;
                end else begin
                    next_state = FT601_IDLE;
                end
            end

            default: begin
                next_state = FT601_IDLE;
            end
        endcase
    end

    always_ff @(posedge FT601_clk or negedge rst_n) begin
        if (!rst_n) begin
            FT601_WR_N <= 1'b1;
            FT601_RD_N <= 1'b1;
            FT601_OE_N <= 1'b1;

            data_oe  <= 1'b0;
            data_out <= 32'd0;
            be_out   <= 4'hF;
        end else begin
            FT601_WR_N <= 1'b1;
            FT601_RD_N <= 1'b1;
            FT601_OE_N <= 1'b1;

            data_oe  <= 1'b0;
            data_out <= tx_word;
            be_out   <= 4'hF;

            case (state)
                FT601_WRITE: begin
                    if (FT601_TXE_N == 1'b0) begin
                        data_oe     <= 1'b1;
                        FT601_WR_N  <= 1'b0;
                    end
                end

                FT601_READ_OE: begin
                    FT601_OE_N <= 1'b0;
                end

                FT601_READ: begin
                    FT601_OE_N <= 1'b0;

                    if (FT601_RXF_N == 1'b0 && !rx_fifo_almost_full) begin
                        FT601_RD_N <= 1'b0;
                    end
                end

                default: begin
                end
            endcase
        end
    end

    always_ff @(posedge FT601_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_fifo_wr_en   <= 1'b0;
            rx_fifo_wr_data <= 32'd0;
        end else begin
            rx_fifo_wr_en <= 1'b0;

            if (state == FT601_READ && FT601_RXF_N == 1'b0 && !rx_fifo_almost_full) begin
                rx_fifo_wr_data <= FT601_DATA;
                rx_fifo_wr_en   <= 1'b1;
            end
        end
    end

    always_ff @(posedge FT601_clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_fifo_rd_en <= 1'b0;
            tx_word       <= 32'd0;
        end else begin
            tx_fifo_rd_en <= 1'b0;

            if ((state == FT601_IDLE || state == FT601_WRITE) &&
                    FT601_TXE_N == 1'b0 && !tx_fifo_empty) begin
                tx_fifo_rd_en <= 1'b1;
            end

            if (tx_fifo_valid) begin
                tx_word <= tx_fifo_rd_data;
            end
        end
    end

    async_fifo rx_fifo (
        .rst(!rst_n),
        .wr_clk(FT601_clk),
        .rd_clk(sys_clk),
        .din(rx_fifo_wr_data),
        .wr_en(rx_fifo_wr_en),
        .rd_en(rx_fifo_rd_en),
        .dout(rx_fifo_rd_data),
        .full(),
        .almost_full(rx_fifo_almost_full),
        .wr_ack(),
        .overflow(),
        .empty(rx_fifo_empty),
        .almost_empty(rx_fifo_almost_empty),
        .valid(rx_fifo_valid),
        .underflow(),
        .rd_data_count(),
        .wr_data_count(),
        .wr_rst_busy(),
        .rd_rst_busy()
    );

    async_fifo tx_fifo (
        .rst(!rst_n),
        .wr_clk(sys_clk),
        .rd_clk(FT601_clk),
        .din(tx_fifo_wr_data),
        .wr_en(tx_fifo_wr_en),
        .rd_en(tx_fifo_rd_en),
        .dout(tx_fifo_rd_data),
        .full(tx_fifo_full),
        .almost_full(tx_fifo_almost_full),
        .wr_ack(),
        .overflow(),
        .empty(tx_fifo_empty),
        .almost_empty(),
        .valid(tx_fifo_valid),
        .underflow(),
        .rd_data_count(),
        .wr_data_count(tx_fifo_wr_data_count),
        .wr_rst_busy(),
        .rd_rst_busy()
    );
endmodule
