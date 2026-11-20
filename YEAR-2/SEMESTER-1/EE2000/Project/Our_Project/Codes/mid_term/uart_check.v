`timescale 1ns / 1ps

module uart_fft_top #(
    parameter integer SIM_CLK_FREQ = 100_000_000
)(

    // ============================================================
    // CLOCK AND RESET
    // ============================================================

    input wire clk,
    input wire reset,

    // ============================================================
    // UART INPUT
    // ============================================================

    input wire uart_rxd,

    // ============================================================
    // FFT SPECTRUM SELECTION
    //
    // bin_addr[9:8]:
    //   00 = X axis
    //   01 = Y axis
    //   10 = Z axis
    //
    // bin_addr[7:0]:
    //   FFT bin index, 0 to 255
    // ============================================================

    input wire [9:0] bin_addr,

    // ============================================================
    // STATUS OUTPUTS
    // ============================================================

    output wire [7:0] speed_code,
    output wire buffer_full,
    output wire framing_error,
    output wire fft_done,

    // ============================================================
    // SELECTED FFT RESULT
    // ============================================================

    output wire signed [31:0] bin_re,
    output wire signed [31:0] bin_im

);

    // ============================================================
    // 1. UART RECEIVER SIGNALS
    // ============================================================

    wire [7:0] uart_data;
    wire uart_data_valid;


    // ============================================================
    // 2. PARSER <-> FFT CONTROLLER SIGNALS
    // ============================================================

    wire buffer_release;

    wire [7:0] parser_addr;

    wire signed [15:0] parser_x;
    wire signed [15:0] parser_y;
    wire signed [15:0] parser_z;


    // ============================================================
    // 3. UART RECEIVER
    // ============================================================

    uart_rx #(
            .clk_freq (SIM_CLK_FREQ),
            .baud_rate(300000)
        ) uart_rx_inst (

        .clk(clk),
        .reset(reset),

        .uart_rxd(uart_rxd),

        .data_out(uart_data),
        .data_valid(uart_data_valid),
        .framing_error(framing_error)

    );


    // ============================================================
    // 4. XYZ PACKET PARSER
    // ============================================================

    xyz_packet_parser parser_inst (

        .clk(clk),
        .reset(reset),

        // UART receiver interface
        .data_in(uart_data),
        .data_valid(uart_data_valid),

        // Buffer handshake
        .buffer_release(buffer_release),

        // Packet metadata
        .speed_code(speed_code),
        .buffer_full(buffer_full),

        // FFT sample addresses
        .fft_read_addr_x(parser_addr),
        .fft_read_addr_y(parser_addr),
        .fft_read_addr_z(parser_addr),

        // Signed 16-bit samples
        .fft_read_x(parser_x),
        .fft_read_y(parser_y),
        .fft_read_z(parser_z)

    );


    // ============================================================
    // 5. FFT CONTROLLER
    //
    // Processes X, Y and Z sequentially using xfft_0.
    // Reads samples from the parser and stores FFT results.
    // ============================================================

    fft_controller fft_controller_inst (

        .clk(clk),
        .reset(reset),

        // Parser buffer control
        .buffer_full(buffer_full),
        .buffer_release(buffer_release),

        // Parser memory read interface
        .parser_addr(parser_addr),

        .parser_x(parser_x),
        .parser_y(parser_y),
        .parser_z(parser_z),

        // Spectrum selection
        .bin_addr(bin_addr),

        // Selected FFT result
        .bin_re(bin_re),
        .bin_im(bin_im),

        // Processing completion
        .fft_done(fft_done)

    );


endmodule