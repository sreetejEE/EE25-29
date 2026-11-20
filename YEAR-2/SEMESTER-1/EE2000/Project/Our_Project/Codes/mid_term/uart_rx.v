`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 20.10.2026 16:12:08
// Design Name: 
// Module Name: uart_rx
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


module uart_rx #(
    parameter integer clk_freq = 100_000_000,
    parameter integer baud_rate = 300000)(
    input clk,
    input reset,
    input uart_rxd, //received the bit
    output reg [7:0] data_out,
    output reg framing_error, //two bytes will be combined to get a single 16-bit integer
    output reg data_valid); //a flag kind of thing after which the two bytes are combined in the upcoming module to get the data
    
    localparam integer clks_per_bit = clk_freq/baud_rate;
    
    //The following always block is for a synchroniser which avoids metastability from affecting flip-flops
    reg rx_sync1, rx_sync2;
    
    always @(posedge clk)begin
        if(reset)begin
            rx_sync1<=1'b1;
            rx_sync2<=1'b1;
        end
        else begin
            rx_sync1<=uart_rxd;
            rx_sync2<=rx_sync1;
        end
    end
    
    localparam IDLE = 2'b00;
    localparam START = 2'b01;
    localparam DATA = 2'b10;
    localparam STOP = 2'b11;
    
    reg [1:0] state;
    reg [9:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] bit_shift_reg;
    
    always @(posedge clk)begin
        data_valid <= 1'b0;
        framing_error <= 1'b0;
        if (reset) begin
            state         <= IDLE;
            clk_count     <= 0;
            bit_index     <= 0;
            bit_shift_reg <= 8'b0;
            data_out      <= 8'b0;
            data_valid    <= 1'b0;
            framing_error <= 1'b0;
        end
        
        else begin
            case(state)
                IDLE:begin
                    clk_count<=10'b0;
                    if(rx_sync2==1'b0)begin
                        state<=START;
                    end
                    end
                START:
                    begin
                        if(clk_count==((clks_per_bit/2)-1))begin
                            if(rx_sync2 == 1'b0)begin
                                clk_count<= 10'b0;
                                bit_index <= 3'b0;
                                state <= DATA;
                                
                            end
                            else begin
                                state<=IDLE;
                            end
                        end
                        else begin
                            clk_count<=clk_count+10'b1;
                        end
                    end
                DATA:
                    begin
                        if(clk_count == (clks_per_bit-1))begin
                            clk_count <=10'b0;
                            bit_shift_reg[bit_index] <= rx_sync2;
                            if(bit_index==3'd7)begin
                                state<=STOP;
                                bit_index  <= 3'b0; 
                            end
                            else begin
                                bit_index <= bit_index + 3'b1;
                            end
                            
                        end
                        else begin
                            clk_count <= clk_count  + 10'b1;
                        end
                    end
                STOP:
                    begin
                        if(clk_count == (clks_per_bit-1))begin
                            clk_count <= 10'b0;
                            state <= IDLE;
                            if(rx_sync2 == 1'b1)begin
                                data_out<= bit_shift_reg;
                                data_valid <= 1'b1;
                                
                            end
                            else begin
                                framing_error <= 1'b1;
                            end
                            
                        end
                        else begin
                            clk_count <= clk_count+10'b1;
                        end
                    end
                default:
                    begin
                        state<=IDLE;
                        clk_count<=10'b0;
                    end  
            endcase
        end
    end    
endmodule
