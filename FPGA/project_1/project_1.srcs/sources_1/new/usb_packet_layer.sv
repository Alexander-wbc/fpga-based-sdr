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


module usb_packet_layer #(
    parameter int ee = 256
)(
    input  logic        sys_clk,
    input  logic        rst_n,

    // RX data interface: FT601 -> async FIFO -> sys_clk domain
    output logic        rx_fifo_rd_en,
    input  logic [31:0] rx_fifo_rd_data,
    input  logic        rx_fifo_empty,
    input  logic        rx_fifo_valid,

    // TX data interface: sys_clk domain -> async FIFO -> FT601
    output logic        tx_fifo_wr_en,
    output logic [31:0] tx_fifo_wr_data,
    input  logic        tx_fifo_full,
    input  logic        tx_fifo_almost_full,
    input  logic [10:0] tx_fifo_free_words,

    // RX_DATA
    input  logic        rx_data_fifo_rd_en,
    output logic [31:0] rx_data_fifo_rd_data,
    output logic        rx_data_fifo_empty,
    output logic        rx_data_fifo_almost_empty,
    output logic        rx_data_fifo_valid,
    output logic [9:0]  rx_data_fifo_data_count,

    // RX_REG_CMD
    input  logic        reg_cmd_fifo_rd_en,
    output logic [31:0] reg_cmd_fifo_rd_data,
    output logic        reg_cmd_fifo_full,
    output logic        reg_cmd_fifo_almost_full,
    output logic        reg_cmd_fifo_empty,
    output logic        reg_cmd_fifo_almost_empty,
    output logic        reg_cmd_fifo_valid,
    output logic [6:0]  reg_cmd_fifo_data_count,

    // TX_DATA: AD9363 -> PC
    input  logic        tx_data_fifo_wr_en,
    input  logic [31:0] tx_data_fifo_wr_data,
    output logic        tx_data_fifo_wr_ready,
    output logic        tx_data_fifo_full,
    output logic        tx_data_fifo_almost_full,
    output logic [9:0]  tx_data_fifo_data_count,
    output logic [10:0] tx_data_fifo_free_words,

    // TX_REG_DATA: register read/write return data -> PC
    input  logic        tx_reg_cmd_fifo_wr_en,
    input  logic [31:0] tx_reg_cmd_fifo_wr_data,
    output logic        tx_reg_cmd_fifo_wr_ready,
    output logic        tx_reg_cmd_fifo_full,
    output logic        tx_reg_cmd_fifo_almost_full,
    output logic [6:0]  tx_reg_cmd_fifo_data_count,

    // sign
    output logic        rx_start_stream_valid,
    output logic        rx_stop_stream_valid,
    output logic        rx_frame_error
);

    localparam logic [31:0] FRAME_MAGIC = 32'hAAAA5555;
    localparam logic [10:0] DATA_FIFO_DEPTH_WORDS = 11'd1024;
    localparam logic [10:0] REG_CMD_FIFO_DEPTH_WORDS = 11'd128;
    localparam logic [10:0] DATA_PACKET_WORDS_11 = DATA_PACKET_WORDS;
    localparam int TX_FRAME_HEADER_WORDS = 3;
    localparam int TX_SHORT_FRAME_WORDS = TX_FRAME_HEADER_WORDS + 1;
    localparam int TX_DATA_FRAME_WORDS = TX_FRAME_HEADER_WORDS + DATA_PACKET_WORDS;
    localparam logic [3:0]  REG_CMD_WRITE = 4'h1;
    localparam logic [3:0]  REG_CMD_READ  = 4'h2;

    typedef enum logic [7:0] {
        RX_FRAME_TYPE_WRITE_REG    = 8'h01,
        RX_FRAME_TYPE_READ_REG     = 8'h02,
        RX_FRAME_TYPE_RX_DATA      = 8'h10,
        RX_FRAME_TYPE_START_STREAM = 8'h20,
        RX_FRAME_TYPE_STOP_STREAM  = 8'h21
    } rx_frame_type_t;

    typedef enum logic [3:0] {
        RX_IDLE,
        RX_FIND_MAGIC,
        RX_READ_INFO,
        RX_READ_LEN,
        RX_READ_REG,
        RX_WRITE_REG,
        RX_DATA
    } rx_packet_state_t;

    rx_packet_state_t rx_state, rx_next_state;
    rx_frame_type_t rx_frame_type;
    logic [31:0] rx_payload_len;
    logic [31:0] rx_payload_count;

    logic        rx_state_needs_word;
    logic        rx_data_transfer_ready;
    logic        rx_reg_cmd_transfer_ready;
    logic [10:0] rx_data_fifo_free_words;

    logic        rx_data_fifo_wr_en;
    logic [31:0] rx_data_fifo_wr_data;
    logic        rx_data_fifo_full;
    logic        rx_data_fifo_almost_full;

    logic        reg_cmd_fifo_wr_en;
    logic [31:0] reg_cmd_fifo_wr_data;

    typedef enum logic [7:0] {
        TX_FRAME_TYPE_REG_DATA = 8'h03,
        TX_FRAME_TYPE_TX_DATA  = 8'h10,
        TX_FRAME_TYPE_ACK      = 8'h30
    } tx_frame_type_t;

    typedef enum logic [3:0] {
        TX_IDLE,
        TX_WRITE_MAGIC,
        TX_WRITE_INFO,
        TX_WRITE_LEN,
        TX_REG_DATA,
        TX_DATA,
        TX_ACK
    } tx_packet_state_t;

    tx_packet_state_t tx_state;
    tx_frame_type_t tx_frame_type;
    logic [31:0] tx_payload_len;
    logic [31:0] tx_payload_count;
    logic [31:0] tx_ack_payload;

    logic        tx_output_ready;
    logic        tx_fifo_can_start_short_frame;
    logic        tx_fifo_can_start_data_frame;

    logic        tx_data_fifo_wr_en_int;
    logic        tx_data_fifo_rd_en;
    logic [31:0] tx_data_fifo_rd_data;
    logic        tx_data_fifo_empty;
    logic        tx_data_fifo_almost_empty;
    logic        tx_data_fifo_valid;
    logic [31:0] tx_data_word;
    logic        tx_data_word_valid;
    logic        tx_data_read_pending;
    logic        tx_data_packet_ready;

    logic        tx_reg_cmd_fifo_wr_en_int;
    logic        tx_reg_cmd_fifo_rd_en;
    logic [31:0] tx_reg_cmd_fifo_rd_data;
    logic        tx_reg_cmd_fifo_empty;
    logic        tx_reg_cmd_fifo_almost_empty;
    logic        tx_reg_cmd_fifo_valid;
    logic [31:0] tx_reg_cmd_word;
    logic        tx_reg_cmd_word_valid;
    logic        tx_reg_cmd_read_pending;

    logic        tx_start_stream_ack_pending;
    logic        tx_stop_stream_ack_pending;
    logic        tx_ack_pop_start;
    logic        tx_ack_pop_stop;

    assign rx_data_fifo_free_words = DATA_FIFO_DEPTH_WORDS - {1'b0, rx_data_fifo_data_count};
    assign rx_data_fifo_wr_en = rx_fifo_valid && (rx_state == RX_DATA);
    assign rx_data_fifo_wr_data = rx_fifo_rd_data;

    assign reg_cmd_fifo_wr_en =
        rx_fifo_valid &&
        ((rx_state == RX_READ_REG) || (rx_state == RX_WRITE_REG)) &&
        !reg_cmd_fifo_full;

    assign reg_cmd_fifo_wr_data =
        (rx_state == RX_READ_REG) ?
            {REG_CMD_READ, rx_fifo_rd_data[9:0], 8'd0, 10'd0} :
            {REG_CMD_WRITE, rx_fifo_rd_data[9:0], rx_fifo_rd_data[17:10], 10'd0};

    assign tx_output_ready = !tx_fifo_full && (tx_fifo_free_words != 11'd0);
    assign tx_fifo_can_start_short_frame = ({21'd0, tx_fifo_free_words} > TX_SHORT_FRAME_WORDS);
    assign tx_fifo_can_start_data_frame = ({21'd0, tx_fifo_free_words} > TX_DATA_FRAME_WORDS);
    assign tx_data_packet_ready = ({22'd0, tx_data_fifo_data_count} >= DATA_PACKET_WORDS);

    assign tx_data_fifo_free_words = DATA_FIFO_DEPTH_WORDS - {1'b0, tx_data_fifo_data_count};
    assign tx_data_fifo_wr_ready = !tx_data_fifo_full && (tx_data_fifo_free_words > DATA_PACKET_WORDS_11);
    assign tx_data_fifo_wr_en_int = tx_data_fifo_wr_en && tx_data_fifo_wr_ready;

    assign tx_reg_cmd_fifo_wr_ready = !tx_reg_cmd_fifo_full;
    assign tx_reg_cmd_fifo_wr_en_int = tx_reg_cmd_fifo_wr_en && tx_reg_cmd_fifo_wr_ready;

    function automatic logic [31:0] make_tx_info(input tx_frame_type_t frame_type);
        begin
            make_tx_info = {24'd0, frame_type};
            if (frame_type == TX_FRAME_TYPE_TX_DATA) begin
                make_tx_info = {13'd0, rx_data_fifo_free_words, frame_type};
            end
        end
    endfunction

    always_comb begin
        rx_state_needs_word = 1'b0;
        case (rx_state)
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
        if (rx_state == RX_DATA) begin
            rx_data_transfer_ready = (rx_data_fifo_free_words > DATA_PACKET_WORDS_11);
        end
    end

    always_comb begin
        rx_reg_cmd_transfer_ready = 1'b1;
        if ((rx_state == RX_READ_REG) || (rx_state == RX_WRITE_REG)) begin
            rx_reg_cmd_transfer_ready = !reg_cmd_fifo_full;
        end
    end

    assign rx_fifo_rd_en =
        rx_state_needs_word &&
        !rx_fifo_empty &&
        rx_data_transfer_ready &&
        rx_reg_cmd_transfer_ready;

    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
        end else begin
            rx_state <= rx_next_state;
        end
    end

    always_comb begin
        rx_next_state = rx_state;

        if (rx_state == RX_IDLE) begin
            rx_next_state = RX_FIND_MAGIC;
        end else if (rx_fifo_valid) begin
            case (rx_state)
                RX_FIND_MAGIC: begin
                    if (rx_fifo_rd_data == FRAME_MAGIC) begin
                        rx_next_state = RX_READ_INFO;
                    end
                end

                RX_READ_INFO: begin
                    rx_next_state = RX_READ_LEN;
                end

                RX_READ_LEN: begin
                    case (rx_frame_type)
                        RX_FRAME_TYPE_WRITE_REG: begin
                            if (rx_fifo_rd_data == 32'd1) begin
                                rx_next_state = RX_WRITE_REG;
                            end else begin
                                rx_next_state = RX_FIND_MAGIC;
                            end
                        end

                        RX_FRAME_TYPE_READ_REG: begin
                            if (rx_fifo_rd_data == 32'd1) begin
                                rx_next_state = RX_READ_REG;
                            end else begin
                                rx_next_state = RX_FIND_MAGIC;
                            end
                        end

                        RX_FRAME_TYPE_RX_DATA: begin
                            if (rx_fifo_rd_data == 32'd0) begin
                                rx_next_state = RX_FIND_MAGIC;
                            end else begin
                                rx_next_state = RX_DATA;
                            end
                        end

                        RX_FRAME_TYPE_START_STREAM,
                        RX_FRAME_TYPE_STOP_STREAM: begin
                            rx_next_state = RX_FIND_MAGIC;
                        end

                        default: begin
                            rx_next_state = RX_FIND_MAGIC;
                        end
                    endcase
                end

                RX_READ_REG,
                RX_WRITE_REG: begin
                    rx_next_state = RX_FIND_MAGIC;
                end

                RX_DATA: begin
                    if ((rx_payload_count + 32'd1) >= rx_payload_len) begin
                        rx_next_state = RX_FIND_MAGIC;
                    end
                end

                default: begin
                    rx_next_state = RX_FIND_MAGIC;
                end
            endcase
        end
    end

    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_frame_type               <= RX_FRAME_TYPE_WRITE_REG;
            rx_payload_len              <= 32'd0;
            rx_payload_count            <= 32'd0;
            rx_start_stream_valid       <= 1'b0;
            rx_stop_stream_valid        <= 1'b0;
            rx_frame_error              <= 1'b0;
            tx_start_stream_ack_pending <= 1'b0;
            tx_stop_stream_ack_pending  <= 1'b0;
        end else begin
            rx_start_stream_valid <= 1'b0;
            rx_stop_stream_valid  <= 1'b0;
            rx_frame_error        <= 1'b0;

            if (tx_ack_pop_start) begin
                tx_start_stream_ack_pending <= 1'b0;
            end

            if (tx_ack_pop_stop) begin
                tx_stop_stream_ack_pending <= 1'b0;
            end

            if (rx_fifo_valid) begin
                case (rx_state)
                    RX_FIND_MAGIC: begin
                    end

                    RX_READ_INFO: begin
                        rx_frame_type <= rx_frame_type_t'(rx_fifo_rd_data[7:0]);
                    end

                    RX_READ_LEN: begin
                        rx_payload_len   <= rx_fifo_rd_data;
                        rx_payload_count <= 32'd0;

                        case (rx_frame_type)
                            RX_FRAME_TYPE_WRITE_REG: begin
                                if (rx_fifo_rd_data != 32'd1) begin
                                    rx_frame_error <= 1'b1;
                                end
                            end

                            RX_FRAME_TYPE_READ_REG: begin
                                if (rx_fifo_rd_data != 32'd1) begin
                                    rx_frame_error <= 1'b1;
                                end
                            end

                            RX_FRAME_TYPE_RX_DATA: begin
                            end

                            RX_FRAME_TYPE_START_STREAM: begin
                                if (rx_fifo_rd_data == 32'd0) begin
                                    rx_start_stream_valid       <= 1'b1;
                                    tx_start_stream_ack_pending <= 1'b1;
                                end else begin
                                    rx_frame_error <= 1'b1;
                                end
                            end

                            RX_FRAME_TYPE_STOP_STREAM: begin
                                if (rx_fifo_rd_data == 32'd0) begin
                                    rx_stop_stream_valid       <= 1'b1;
                                    tx_stop_stream_ack_pending <= 1'b1;
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
                    end

                    RX_WRITE_REG: begin
                    end

                    RX_DATA: begin
                        rx_payload_count <= rx_payload_count + 32'd1;
                    end

                    default: begin
                        rx_frame_error <= 1'b1;
                    end
                endcase
            end
        end
    end

    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state              <= TX_IDLE;
            tx_frame_type         <= TX_FRAME_TYPE_ACK;
            tx_payload_len        <= 32'd0;
            tx_payload_count      <= 32'd0;
            tx_ack_payload        <= 32'd0;
            tx_fifo_wr_en         <= 1'b0;
            tx_fifo_wr_data       <= 32'd0;
            tx_data_fifo_rd_en    <= 1'b0;
            tx_data_word          <= 32'd0;
            tx_data_word_valid    <= 1'b0;
            tx_data_read_pending  <= 1'b0;
            tx_reg_cmd_fifo_rd_en <= 1'b0;
            tx_reg_cmd_word       <= 32'd0;
            tx_reg_cmd_word_valid <= 1'b0;
            tx_reg_cmd_read_pending <= 1'b0;
            tx_ack_pop_start      <= 1'b0;
            tx_ack_pop_stop       <= 1'b0;
        end else begin
            tx_fifo_wr_en         <= 1'b0;
            tx_data_fifo_rd_en    <= 1'b0;
            tx_reg_cmd_fifo_rd_en <= 1'b0;
            tx_ack_pop_start      <= 1'b0;
            tx_ack_pop_stop       <= 1'b0;

            if (tx_data_fifo_valid) begin
                tx_data_word       <= tx_data_fifo_rd_data;
                tx_data_word_valid <= 1'b1;
                tx_data_read_pending <= 1'b0;
            end

            if (tx_reg_cmd_fifo_valid) begin
                tx_reg_cmd_word       <= tx_reg_cmd_fifo_rd_data;
                tx_reg_cmd_word_valid <= 1'b1;
                tx_reg_cmd_read_pending <= 1'b0;
            end

            case (tx_state)
                TX_IDLE: begin
                    tx_payload_count <= 32'd0;

                    if (tx_start_stream_ack_pending && tx_fifo_can_start_short_frame) begin
                        tx_frame_type    <= TX_FRAME_TYPE_ACK;
                        tx_payload_len   <= 32'd1;
                        tx_ack_payload   <= {24'd0, RX_FRAME_TYPE_START_STREAM};
                        tx_ack_pop_start <= 1'b1;
                        tx_state         <= TX_WRITE_MAGIC;
                    end else if (tx_stop_stream_ack_pending && tx_fifo_can_start_short_frame) begin
                        tx_frame_type   <= TX_FRAME_TYPE_ACK;
                        tx_payload_len  <= 32'd1;
                        tx_ack_payload  <= {24'd0, RX_FRAME_TYPE_STOP_STREAM};
                        tx_ack_pop_stop <= 1'b1;
                        tx_state        <= TX_WRITE_MAGIC;
                    end else if (!tx_reg_cmd_fifo_empty && tx_fifo_can_start_short_frame) begin
                        tx_frame_type             <= TX_FRAME_TYPE_REG_DATA;
                        tx_payload_len            <= 32'd1;
                        tx_reg_cmd_word_valid     <= 1'b0;
                        tx_reg_cmd_fifo_rd_en     <= 1'b1;
                        tx_reg_cmd_read_pending   <= 1'b1;
                        tx_state                  <= TX_WRITE_MAGIC;
                    end else if (tx_data_packet_ready && tx_fifo_can_start_data_frame) begin
                        tx_frame_type      <= TX_FRAME_TYPE_TX_DATA;
                        tx_payload_len     <= DATA_PACKET_WORDS;
                        tx_payload_count   <= 32'd0;
                        tx_data_word_valid <= 1'b0;
                        tx_state           <= TX_WRITE_MAGIC;
                    end
                end

                TX_WRITE_MAGIC: begin
                    if (tx_output_ready) begin
                        tx_fifo_wr_en   <= 1'b1;
                        tx_fifo_wr_data <= FRAME_MAGIC;
                        tx_state        <= TX_WRITE_INFO;
                    end
                end

                TX_WRITE_INFO: begin
                    if (tx_output_ready) begin
                        tx_fifo_wr_en   <= 1'b1;
                        tx_fifo_wr_data <= make_tx_info(tx_frame_type);
                        tx_state        <= TX_WRITE_LEN;
                    end
                end

                TX_WRITE_LEN: begin
                    if (tx_output_ready) begin
                        tx_fifo_wr_en    <= 1'b1;
                        tx_fifo_wr_data  <= tx_payload_len;
                        tx_payload_count <= 32'd0;

                        case (tx_frame_type)
                            TX_FRAME_TYPE_REG_DATA: begin
                                tx_state <= TX_REG_DATA;
                            end
                            TX_FRAME_TYPE_TX_DATA: begin
                                tx_state <= TX_DATA;
                            end
                            TX_FRAME_TYPE_ACK: begin
                                tx_state <= TX_ACK;
                            end
                            default: begin
                                tx_state <= TX_IDLE;
                            end
                        endcase
                    end
                end

                TX_REG_DATA: begin
                    if (!tx_reg_cmd_word_valid && !tx_reg_cmd_read_pending &&
                            !tx_reg_cmd_fifo_valid && !tx_reg_cmd_fifo_empty) begin
                        tx_reg_cmd_fifo_rd_en   <= 1'b1;
                        tx_reg_cmd_read_pending <= 1'b1;
                    end

                    if (tx_reg_cmd_word_valid && tx_output_ready) begin
                        tx_fifo_wr_en          <= 1'b1;
                        tx_fifo_wr_data        <= tx_reg_cmd_word;
                        tx_reg_cmd_word_valid  <= 1'b0;
                        tx_state               <= TX_IDLE;
                    end
                end

                TX_DATA: begin
                    if (!tx_data_word_valid && !tx_data_read_pending &&
                            !tx_data_fifo_valid && !tx_data_fifo_empty && tx_output_ready) begin
                        tx_data_fifo_rd_en   <= 1'b1;
                        tx_data_read_pending <= 1'b1;
                    end

                    if (tx_data_word_valid && tx_output_ready) begin
                        tx_fifo_wr_en      <= 1'b1;
                        tx_fifo_wr_data    <= tx_data_word;
                        tx_data_word_valid <= 1'b0;
                        tx_payload_count   <= tx_payload_count + 32'd1;

                        if ((tx_payload_count + 32'd1) >= tx_payload_len) begin
                            tx_state <= TX_IDLE;
                        end
                    end
                end

                TX_ACK: begin
                    if (tx_output_ready) begin
                        tx_fifo_wr_en   <= 1'b1;
                        tx_fifo_wr_data <= tx_ack_payload;
                        tx_state        <= TX_IDLE;
                    end
                end

                default: begin
                    tx_state <= TX_IDLE;
                end
            endcase
        end
    end

    // RX fifos
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

    sync_fifo_32x128 rx_reg_cmd_fifo (
        .clk(sys_clk),
        .srst(!rst_n),
        .din(reg_cmd_fifo_wr_data),
        .wr_en(reg_cmd_fifo_wr_en),
        .rd_en(reg_cmd_fifo_rd_en),
        .dout(reg_cmd_fifo_rd_data),
        .full(reg_cmd_fifo_full),
        .almost_full(reg_cmd_fifo_almost_full),
        .wr_ack(),
        .overflow(),
        .empty(reg_cmd_fifo_empty),
        .almost_empty(reg_cmd_fifo_almost_empty),
        .valid(reg_cmd_fifo_valid),
        .underflow(),
        .data_count(reg_cmd_fifo_data_count)
    );

    // TX fifos
    sync_fifo tx_data_fifo (
        .clk(sys_clk),
        .srst(!rst_n),
        .din(tx_data_fifo_wr_data),
        .wr_en(tx_data_fifo_wr_en_int),
        .rd_en(tx_data_fifo_rd_en),
        .dout(tx_data_fifo_rd_data),
        .full(tx_data_fifo_full),
        .almost_full(tx_data_fifo_almost_full),
        .wr_ack(),
        .overflow(),
        .empty(tx_data_fifo_empty),
        .almost_empty(tx_data_fifo_almost_empty),
        .valid(tx_data_fifo_valid),
        .underflow(),
        .data_count(tx_data_fifo_data_count)
    );

    sync_fifo_32x128 tx_reg_cmd_fifo (
        .clk(sys_clk),
        .srst(!rst_n),
        .din(tx_reg_cmd_fifo_wr_data),
        .wr_en(tx_reg_cmd_fifo_wr_en_int),
        .rd_en(tx_reg_cmd_fifo_rd_en),
        .dout(tx_reg_cmd_fifo_rd_data),
        .full(tx_reg_cmd_fifo_full),
        .almost_full(tx_reg_cmd_fifo_almost_full),
        .wr_ack(),
        .overflow(),
        .empty(tx_reg_cmd_fifo_empty),
        .almost_empty(tx_reg_cmd_fifo_almost_empty),
        .valid(tx_reg_cmd_fifo_valid),
        .underflow(),
        .data_count(tx_reg_cmd_fifo_data_count)
    );

endmodule
