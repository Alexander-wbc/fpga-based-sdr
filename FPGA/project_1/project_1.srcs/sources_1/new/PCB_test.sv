`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/19 21:20:39
// Design Name: 
// Module Name: PCB_test
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


module PCB_test(
    input  logic clk,
    input  logic rst_n,

    output logic o_led_0,
    output logic o_led_1,
    output logic o_led_2
);

    logic [25:0] cnt;
    logic [1:0]  led_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt       <= 26'd0;
            led_state <= 2'd0;
        end
        else begin
            if (cnt == 26'd49_999_999) begin
                cnt <= 26'd0;

                if (led_state == 2'd2)
                    led_state <= 2'd0;
                else
                    led_state <= led_state + 2'd1;
            end
            else begin
                cnt <= cnt + 26'd1;
            end
        end
    end

    always_comb begin
        o_led_0 = 1'b0;
        o_led_1 = 1'b0;
        o_led_2 = 1'b0;

        case (led_state)
            2'd0: o_led_0 = 1'b1;
            2'd1: o_led_1 = 1'b1;
            2'd2: o_led_2 = 1'b1;
            default: begin
                o_led_0 = 1'b0;
                o_led_1 = 1'b0;
                o_led_2 = 1'b0;
            end
        endcase
    end

endmodule
