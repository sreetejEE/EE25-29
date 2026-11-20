`timescale 1ns / 1ps
//******Written by Dhanush************************
module uart_tx #(
    parameter integer clk_freq  = 100_000_000,
    parameter integer baud_rate = 2_000_000
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        uart_txd,
    output reg        tx_busy
);

    localparam integer clks_per_bit = clk_freq / baud_rate;
    localparam integer COUNT_WIDTH  = $clog2(clks_per_bit);

    localparam [1:0] IDLE  = 2'b00,
                     START = 2'b01,
                     DATA  = 2'b10,
                     STOP  = 2'b11;

    reg [1:0]             state;
    reg [COUNT_WIDTH-1:0] clk_count;
    reg [2:0]             bit_idx;
    reg [7:0]             shift_reg;

    always @(posedge clk) begin
        if (reset) begin
            state     <= IDLE;
            uart_txd  <= 1'b1;
            tx_busy   <= 1'b0;
            clk_count <= 'd0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    uart_txd  <= 1'b1;
                    clk_count <= 'd0;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                        state     <= START;
                    end else begin
                        tx_busy <= 1'b0;
                    end
                end

                START: begin
                    uart_txd <= 1'b0;
                    if (clk_count == (clks_per_bit - 1)) begin
                        clk_count <= 'd0;
                        bit_idx   <= 3'd0;
                        state     <= DATA;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                DATA: begin
                    uart_txd <= shift_reg[bit_idx];
                    if (clk_count == (clks_per_bit - 1)) begin
                        clk_count <= 'd0;
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                STOP: begin
                    uart_txd <= 1'b1;
                    if (clk_count == (clks_per_bit - 1)) begin
                        clk_count <= 'd0;
                        tx_busy   <= 1'b0;
                        state     <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule