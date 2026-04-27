`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/21 20:40:50
// Design Name: 
// Module Name: USB_test
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


module USB_test (
    input  wire        rst_n,

    // FT601 FIFO bus clock, from FT601 CLK pin
    input  wire        FT601_clk,

    // FT601 245 FIFO interface
    inout  wire [31:0] FT601_DATA,
    inout  wire [3:0]  FT601_BE,

    input  wire        FT601_TXE_N,   // 0: FT601 TX FIFO has space, FPGA can write
    input  wire        FT601_RXF_N,   // 0: FT601 RX FIFO has data, FPGA can read

    output reg         FT601_WR_N,    // write enable, active low
    output reg         FT601_RD_N,    // read enable, active low
    output reg         FT601_OE_N,    // output enable, active low

    output wire        FT601_SIWU_N   // keep high in normal operation
);

    // ============================================================
    // 245 FIFO mode note:
    // FPGA write -> PC read:
    //   TXE_N == 0, FPGA drives DATA/BE, WR_N pulls low.
    //
    // PC write -> FPGA read:
    //   RXF_N == 0, FPGA releases DATA/BE, OE_N pulls low,
    //   then RD_N pulls low to read data.
    // ============================================================

    assign FT601_SIWU_N = 1'b1;

    // DATA / BE tri-state control
    reg        data_oe;
    reg [31:0] data_out;
    reg [3:0]  be_out;

    assign FT601_DATA = data_oe ? data_out : 32'hZZZZ_ZZZZ;
    assign FT601_BE   = data_oe ? be_out   : 4'hZ;

    // Optional receive data capture
    reg [31:0] rx_data;
    reg        rx_data_valid;

    // Test pattern counter
    reg [31:0] tx_counter;

    // State machine
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WRITE,
        ST_READ_OE,
        ST_READ
    } state_t;

    state_t state, next_state;

    // ============================================================
    // State register
    // ============================================================
    always_ff @(posedge FT601_clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // ============================================================
    // Next-state logic
    // ============================================================
    always_comb begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                // Priority: write test data to PC first
                if (FT601_TXE_N == 1'b0) begin
                    next_state = ST_WRITE;
                end else if (FT601_RXF_N == 1'b0) begin
                    next_state = ST_READ_OE;
                end else begin
                    next_state = ST_IDLE;
                end
            end

            ST_WRITE: begin
                // Continue writing while TXE_N is low.
                // If FT601 no longer has space, stop.
                if (FT601_TXE_N == 1'b0) begin
                    next_state = ST_WRITE;
                end else begin
                    next_state = ST_IDLE;
                end
            end

            ST_READ_OE: begin
                // One cycle after OE_N low, enter read cycle
                next_state = ST_READ;
            end

            ST_READ: begin
                // Continue reading while RXF_N is low.
                // If no more data, return idle.
                if (FT601_RXF_N == 1'b0) begin
                    next_state = ST_READ;
                end else begin
                    next_state = ST_IDLE;
                end
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    // ============================================================
    // Output logic and data path
    // ============================================================
    always_ff @(posedge FT601_clk or negedge rst_n) begin
        if (!rst_n) begin
            FT601_WR_N   <= 1'b1;
            FT601_RD_N   <= 1'b1;
            FT601_OE_N   <= 1'b1;

            data_oe      <= 1'b0;
            data_out     <= 32'd0;
            be_out       <= 4'hF;

            tx_counter   <= 32'd0;
            rx_data      <= 32'd0;
            rx_data_valid <= 1'b0;
        end else begin
            // default inactive
            FT601_WR_N    <= 1'b1;
            FT601_RD_N    <= 1'b1;
            FT601_OE_N    <= 1'b1;
            data_oe       <= 1'b0;
            be_out        <= 4'hF;
            rx_data_valid <= 1'b0;

            case (next_state)

                ST_IDLE: begin
                    data_oe    <= 1'b0;
                    FT601_WR_N <= 1'b1;
                    FT601_RD_N <= 1'b1;
                    FT601_OE_N <= 1'b1;
                end

                ST_WRITE: begin
                    // FPGA drives data bus
                    data_oe    <= 1'b1;
                    data_out   <= tx_counter;
                    be_out     <= 4'hF;      // all 4 bytes valid

                    FT601_WR_N <= 1'b0;      // active low write
                    FT601_RD_N <= 1'b1;
                    FT601_OE_N <= 1'b1;

                    if (FT601_TXE_N == 1'b0) begin
                        tx_counter <= tx_counter + 32'd1;
                    end
                end

                ST_READ_OE: begin
                    // FPGA releases data bus, FT601 prepares to drive DATA/BE
                    data_oe    <= 1'b0;

                    FT601_OE_N <= 1'b0;
                    FT601_RD_N <= 1'b1;
                    FT601_WR_N <= 1'b1;
                end

                ST_READ: begin
                    // FPGA reads data from FT601
                    data_oe    <= 1'b0;

                    FT601_OE_N <= 1'b0;
                    FT601_RD_N <= 1'b0;
                    FT601_WR_N <= 1'b1;

                    if (FT601_RXF_N == 1'b0) begin
                        rx_data       <= FT601_DATA;
                        rx_data_valid <= 1'b1;
                    end
                end

                default: begin
                    data_oe    <= 1'b0;
                    FT601_WR_N <= 1'b1;
                    FT601_RD_N <= 1'b1;
                    FT601_OE_N <= 1'b1;
                end

            endcase
        end
    end

endmodule