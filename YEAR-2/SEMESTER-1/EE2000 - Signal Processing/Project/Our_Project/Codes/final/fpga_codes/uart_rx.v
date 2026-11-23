`timescale 1ns / 1ps

module uart_rx #(
    parameter integer clk_freq  = 100_000_000,
    parameter integer baud_rate = 2_000_000
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       uart_rxd,
    output reg  [7:0] data_out,
    output reg        framing_error, // Asserted for 1 cycle if stop bit is missing/invalid
    output reg        data_valid     // 1-cycle strobe indicating new valid byte in data_out
);
    
    localparam integer clks_per_bit = clk_freq / baud_rate;
    localparam integer COUNT_WIDTH  = $clog2(clks_per_bit);
    //******Written by Vishwambhar************************
    // Double-flop synchronizer to prevent metastability
    reg rx_sync1, rx_sync2;
    always @(posedge clk) begin
        if (reset) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= uart_rxd;
            rx_sync2 <= rx_sync1;
        end
    end
    
    localparam [1:0] IDLE  = 2'b00,
                     START = 2'b01,
                     DATA  = 2'b10,
                     STOP  = 2'b11;
    
    reg [1:0]               state;
    reg [COUNT_WIDTH-1:0]   clk_count;
    reg [2:0]               bit_index;
    reg [7:0]               bit_shift_reg;
    
    always @(posedge clk) begin
        // Default single-cycle pulses
        data_valid    <= 1'b0;
        framing_error <= 1'b0;
        
        if (reset) begin
            state         <= IDLE;
            clk_count     <= 'd0;
            bit_index     <= 3'd0;
            bit_shift_reg <= 8'd0;
            data_out      <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    clk_count <= 'd0;
                    if (rx_sync2 == 1'b0) begin
                        state <= START;
                    end
                end
                
                START: begin
                    if (clk_count == ((clks_per_bit / 2) - 1)) begin
                        if (rx_sync2 == 1'b0) begin // Confirm valid start bit at midpoint
                            clk_count <= 'd0;
                            bit_index <= 3'd0;
                            state     <= DATA;
                        end else begin
                            state     <= IDLE;      // False start (noise glitch)
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                
                DATA: begin
                    if (clk_count == (clks_per_bit - 1)) begin
                        clk_count                <= 'd0;
                        bit_shift_reg[bit_index] <= rx_sync2;
                        
                        if (bit_index == 3'd7) begin
                            state     <= STOP;
                            bit_index <= 3'd0;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                
                STOP: begin
                    if (clk_count == (clks_per_bit - 1)) begin
                        clk_count <= 'd0;
                        state     <= IDLE;
                        
                        if (rx_sync2 == 1'b1) begin
                            data_out   <= bit_shift_reg;
                            data_valid <= 1'b1;
                        end else begin
                            framing_error <= 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                
                default: begin
                    state     <= IDLE;
                    clk_count <= 'd0;
                end
            endcase
        end
    end

endmodule