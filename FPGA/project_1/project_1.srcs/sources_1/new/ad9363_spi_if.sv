`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/30 10:56:06
// Design Name: 
// Module Name: ad9363_spi_if
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


module ad9363_spi_if #(
    parameter int SYS_CLK_HZ = 50_000_000,
    parameter int SPI_CLK_HZ = 10_000_000
)(
    input  logic        sys_clk,
    input  logic        rst_n,

    // RX_REG_CMD FIFO (usb_packet_layer -> this module)
    output logic        reg_cmd_fifo_rd_en,
    input  logic [31:0] reg_cmd_fifo_rd_data,
    input  logic        reg_cmd_fifo_empty,
    input  logic        reg_cmd_fifo_valid,

    // TX_REG_DATA FIFO (this module -> usb_packet_layer)
    output logic        tx_reg_cmd_fifo_wr_en,
    output logic [31:0] tx_reg_cmd_fifo_wr_data,
    input  logic        tx_reg_cmd_fifo_wr_ready,

    // AD9363 default 4-wire SPI: data launches on the rising edge and is
    // sampled on the falling edge (UG-1040, Serial Peripheral Interface).
    output logic        spi_csn,
    output logic        spi_sclk,
    output logic        spi_mosi,
    input  logic        spi_miso,

    output logic        busy
);

    // A 50 MHz clock cannot produce a perfectly symmetric 10 MHz clock using
    // only rising-edge logic.  Two low cycles and three high cycles give an
    // exact 100 ns SPI period while meeting the requested 10 MHz bit rate.
    localparam int SPI_PERIOD_CYCLES = SYS_CLK_HZ / SPI_CLK_HZ;
    localparam int SPI_LOW_CYCLES    = SPI_PERIOD_CYCLES / 2;
    localparam int SPI_HIGH_CYCLES   = SPI_PERIOD_CYCLES - SPI_LOW_CYCLES;
    localparam int PHASE_COUNT_WIDTH =
        (SPI_HIGH_CYCLES <= 1) ? 1 : $clog2(SPI_HIGH_CYCLES);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WAIT_CMD,
        ST_TRANSFER,
        ST_END_TRANSFER,
        ST_RETURN_DATA
    } state_t;

    state_t state;

    logic [23:0] tx_shift;
    logic [7:0]  rx_shift;
    logic [4:0]  bit_index;
    logic [9:0]  cmd_address;
    logic        cmd_is_write;
    logic [PHASE_COUNT_WIDTH-1:0] phase_count;

    assign busy = (state != ST_IDLE);

    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            state                       <= ST_IDLE;
            reg_cmd_fifo_rd_en          <= 1'b0;
            tx_reg_cmd_fifo_wr_en       <= 1'b0;
            tx_reg_cmd_fifo_wr_data     <= 32'd0;
            spi_csn                     <= 1'b1;
            spi_sclk                    <= 1'b0;
            spi_mosi                    <= 1'b0;
            tx_shift                    <= 24'd0;
            rx_shift                    <= 8'd0;
            bit_index                   <= 5'd0;
            cmd_address                 <= 10'd0;
            cmd_is_write                <= 1'b0;
            phase_count                 <= '0;
        end else begin
            reg_cmd_fifo_rd_en    <= 1'b0;
            tx_reg_cmd_fifo_wr_en <= 1'b0;

            case (state)
                ST_IDLE: begin
                    spi_csn     <= 1'b1;
                    spi_sclk    <= 1'b0;
                    spi_mosi    <= 1'b0;
                    phase_count <= '0;

                    if (!reg_cmd_fifo_empty) begin
                        reg_cmd_fifo_rd_en <= 1'b1;
                        state              <= ST_WAIT_CMD;
                    end
                end

                ST_WAIT_CMD: begin
                    if (reg_cmd_fifo_valid) begin
                        cmd_is_write <= reg_cmd_fifo_rd_data[31];
                        cmd_address  <= reg_cmd_fifo_rd_data[9:0];

                        // AD9363 single-register transaction:
                        // command[15] = write, command[14:10] = 0,
                        // command[9:0] = address, followed by one data byte.
                        tx_shift <= {
                            reg_cmd_fifo_rd_data[31],
                            5'd0,
                            reg_cmd_fifo_rd_data[9:0],
                            reg_cmd_fifo_rd_data[31]
                                ? reg_cmd_fifo_rd_data[17:10] : 8'd0
                        };
                        rx_shift    <= 8'd0;
                        bit_index   <= 5'd23;
                        phase_count <= '0;
                        spi_csn     <= 1'b0;
                        spi_sclk    <= 1'b0;
                        spi_mosi    <= reg_cmd_fifo_rd_data[31];
                        state       <= ST_TRANSFER;
                    end
                end

                ST_TRANSFER: begin
                    if (!spi_sclk) begin
                        if (phase_count == SPI_LOW_CYCLES - 1) begin
                            phase_count <= '0;
                            spi_sclk    <= 1'b1;
                            // Both sides launch their next data bit on the
                            // rising edge.  The AD9363 samples SPI_DI and the
                            // FPGA samples SPI_DO on the following falling edge.
                            spi_mosi <= tx_shift[bit_index];
                        end else begin
                            phase_count <= phase_count + 1'b1;
                        end
                    end else begin
                        if (phase_count == SPI_HIGH_CYCLES - 1) begin
                            phase_count <= '0;
                            spi_sclk    <= 1'b0;

                            // Keeping the last eight samples yields the Phase 2
                            // read byte; command-phase samples shift out.
                            rx_shift <= {rx_shift[6:0], spi_miso};

                            if (bit_index == 0) begin
                                // Keep SPI_ENB low through the complete final
                                // falling edge, then release it in the next
                                // system-clock cycle.
                                state <= ST_END_TRANSFER;
                            end else begin
                                bit_index <= bit_index - 1'b1;
                            end
                        end else begin
                            phase_count <= phase_count + 1'b1;
                        end
                    end
                end

                ST_END_TRANSFER: begin
                    spi_csn  <= 1'b1;
                    spi_mosi <= 1'b0;

                    if (cmd_is_write) begin
                        state <= ST_IDLE;
                    end else begin
                        tx_reg_cmd_fifo_wr_data <= {
                            14'd0,
                            rx_shift,
                            cmd_address
                        };
                        state <= ST_RETURN_DATA;
                    end
                end

                ST_RETURN_DATA: begin
                    if (tx_reg_cmd_fifo_wr_ready) begin
                        tx_reg_cmd_fifo_wr_en <= 1'b1;
                        state                 <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
