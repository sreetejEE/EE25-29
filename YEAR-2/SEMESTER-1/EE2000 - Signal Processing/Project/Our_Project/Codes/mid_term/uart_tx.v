`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// uart_tx : 8N1 UART transmitter (mirror of uart_rx)
//
//   send     : one-clock pulse; data_in is captured on that clock
//   busy     : high from the clock after `send` until the stop bit has finished
//   Do not pulse `send` while busy is high.
//////////////////////////////////////////////////////////////////////////////////

module uart_tx #(
    parameter integer clk_freq  = 100_000_000,
    parameter integer baud_rate = 300000
)(
    input  wire       clk,
    input  wire       reset,
    input  wire [7:0] data_in,
    input  wire       send,
    output reg        tx,
    output reg        busy
);

    localparam integer clks_per_bit = clk_freq / baud_rate;

    localparam [1:0] IDLE  = 2'd0;
    localparam [1:0] START = 2'd1;
    localparam [1:0] DATA  = 2'd2;
    localparam [1:0] STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  shift;

    always @(posedge clk) begin
        if (reset) begin
            state     <= IDLE;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            shift     <= 8'd0;
            tx        <= 1'b1;
            busy      <= 1'b0;
        end
        else begin
            case (state)

                IDLE: begin
                    tx        <= 1'b1;
                    busy      <= 1'b0;
                    clk_count <= 16'd0;
                    if (send) begin
                        shift <= data_in;
                        busy  <= 1'b1;
                        tx    <= 1'b0;              // start bit
                        state <= START;
                    end
                end

                START: begin
                    if (clk_count == clks_per_bit - 1) begin
                        clk_count <= 16'd0;
                        bit_index <= 3'd0;
                        tx        <= shift[0];      // first data bit (LSB)
                        state     <= DATA;
                    end
                    else
                        clk_count <= clk_count + 1'b1;
                end

                DATA: begin
                    if (clk_count == clks_per_bit - 1) begin
                        clk_count <= 16'd0;
                        if (bit_index == 3'd7) begin
                            tx    <= 1'b1;          // stop bit
                            state <= STOP;
                        end
                        else begin
                            bit_index <= bit_index + 1'b1;
                            tx        <= shift[bit_index + 1'b1];
                        end
                    end
                    else
                        clk_count <= clk_count + 1'b1;
                end

                STOP: begin
                    if (clk_count == clks_per_bit - 1) begin
                        clk_count <= 16'd0;
                        busy      <= 1'b0;
                        state     <= IDLE;
                    end
                    else
                        clk_count <= clk_count + 1'b1;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule