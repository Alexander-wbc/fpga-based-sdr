`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2026/04/28 22:40:31
// Design Name:
// Module Name: usb_packet_layer
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


module usb_packet_layer(
    input  logic        sys_clk,
    input  logic        rst_n,

    // RX data interface: FT601 -> async FIFO -> sys_clk domain
    output logic        rx_fifo_rd_en,
    input  logic [31:0] rx_fifo_rd_data,
    input  logic        rx_fifo_empty,
    input  logic        rx_fifo_valid,

    // RX_DATA payload FIFO. The downstream TX/DSP path reads data here.
    input  logic        rx_data_fifo_rd_en,
    output logic [31:0] rx_data_fifo_rd_data,
    output logic        rx_data_fifo_empty,
    output logic        rx_data_fifo_almost_empty,
    output logic        rx_data_fifo_valid,
    output logic [9:0]  rx_data_fifo_data_count,

    // AD9363 SPI Read and Write
    output logic        reg_write_start,
    output logic [9:0]  reg_addr,
    output logic [7:0]  reg_write_data,
    output logic        reg_read_start,

    input  logic        write_reg_fifo_rd_en,
    output logic [17:0] write_reg_fifo_rd_data,
    output logic        write_reg_fifo_full,
    output logic        write_reg_fifo_almost_full,
    output logic        write_reg_fifo_empty,
    output logic        write_reg_fifo_almost_empty,
    output logic        write_reg_fifo_valid,
    output logic [6:0]  write_reg_fifo_data_count,

    output logic        rx_start_stream_valid,
    output logic        rx_stop_stream_valid,

    output logic        rx_frame_error
);

    // Frame format:
    //   word0: 32'hAAAA_5555
    //   word1: info, frame type is info[7:0]
    //   word2: payload length in 32-bit words. For RX_DATA each word holds
    //          one 16-bit I + 16-bit Q sample pair.
    // Register command payload:
    //   READ_REG : one word, addr = payload[9:0]
    //   WRITE_REG: one word, addr = payload[9:0], write_data = payload[17:10]
    localparam logic [31:0] FRAME_MAGIC = 32'hAAAA5555;
    localparam logic [10:0] RX_DATA_FIFO_DEPTH_WORDS = 11'd1024;

    typedef enum logic [7:0] {
        FRAME_TYPE_WRITE_REG    = 8'h01,
        FRAME_TYPE_READ_REG     = 8'h02,
        FRAME_TYPE_TX_DATA      = 8'h10,
        FRAME_TYPE_START_STREAM = 8'h20,
        FRAME_TYPE_STOP_STREAM  = 8'h21
    } frame_type_t;

    typedef enum logic [3:0] {
        RX_IDLE,
        RX_FIND_MAGIC,
        RX_READ_INFO,
        RX_READ_LEN,
        RX_READ_REG,
        RX_WRITE_REG,
        RX_DATA
    } rx_packet_state_t;

    rx_packet_state_t state, next_state;

    frame_type_t rx_frame_type;
    logic [31:0] rx_payload_len;
    logic [31:0] rx_payload_count;

    logic        rx_state_needs_word;
    logic        rx_data_transfer_ready;
    logic [10:0] rx_data_fifo_free_words;
    logic [31:0] rx_data_resume_words;

    logic        rx_data_fifo_wr_en;
    logic [31:0] rx_data_fifo_wr_data;
    logic        rx_data_fifo_full;
    logic        rx_data_fifo_almost_full;

    logic        write_reg_fifo_wr_en;
    logic [17:0] write_reg_fifo_wr_data;


    assign rx_data_fifo_free_words = RX_DATA_FIFO_DEPTH_WORDS - {1'b0, rx_data_fifo_data_count};
    assign rx_data_resume_words = (rx_payload_len >> 1) + {{31{1'b0}}, rx_payload_len[0]};

    assign rx_data_fifo_wr_en = rx_fifo_valid && (state == RX_DATA) && rx_data_transfer_ready;
    assign rx_data_fifo_wr_data = rx_fifo_rd_data;

    assign write_reg_fifo_wr_en = rx_fifo_valid && (state == RX_WRITE_REG) && !write_reg_fifo_full;
    assign write_reg_fifo_wr_data = rx_fifo_rd_data[17:0];

    always_comb begin
        rx_state_needs_word = 1'b0;
        case (state)
            RX_FIND_MAGIC,
            RX_READ_INFO,
            RX_READ_LEN,
            RX_READ_REG,
            RX_WRITE_REG: begin
                rx_state_needs_word = 1'b1;
            end
            RX_DATA: begin
                rx_state_needs_word = (rx_payload_count < rx_payload_len);
            end
            default: begin
                rx_state_needs_word = 1'b0;
            end
        endcase
    end

    always_comb begin
        rx_data_transfer_ready = 1'b1;
        if (state == RX_DATA) begin
            rx_data_transfer_ready = ({21'd0, rx_data_fifo_free_words} >= rx_data_resume_words);
        end
    end

    assign rx_fifo_rd_en =
        rx_state_needs_word &&
        !rx_fifo_empty &&
        rx_data_transfer_ready;


    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= RX_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;

        if (state == RX_IDLE) begin
            next_state = RX_FIND_MAGIC;
        end else if (rx_fifo_valid) begin
            case (state)
                RX_FIND_MAGIC: begin
                    if (rx_fifo_rd_data == FRAME_MAGIC) begin
                        next_state = RX_READ_INFO;
                    end
                end

                RX_READ_INFO: begin
                    next_state = RX_READ_LEN;
                end

                RX_READ_LEN: begin
                    case (rx_frame_type)
                        FRAME_TYPE_WRITE_REG: begin
                            if (rx_fifo_rd_data == 32'd1) begin
                                next_state = RX_WRITE_REG;
                            end else begin
                                next_state = RX_FIND_MAGIC;
                            end
                        end

                        FRAME_TYPE_READ_REG: begin
                            if (rx_fifo_rd_data == 32'd1) begin
                                next_state = RX_READ_REG;
                            end else begin
                                next_state = RX_FIND_MAGIC;
                            end
                        end

                        FRAME_TYPE_TX_DATA: begin
                            if (rx_fifo_rd_data == 32'd0) begin
                                next_state = RX_FIND_MAGIC;
                            end else begin
                                next_state = RX_DATA;
                            end
                        end

                        FRAME_TYPE_START_STREAM,
                        FRAME_TYPE_STOP_STREAM: begin
                            next_state = RX_FIND_MAGIC;
                        end

                        default: begin
                            next_state = RX_FIND_MAGIC;
                        end
                    endcase
                end

                RX_READ_REG,
                RX_WRITE_REG: begin
                    next_state = RX_FIND_MAGIC;
                end

                RX_DATA: begin
                    if (rx_data_transfer_ready &&
                            (rx_payload_count + 32'd1) >= rx_payload_len) begin
                        next_state = RX_FIND_MAGIC;
                    end
                end

                default: begin
                    next_state = RX_FIND_MAGIC;
                end
            endcase
        end
    end


    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_frame_type            <= FRAME_TYPE_WRITE_REG;
            rx_payload_len           <= 32'd0;
            rx_payload_count         <= 32'd0;
            reg_addr                 <= 10'd0;
            reg_write_data           <= 8'd0;
            reg_write_start          <= 1'b0;
            reg_read_start           <= 1'b0;
            rx_start_stream_valid    <= 1'b0;
            rx_stop_stream_valid     <= 1'b0;
            rx_frame_error           <= 1'b0;
        end else begin
            reg_write_start         <= 1'b0;
            reg_read_start          <= 1'b0;
            rx_start_stream_valid   <= 1'b0;
            rx_stop_stream_valid    <= 1'b0;
            rx_frame_error          <= 1'b0;

            if (rx_fifo_valid) begin
                case (state)
                    RX_FIND_MAGIC: begin
                    end

                    RX_READ_INFO: begin
                        rx_frame_type <= frame_type_t'(rx_fifo_rd_data[7:0]);
                    end

                    RX_READ_LEN: begin
                        rx_payload_len   <= rx_fifo_rd_data;
                        rx_payload_count <= 32'd0;

                        case (rx_frame_type)
                            FRAME_TYPE_WRITE_REG: begin
                                if (rx_fifo_rd_data != 32'd1) begin
                                    rx_frame_error <= 1'b1;
                                end
                            end

                            FRAME_TYPE_READ_REG: begin
                                if (rx_fifo_rd_data != 32'd1) begin
                                    rx_frame_error <= 1'b1;
                                end
                            end

                            FRAME_TYPE_TX_DATA: begin
                            end

                            FRAME_TYPE_START_STREAM: begin
                                if (rx_fifo_rd_data == 32'd0) begin
                                    rx_start_stream_valid <= 1'b1;
                                end else begin
                                    rx_frame_error <= 1'b1;
                                end
                            end

                            FRAME_TYPE_STOP_STREAM: begin
                                if (rx_fifo_rd_data == 32'd0) begin
                                    rx_stop_stream_valid <= 1'b1;
                                end else begin
                                    rx_frame_error <= 1'b1;
                                end
                            end

                            default: begin
                                rx_frame_error <= 1'b1;
                            end
                        endcase
                    end

                    RX_READ_REG: begin
                        reg_addr       <= rx_fifo_rd_data[9:0];
                        reg_read_start <= 1'b1;
                    end

                    RX_WRITE_REG: begin
                        reg_addr         <= rx_fifo_rd_data[9:0];
                        reg_write_data   <= rx_fifo_rd_data[17:10];
                        reg_write_start  <= 1'b1;
                    end

                    RX_DATA: begin
                        if (rx_data_transfer_ready) begin
                            rx_payload_count        <= rx_payload_count + 32'd1;
                        end
                    end

                    default: begin
                        rx_frame_error <= 1'b1;
                    end
                endcase
            end

        end
    end

    sync_fifo rx_data_fifo (
        .clk(sys_clk),
        .srst(!rst_n),
        .din(rx_data_fifo_wr_data),
        .wr_en(rx_data_fifo_wr_en),
        .rd_en(rx_data_fifo_rd_en),
        .dout(rx_data_fifo_rd_data),
        .full(rx_data_fifo_full),
        .almost_full(rx_data_fifo_almost_full),
        .wr_ack(),
        .overflow(),
        .empty(rx_data_fifo_empty),
        .almost_empty(rx_data_fifo_almost_empty),
        .valid(rx_data_fifo_valid),
        .underflow(),
        .data_count(rx_data_fifo_data_count)
    );

    sync_fifo_18bits write_reg_fifo (
        .clk(sys_clk),
        .srst(!rst_n),
        .din(write_reg_fifo_wr_data),
        .wr_en(write_reg_fifo_wr_en),
        .rd_en(write_reg_fifo_rd_en),
        .dout(write_reg_fifo_rd_data),
        .full(write_reg_fifo_full),
        .almost_full(write_reg_fifo_almost_full),
        .wr_ack(),
        .overflow(),
        .empty(write_reg_fifo_empty),
        .almost_empty(write_reg_fifo_almost_empty),
        .valid(write_reg_fifo_valid),
        .underflow(),
        .data_count(write_reg_fifo_data_count)
    );
endmodule
