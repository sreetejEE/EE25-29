`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// board_top (Boolean Board)
//
// UART in  -> uart_fft_top -> spectrum_sender -> uart_tx -> UART out (to MATLAB)
//
// Switch readout:
//   sw[15:14] : Axis selection (00: X, 01: Y, 10: Z)
//   sw[7:0]   : FFT bin selection (0..127)
//
// LEDs:
//   led[15]   : Complete packet received (buffer_full seen, sticky)
//   led[14]   : FFT finished (fft_done seen, sticky)
//   led[13]   : UART framing error seen (sticky)
//   led[12]   : Spectrum frame actively streaming over UART (live)
//   led[11]   : Packet collision flag (sticky)
//   led[10:8] : Tied to 0
//   led[7:0]  : Latched magnitude |Re| + |Im| of switch-selected bin
//
// 7-Segment Displays:
//   D0/D1     : Selected FFT bin index in hex (sw[7:0])
//
// Button:
//   btn[0]    : System reset / clear sticky flags
//////////////////////////////////////////////////////////////////////////////////

module board_top (
    input  wire        clk,
    input  wire        UART_rxd,
    output wire        UART_txd,

    input  wire [15:0] sw,
    output wire [15:0] led,
    input  wire [3:0]  btn,

    output wire [3:0]  D0_AN,
    output wire [7:0]  D0_SEG,
    output wire [3:0]  D1_AN,
    output wire [7:0]  D1_SEG,

    output wire [2:0]  RGB0,
    output wire [2:0]  RGB1
);

    //==========================================================
    // Reset: Power-on hold + btn[0]
    //==========================================================
    reg [7:0] por_cnt = 8'd0;
    wire      por_active = (por_cnt != 8'hFF);

    always @(posedge clk) begin
        if (por_active)
            por_cnt <= por_cnt + 1'b1;
    end

    wire reset = por_active | btn[0];

    //==========================================================
    // FFT Pipeline
    //==========================================================
    wire [9:0]         snd_addr;
    wire               snd_active;
    wire [9:0]         sw_addr  = {sw[15:14], sw[7:0]};
    wire [9:0]         bin_addr = snd_active ? snd_addr : sw_addr;

    wire [7:0]         speed_code;
    wire               buffer_full;
    wire               framing_error;
    wire               fft_done;
    wire signed [31:0] bin_re;
    wire signed [31:0] bin_im;

    uart_fft_top #(
        .SIM_CLK_FREQ(100_000_000)
    ) u_fft (
        .clk          (clk),
        .reset        (reset),
        .uart_rxd     (UART_rxd),
        .bin_addr     (bin_addr),
        .speed_code   (speed_code),
        .buffer_full  (buffer_full),
        .framing_error(framing_error),
        .fft_done     (fft_done),
        .bin_re       (bin_re),
        .bin_im       (bin_im)
    );

    //==========================================================
    // Spectrum Transmitter
    //==========================================================
    wire [7:0] tx_data;
    wire       tx_send;
    wire       tx_busy;

    spectrum_sender #(
        .N_BINS(128)
    ) u_sender (
        .clk     (clk),
        .reset   (reset),
        .start   (fft_done),
        .bin_addr(snd_addr),
        .bin_re  (bin_re),
        .bin_im  (bin_im),
        .tx_data (tx_data),
        .tx_send (tx_send),
        .tx_busy (tx_busy),
        .active  (snd_active)
    );

    uart_tx #(
        .clk_freq (100_000_000),
        .baud_rate(300000)
    ) u_tx (
        .clk    (clk),
        .reset  (reset),
        .data_in(tx_data),
        .send   (tx_send),
        .tx     (UART_txd),
        .busy   (tx_busy)
    );

    //==========================================================
    // Sticky Status Flags
    //==========================================================
    reg full_sticky;
    reg done_sticky;
    reg ferr_sticky;
    reg coll_sticky;

    always @(posedge clk) begin
        if (reset) begin
            full_sticky <= 1'b0;
            done_sticky <= 1'b0;
            ferr_sticky <= 1'b0;
            coll_sticky <= 1'b0;
        end
        else begin
            if (buffer_full)   full_sticky <= 1'b1;
            if (fft_done)      done_sticky <= 1'b1;
            if (framing_error) ferr_sticky <= 1'b1;
            if (snd_active && (buffer_full || fft_done))
                coll_sticky <= 1'b1;
        end
    end

    //==========================================================
    // Magnitude Estimate for LEDs: |Re| + |Im|
    //==========================================================
    wire [31:0] abs_re  = bin_re[31] ? (~bin_re + 32'd1) : bin_re;
    wire [31:0] abs_im  = bin_im[31] ? (~bin_im + 32'd1) : bin_im;
    wire [31:0] mag_sum = abs_re + abs_im;

    // Bit-slice [14:7] matches ~7000 peak (binary 0001_1011_0101_1000)
    // Latch value when sender is idle so LEDs don't blank out during UART transfer
    reg [7:0] mag_led_reg;
    always @(posedge clk) begin
        if (reset)
            mag_led_reg <= 8'h00;
        else if (!snd_active)
            mag_led_reg <= mag_sum[14:7];
    end

    //==========================================================
    // Seven-Segment Display (Selected bin in HEX)
    //==========================================================
    wire [7:0] bin_num = sw[7:0];

    function [7:0] hex_to_seg;
        input [3:0] h;
        begin
            case (h)
                4'h0: hex_to_seg = 8'hC0;
                4'h1: hex_to_seg = 8'hF9;
                4'h2: hex_to_seg = 8'hA4;
                4'h3: hex_to_seg = 8'hB0;
                4'h4: hex_to_seg = 8'h99;
                4'h5: hex_to_seg = 8'h92;
                4'h6: hex_to_seg = 8'h82;
                4'h7: hex_to_seg = 8'hF8;
                4'h8: hex_to_seg = 8'h80;
                4'h9: hex_to_seg = 8'h90;
                4'hA: hex_to_seg = 8'h88;
                4'hB: hex_to_seg = 8'h83;
                4'hC: hex_to_seg = 8'hC6;
                4'hD: hex_to_seg = 8'hA1;
                4'hE: hex_to_seg = 8'h86;
                default: hex_to_seg = 8'h8E;
            endcase
        end
    endfunction

    assign D0_AN  = 4'b1110;
    assign D1_AN  = 4'b1110;
    assign D0_SEG = hex_to_seg(bin_num[7:4]);
    assign D1_SEG = hex_to_seg(bin_num[3:0]);

    //==========================================================
    // LED Output Mapping
    //==========================================================
    assign led[15]   = full_sticky;
    assign led[14]   = done_sticky;
    assign led[13]   = ferr_sticky;
    assign led[12]   = snd_active;
    assign led[11]   = coll_sticky;
    assign led[10:8] = 3'b000;
    assign led[7:0]  = mag_led_reg;

    // RGB LEDs off
    assign RGB0 = 3'b000;
    assign RGB1 = 3'b000;

endmodule