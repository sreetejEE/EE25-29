`timescale 1ns / 1ps
//******Written by Sreetej************************
module hann_window_xyz #(
    parameter integer BUFFER_SIZE = 1024,
    parameter         COEFF_FILE  = "hann_1024_q15.mem"
)(
    input  wire        clk,
    input  wire        reset,

    // Interface to xyz_packet_parser
    input  wire        parser_buffer_full,
    output reg         parser_buffer_release,
    output wire [9:0]  parser_read_addr,
    input  wire signed [15:0] parser_read_x,
    input  wire signed [15:0] parser_read_y,
    input  wire signed [15:0] parser_read_z,

    // Interface to FFT module (matches xyz_packet_parser port style)
    output wire        win_buffer_full,
    input  wire        win_buffer_release,
    input  wire [9:0]  fft_read_addr_x,
    input  wire [9:0]  fft_read_addr_y,
    input  wire [9:0]  fft_read_addr_z,
    output reg  signed [15:0] fft_read_x,
    output reg  signed [15:0] fft_read_y,
    output reg  signed [15:0] fft_read_z
);

    // ------------------------------------------------------------
    // 1. Synthesizable Hann Coefficient ROM (Q1.15: 0 to 32767)
    // ------------------------------------------------------------
    (* rom_style = "block" *) reg signed [15:0] hann_rom [0:BUFFER_SIZE-1];
    initial begin
        $readmemh(COEFF_FILE, hann_rom);
    end

    // ------------------------------------------------------------
    // 2. Output Windowed Sample Buffers (Infers BRAM)
    // ------------------------------------------------------------
    (* ram_style = "block" *) reg signed [15:0] win_x_mem [0:BUFFER_SIZE-1];
    (* ram_style = "block" *) reg signed [15:0] win_y_mem [0:BUFFER_SIZE-1];
    (* ram_style = "block" *) reg signed [15:0] win_z_mem [0:BUFFER_SIZE-1];

    // Synchronous read ports for FFT (1 clock cycle latency)
    always @(posedge clk) begin
        fft_read_x <= win_x_mem[fft_read_addr_x];
        fft_read_y <= win_y_mem[fft_read_addr_y];
        fft_read_z <= win_z_mem[fft_read_addr_z];
    end

    // ------------------------------------------------------------
    // 3. 3-Stage Pipelined Windowing Engine
    // ------------------------------------------------------------
    localparam [1:0] S_IDLE   = 2'd0,
                     S_STREAM = 2'd1,
                     S_FLUSH  = 2'd2;

    reg [1:0] state;
    reg       win_full_r;

    assign win_buffer_full = win_full_r & ~win_buffer_release;

    // Stage 0: Address generation
    reg [9:0] rd_addr;
    reg       valid_d0;
    assign parser_read_addr = rd_addr;

    // Stage 1: BRAM/ROM read outputs
    reg signed [15:0] hann_coeff;
    reg [9:0]         addr_d1;
    reg               valid_d1;

    always @(posedge clk) begin
        hann_coeff <= hann_rom[rd_addr];
    end

    // Stage 2: Signed Multiplication (Infers DSP48)
    reg signed [31:0] prod_x;
    reg signed [31:0] prod_y;
    reg signed [31:0] prod_z;
    reg [9:0]         addr_d2;
    reg               valid_d2;

    // Rounding helper (+0.5 LSB in Q1.15 before truncation)
    wire signed [31:0] prod_x_rnd = prod_x + 32'sd16384;
    wire signed [31:0] prod_y_rnd = prod_y + 32'sd16384;
    wire signed [31:0] prod_z_rnd = prod_z + 32'sd16384;

    always @(posedge clk) begin
        if (reset) begin
            state                 <= S_IDLE;
            win_full_r            <= 1'b0;
            parser_buffer_release <= 1'b0;
            rd_addr               <= 10'd0;
            valid_d0              <= 1'b0;
            addr_d1               <= 10'd0;
            valid_d1              <= 1'b0;
            addr_d2               <= 10'd0;
            valid_d2              <= 1'b0;
            prod_x                <= 32'sd0;
            prod_y                <= 32'sd0;
            prod_z                <= 32'sd0;
        end else begin
            // Default single-cycle pulse
            parser_buffer_release <= 1'b0;

            if (win_buffer_release)
                win_full_r <= 1'b0;

            // --- Pipeline Stage 1 ---
            addr_d1  <= rd_addr;
            valid_d1 <= valid_d0;

            // --- Pipeline Stage 2 (Multiply) ---
            if (valid_d1) begin
                prod_x <= parser_read_x * hann_coeff;
                prod_y <= parser_read_y * hann_coeff;
                prod_z <= parser_read_z * hann_coeff;
            end
            addr_d2  <= addr_d1;
            valid_d2 <= valid_d1;

            // --- Pipeline Stage 3 (Scale & Write to Output BRAM) ---
            if (valid_d2) begin
                win_x_mem[addr_d2] <= prod_x_rnd[30:15];
                win_y_mem[addr_d2] <= prod_y_rnd[30:15];
                win_z_mem[addr_d2] <= prod_z_rnd[30:15];

                if (addr_d2 == (BUFFER_SIZE - 1)) begin
                    win_full_r            <= 1'b1;
                    parser_buffer_release <= 1'b1; // Free parser for next UART packet
                    state                 <= S_IDLE;
                end
            end

            // --- Control FSM ---
            case (state)
                S_IDLE: begin
                    valid_d0 <= 1'b0;
                    rd_addr  <= 10'd0;
                    if (parser_buffer_full && !win_full_r) begin
                        valid_d0 <= 1'b1;
                        state    <= S_STREAM;
                    end
                end

                S_STREAM: begin
                    if (rd_addr == (BUFFER_SIZE - 1)) begin
                        valid_d0 <= 1'b0;
                        state    <= S_FLUSH;
                    end else begin
                        rd_addr  <= rd_addr + 10'd1;
                        valid_d0 <= 1'b1;
                    end
                end

                S_FLUSH: begin
                    valid_d0 <= 1'b0;
                    // State returns to S_IDLE when addr_d2 == 1023 completes above
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule