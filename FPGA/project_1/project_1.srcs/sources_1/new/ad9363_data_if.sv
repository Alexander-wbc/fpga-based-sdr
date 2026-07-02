`timescale 1ns / 1ps


module ad9363_data_if (
    input  logic        rst_n,
    input  logic        sys_clk,

    // AD9363 CMOS dual-port, full-duplex interface
    input  logic        ad_data_clk,
    input  logic        ad_rx_frame,
    input  logic [11:0] ad_p0_rx_data,
    output logic        ad_fb_clk,
    output logic        ad_tx_frame,
    output logic [11:0] ad_p1_tx_data,
    output logic        ad_enable,
    output logic        ad_txnrx,

    // RX FIFO read interface, sys_clk domain
    input  logic        rx_fifo_rd_en,
    output logic [23:0] rx_fifo_data,
    output logic        rx_fifo_empty,
    output logic        rx_fifo_almost_empty,
    output logic        rx_fifo_valid,
    output logic [6:0]  rx_fifo_data_count,
    output logic        rx_fifo_overflow,

    // TX FIFO write interface, sys_clk domain
    input  logic        tx_fifo_wr_en,
    input  logic [23:0] tx_fifo_data,
    output logic        tx_fifo_wr_ready,
    output logic        tx_fifo_full,
    output logic        tx_fifo_almost_full,
    output logic [6:0]  tx_fifo_data_count,
    output logic        tx_fifo_underflow
);

    typedef enum logic [1:0] {
        TX_WAIT_DATA,
        TX_WAIT_VALID,
        TX_SEND_Q
    } tx_state_t;

    logic data_clk;
    logic fifo_rst;

    // RX, DATA_CLK domain
    logic [11:0] rx_i_data;
    logic        rx_i_valid;
    logic [23:0] rx_fifo_din;
    logic        rx_fifo_wr_en;
    logic        rx_fifo_full_int;
    logic        rx_fifo_almost_full_int;
    logic        rx_fifo_wr_rst_busy;
    logic        rx_fifo_rd_rst_busy;

    // TX, DATA_CLK domain
    tx_state_t   tx_state;
    logic [23:0] tx_fifo_dout;
    logic        tx_fifo_rd_en;
    logic        tx_fifo_full_int;
    logic        tx_fifo_almost_full_int;
    logic        tx_fifo_empty_int;
    logic        tx_fifo_almost_empty_int;
    logic        tx_fifo_valid_int;
    logic        tx_fifo_wr_rst_busy;
    logic        tx_fifo_rd_rst_busy;
    logic [11:0] tx_q_data;

    assign fifo_rst = !rst_n;

    BUFG u_data_clk_bufg (
        .I(ad_data_clk),
        .O(data_clk)
    );

    // Forward DATA_CLK to FB_CLK with an output DDR register.  TX data and
    // TX_FRAME change on DATA_CLK falling edges and are therefore stable for
    // half a cycle before the AD9363 samples them on FB_CLK rising edges.
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("ASYNC")
    ) u_fb_clk_oddr (
        .Q(ad_fb_clk),
        .C(data_clk),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R(!rst_n),
        .S(1'b0)
    );

    // Normal full-duplex FDD operation: ENABLE remains asserted. TXNRX is
    // ignored by the AD9363 in normal FDD mode but must have a valid level.
    always_ff @(posedge data_clk or negedge rst_n) begin
        if (!rst_n) begin
            ad_enable <= 1'b0;
            ad_txnrx  <= 1'b0;
        end else begin
            ad_enable <= 1'b1;
            ad_txnrx  <= 1'b1;
        end
    end

    // Receive I on an RX_FRAME-high cycle and Q on the following low cycle.
    // A complete {I,Q} pair is written atomically to the asynchronous FIFO.
    always_ff @(posedge data_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_i_data        <= 12'd0;
            rx_i_valid       <= 1'b0;
            rx_fifo_din      <= 24'd0;
            rx_fifo_wr_en    <= 1'b0;
            rx_fifo_overflow <= 1'b0;
        end else begin
            rx_fifo_wr_en <= 1'b0;

            if (ad_rx_frame) begin
                rx_i_data  <= ad_p0_rx_data;
                rx_i_valid <= 1'b1;
            end else if (rx_i_valid) begin
                rx_i_valid <= 1'b0;

                if (!rx_fifo_full_int && !rx_fifo_wr_rst_busy) begin
                    rx_fifo_din   <= {rx_i_data, ad_p0_rx_data};
                    rx_fifo_wr_en <= 1'b1;
                end else begin
                    // RX cannot be backpressured; discard the complete pair.
                    rx_fifo_overflow <= 1'b1;
                end
            end
        end
    end

    async_fifo_24x128 u_rx_data_fifo (
        .rst(fifo_rst),
        .wr_clk(data_clk),
        .rd_clk(sys_clk),
        .din(rx_fifo_din),
        .wr_en(rx_fifo_wr_en),
        .rd_en(rx_fifo_rd_en && !rx_fifo_empty && !rx_fifo_rd_rst_busy),
        .dout(rx_fifo_data),
        .full(rx_fifo_full_int),
        .almost_full(rx_fifo_almost_full_int),
        .wr_ack(),
        .overflow(),
        .empty(rx_fifo_empty),
        .almost_empty(rx_fifo_almost_empty),
        .valid(rx_fifo_valid),
        .underflow(),
        .rd_data_count(rx_fifo_data_count),
        .wr_data_count(),
        .wr_rst_busy(rx_fifo_wr_rst_busy),
        .rd_rst_busy(rx_fifo_rd_rst_busy)
    );

    assign tx_fifo_full        = tx_fifo_full_int;
    assign tx_fifo_almost_full = tx_fifo_almost_full_int;
    assign tx_fifo_wr_ready =
        !tx_fifo_full_int && !tx_fifo_wr_rst_busy;

    async_fifo_24x128 u_tx_data_fifo (
        .rst(fifo_rst),
        .wr_clk(sys_clk),
        .rd_clk(data_clk),
        .din(tx_fifo_data),
        .wr_en(tx_fifo_wr_en && tx_fifo_wr_ready),
        .rd_en(tx_fifo_rd_en),
        .dout(tx_fifo_dout),
        .full(tx_fifo_full_int),
        .almost_full(tx_fifo_almost_full_int),
        .wr_ack(),
        .overflow(),
        .empty(tx_fifo_empty_int),
        .almost_empty(tx_fifo_almost_empty_int),
        .valid(tx_fifo_valid_int),
        .underflow(),
        .rd_data_count(),
        .wr_data_count(tx_fifo_data_count),
        .wr_rst_busy(tx_fifo_wr_rst_busy),
        .rd_rst_busy(tx_fifo_rd_rst_busy)
    );

    // The AD9363 samples SDR transmit data on FB_CLK rising edges.  Updating
    // Port 1 on falling edges provides half a DATA_CLK period of setup time.
    // A new FIFO read is requested while Q is being presented, allowing the
    // next I word to follow without an idle cycle when FIFO data is available.
    always_ff @(negedge data_clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state          <= TX_WAIT_DATA;
            tx_fifo_rd_en     <= 1'b0;
            tx_q_data         <= 12'd0;
            ad_p1_tx_data     <= 12'd0;
            ad_tx_frame       <= 1'b0;
            tx_fifo_underflow <= 1'b0;
        end else begin
            tx_fifo_rd_en <= 1'b0;

            case (tx_state)
                TX_WAIT_DATA: begin
                    ad_p1_tx_data <= 12'd0;
                    ad_tx_frame   <= 1'b0;

                    if (!tx_fifo_empty_int && !tx_fifo_rd_rst_busy) begin
                        tx_fifo_rd_en <= 1'b1;
                        tx_state      <= TX_WAIT_VALID;
                    end
                end

                TX_WAIT_VALID: begin
                    if (tx_fifo_valid_int) begin
                        ad_p1_tx_data <= tx_fifo_dout[23:12];
                        ad_tx_frame   <= 1'b1;
                        tx_q_data     <= tx_fifo_dout[11:0];
                        tx_state      <= TX_SEND_Q;
                    end
                end

                TX_SEND_Q: begin
                    ad_p1_tx_data <= tx_q_data;
                    ad_tx_frame   <= 1'b0;

                    if (!tx_fifo_empty_int && !tx_fifo_rd_rst_busy) begin
                        tx_fifo_rd_en <= 1'b1;
                        tx_state      <= TX_WAIT_VALID;
                    end else begin
                        tx_fifo_underflow <= 1'b1;
                        tx_state          <= TX_WAIT_DATA;
                    end
                end

                default: begin
                    tx_state <= TX_WAIT_DATA;
                end
            endcase
        end
    end

endmodule
