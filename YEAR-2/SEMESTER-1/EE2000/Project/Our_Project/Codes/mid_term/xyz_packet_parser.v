`timescale 1ns / 1ps

// Packet format (from matlab_vibration_uart_sender.m):
//   0xAA 0x55 <speed_code> then 256 x {X_hi, X_lo, Y_hi, Y_lo, Z_hi, Z_lo}

module xyz_packet_parser (
    input  wire       clk,
    input  wire       reset,
    input  wire [7:0] data_in,//data from uart
    input  wire       data_valid, //indication of valid data from uart_rx code
    input  wire       buffer_release,//This goes high when fft is done and buffer is ready to take data again
    output wire       buffer_full,//This is when buffer completely reads and stores all 256 samples
    output reg  [7:0] speed_code,//RPM of the motor
    output reg        overrun,        // packet dropped because buffer was busy
    // FFT read port (combinational)
    input  wire [7:0]        fft_read_addr_x,
    input  wire [7:0]        fft_read_addr_y,
    input  wire [7:0]        fft_read_addr_z,
    output wire signed [15:0] fft_read_x,
    output wire signed [15:0] fft_read_y,
    output wire signed [15:0] fft_read_z
);
    //All the states
    localparam [2:0] S_WAIT_AA = 3'd0;
    localparam [2:0] S_WAIT_55 = 3'd1;
    localparam [2:0] S_SPEED   = 3'd2;
    localparam [2:0] S_PAYLOAD = 3'd3;
    localparam [2:0] S_DROP    = 3'd4;

    localparam integer PAYLOAD_BYTES = 256 * 6;   // 1536(total number of samples)

    reg [2:0]  state;
    reg [2:0]  byte_index;     // position within one XYZ sample (0..5)
    reg [7:0]  sample_count;   // samples stored so far in the current packet
    reg [10:0] drop_count;     // payload bytes still to skip in S_DROP
    reg        full_r;         // registered buffer-full flag

    reg [7:0]  x_high, y_high, z_high;

    reg signed [15:0] x_mem [0:255];
    reg signed [15:0] y_mem [0:255];
    reg signed [15:0] z_mem [0:255];

    // Outputs
    assign buffer_full = full_r & ~buffer_release;

    assign fft_read_x = x_mem[fft_read_addr_x];
    assign fft_read_y = y_mem[fft_read_addr_y];
    assign fft_read_z = z_mem[fft_read_addr_z];

    // Parser
    always @(posedge clk) begin
        if (reset) begin
            state        <= S_WAIT_AA;
            byte_index   <= 3'd0;
            sample_count <= 8'd0;
            drop_count   <= 11'd0;
            full_r       <= 1'b0;
            speed_code   <= 8'd0;
            overrun      <= 1'b0;
            x_high       <= 8'd0;
            y_high       <= 8'd0;
            z_high       <= 8'd0;
        end
        else begin
            // Release first; a set in this same cycle (not possible in normal
            // operation) takes priority below.
            if (buffer_release)
                full_r <= 1'b0;

            if (data_valid) begin
                case (state)

                    // Header search
                    S_WAIT_AA: begin
                        if (data_in == 8'hAA)
                            state <= S_WAIT_55;
                    end

                    S_WAIT_55: begin
                        if (data_in == 8'h55)
                            state <= S_SPEED;
                        else if (data_in != 8'hAA)
                            state <= S_WAIT_AA;
                        // AA AA 55: stay in WAIT_55 on a repeated AA
                    end

                    // Speed code: accept, or drop the packet
                    S_SPEED: begin
                        if (full_r) begin
                            // FFT still owns the buffer: discard this packet
                            overrun    <= 1'b1;
                            drop_count <= PAYLOAD_BYTES;
                            state      <= S_DROP;
                        end
                        else begin
                            speed_code   <= data_in;
                            byte_index   <= 3'd0;
                            sample_count <= 8'd0;
                            state        <= S_PAYLOAD;
                        end
                    end

                    // Payload: 256 x 6 bytes
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
                            default: begin // 3'd5: Z low byte completes the sample
                                z_mem[sample_count] <= {z_high, data_in};
                                byte_index          <= 3'd0;

                                if (sample_count == 8'd255) begin
                                    full_r       <= 1'b1;   // set wins over release
                                    sample_count <= 8'd0;
                                    state        <= S_WAIT_AA;
                                end
                                else begin
                                    sample_count <= sample_count + 1'b1;
                                end
                            end
                        endcase
                    end

                    // Skip the payload of a discarded packet
                    S_DROP: begin
                        drop_count <= drop_count - 1'b1;
                        if (drop_count == 11'd1)
                            state <= S_WAIT_AA;
                    end

                    default: begin
                        state <= S_WAIT_AA;
                    end

                endcase
            end
        end
    end

endmodule