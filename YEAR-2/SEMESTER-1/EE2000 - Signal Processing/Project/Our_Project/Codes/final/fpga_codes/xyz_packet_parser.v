`timescale 1ns / 1ps

// Packet format:
// 0xAA 0x55 <speed_code>
// Then 1024 x {X_hi, X_lo, Y_hi, Y_lo, Z_hi, Z_lo}
//******Written by Vishwambhar************************
module xyz_packet_parser (
    input  wire        clk,
    input  wire        reset,
    input  wire [7:0]  data_in,
    input  wire        data_valid,
    input  wire        buffer_release,
    output wire parser_busy,

    output wire        buffer_full,
    output reg  [7:0]  speed_code,
    output reg         overrun,

    // FFT read ports (Synchronous for Block RAM inference)
    input  wire [9:0]  fft_read_addr_x,
    input  wire [9:0]  fft_read_addr_y,
    input  wire [9:0]  fft_read_addr_z,

    output reg signed [15:0] fft_read_x,
    output reg signed [15:0] fft_read_y,
    output reg signed [15:0] fft_read_z
);

    localparam integer BUFFER_SIZE   = 1024;
    localparam integer PAYLOAD_BYTES = BUFFER_SIZE * 6;

    localparam [2:0] S_WAIT_AA = 3'd0,
                     S_WAIT_55 = 3'd1,
                     S_SPEED   = 3'd2,
                     S_PAYLOAD = 3'd3,
                     S_DROP    = 3'd4;

    reg [2:0]  state;
    reg [2:0]  byte_index;      // 0 to 5
    reg [9:0]  sample_count;    // 0 to 1023
    reg [12:0] drop_count;      // 0 to 6144

    reg full_r;

    reg [7:0] x_high;
    reg [7:0] y_high;
    reg [7:0] z_high;

    // ------------------------------------------------
    // Sample Buffers (Infers BRAM)
    // ------------------------------------------------
    (* ram_style = "block" *) reg signed [15:0] x_mem [0:BUFFER_SIZE-1];
    (* ram_style = "block" *) reg signed [15:0] y_mem [0:BUFFER_SIZE-1];
    (* ram_style = "block" *) reg signed [15:0] z_mem [0:BUFFER_SIZE-1];

    assign buffer_full = full_r & ~buffer_release;
    assign parser_busy = (state == S_SPEED) || (state == S_PAYLOAD) || (state == S_DROP);

    // Synchronous read ports (1 clock cycle latency, BRAM compatible)
    always @(posedge clk) begin
        fft_read_x <= x_mem[fft_read_addr_x];
        fft_read_y <= y_mem[fft_read_addr_y];
        fft_read_z <= z_mem[fft_read_addr_z];
    end

    // ------------------------------------------------
    // Packet Parser FSM
    // ------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state        <= S_WAIT_AA;
            byte_index   <= 3'd0;
            sample_count <= 10'd0;
            drop_count   <= 13'd0;
            full_r       <= 1'b0;
            speed_code   <= 8'd0;
            overrun      <= 1'b0;
            x_high       <= 8'd0;
            y_high       <= 8'd0;
            z_high       <= 8'd0;
        end else begin
            overrun <= 1'b0;

            if (buffer_release)
                full_r <= 1'b0;

            if (data_valid) begin
                case (state)
                    S_WAIT_AA: begin
                        if (data_in == 8'hAA)
                            state <= S_WAIT_55;
                    end

                    S_WAIT_55: begin
                        if (data_in == 8'h55)
                            state <= S_SPEED;
                        else if (data_in != 8'hAA)
                            state <= S_WAIT_AA;
                    end

                    S_SPEED: begin
                        if (full_r && !buffer_release) begin
                            overrun    <= 1'b1;
                            drop_count <= PAYLOAD_BYTES;
                            state      <= S_DROP;
                        end else begin
                            speed_code   <= data_in;
                            byte_index   <= 3'd0;
                            sample_count <= 10'd0;
                            state        <= S_PAYLOAD;
                        end
                    end

                    S_PAYLOAD: begin
                        case (byte_index)
                            3'd0: begin
                                x_high     <= data_in;
                                byte_index <= 3'd1;
                            end
                            3'd1: begin
                                x_mem[sample_count] <= {x_high, data_in};
                                byte_index          <= 3'd2;
                            end
                            3'd2: begin
                                y_high     <= data_in;
                                byte_index <= 3'd3;
                            end
                            3'd3: begin
                                y_mem[sample_count] <= {y_high, data_in};
                                byte_index          <= 3'd4;
                            end
                            3'd4: begin
                                z_high     <= data_in;
                                byte_index <= 3'd5;
                            end
                            3'd5: begin
                                z_mem[sample_count] <= {z_high, data_in};
                                byte_index          <= 3'd0;

                                if (sample_count == (BUFFER_SIZE - 1)) begin
                                    full_r       <= 1'b1;
                                    sample_count <= 10'd0;
                                    state        <= S_WAIT_AA;
                                end else begin
                                    sample_count <= sample_count + 10'd1;
                                end
                            end
                            default: byte_index <= 3'd0;
                        endcase
                    end

                    S_DROP: begin
                        if (drop_count <= 13'd1) begin
                            drop_count <= 13'd0;
                            state      <= S_WAIT_AA;
                        end else begin
                            drop_count <= drop_count - 13'd1;
                        end
                    end

                    default: state <= S_WAIT_AA;
                endcase
            end
        end
    end

endmodule