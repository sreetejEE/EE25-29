`timescale 1ns / 1ps

// spectrum_sender
//
// After `start` (the fft_done pulse) streams the FFT spectrum to uart_tx.
//
// Frame (1539 bytes):
//   0xBB 0x66                              header
//   for axis = X, Y, Z:                    (3 x 128 bins)
//     for bin = 0..127:
//       re[15:8] re[7:0] im[15:8] im[7:0]  big-endian signed int16
//   checksum                               8-bit sum of the 1536 payload bytes
//
// Only bins 0..127 are sent: for real input, bins 128..255 mirror them.
// bin_addr = {axis[1:0], bin[7:0]}, the same convention as uart_fft_top.

module spectrum_sender #(
    parameter integer N_BINS = 128
)(
    input  wire               clk,
    input  wire               reset,
    input  wire               start,

    // spectrum read port
    output reg  [9:0]         bin_addr,
    input  wire signed [31:0] bin_re,
    input  wire signed [31:0] bin_im,

    // uart_tx interface
    output reg  [7:0]         tx_data,
    output reg                tx_send,
    input  wire               tx_busy,

    output reg                active
);

    localparam [3:0] S_IDLE  = 4'd0;
    localparam [3:0] S_HDR1  = 4'd1;
    localparam [3:0] S_ADDR  = 4'd2;
    localparam [3:0] S_LATCH = 4'd3;
    localparam [3:0] S_PAY   = 4'd4;
    localparam [3:0] S_NEXT  = 4'd5;
    localparam [3:0] S_CSUM  = 4'd6;
    localparam [3:0] S_SEND  = 4'd7;
    localparam [3:0] S_WBUSY = 4'd8;
    localparam [3:0] S_WDONE = 4'd9;

    reg [3:0]  state;
    reg [3:0]  ret_state;
    reg [7:0]  byte_reg;
    reg [7:0]  csum;
    reg [1:0]  axis;
    reg [7:0]  bin;
    reg [1:0]  bidx;
    reg [15:0] re_r;
    reg [15:0] im_r;

    reg [7:0] cur_byte;
    always @(*) begin
        case (bidx)
            2'd0:    cur_byte = re_r[15:8];
            2'd1:    cur_byte = re_r[7:0];
            2'd2:    cur_byte = im_r[15:8];
            default: cur_byte = im_r[7:0];
        endcase
    end

    always @(posedge clk) begin
        tx_send <= 1'b0;                       // default: pulse is one clock

        if (reset) begin
            state     <= S_IDLE;
            ret_state <= S_IDLE;
            byte_reg  <= 8'd0;
            csum      <= 8'd0;
            axis      <= 2'd0;
            bin       <= 8'd0;
            bidx      <= 2'd0;
            re_r      <= 16'd0;
            im_r      <= 16'd0;
            bin_addr  <= 10'd0;
            tx_data   <= 8'd0;
            active    <= 1'b0;
        end
        else begin
            case (state)

                S_IDLE: begin
                    active <= 1'b0;
                    if (start) begin
                        active    <= 1'b1;
                        axis      <= 2'd0;
                        bin       <= 8'd0;
                        csum      <= 8'd0;
                        byte_reg  <= 8'hBB;
                        ret_state <= S_HDR1;
                        state     <= S_SEND;
                    end
                end

                S_HDR1: begin
                    byte_reg  <= 8'h66;
                    ret_state <= S_ADDR;
                    state     <= S_SEND;
                end

                // present the address; memory output settles during S_LATCH
                S_ADDR: begin
                    bin_addr <= {axis, bin};
                    state    <= S_LATCH;
                end

                S_LATCH: begin
                    re_r  <= bin_re[15:0];
                    im_r  <= bin_im[15:0];
                    bidx  <= 2'd0;
                    state <= S_PAY;
                end

                // four payload bytes per bin
                S_PAY: begin
                    byte_reg  <= cur_byte;
                    csum      <= csum + cur_byte;
                    bidx      <= bidx + 1'b1;
                    ret_state <= (bidx == 2'd3) ? S_NEXT : S_PAY;
                    state     <= S_SEND;
                end

                S_NEXT: begin
                    if (bin == N_BINS - 1) begin
                        bin <= 8'd0;
                        if (axis == 2'd2)
                            state <= S_CSUM;
                        else begin
                            axis  <= axis + 1'b1;
                            state <= S_ADDR;
                        end
                    end
                    else begin
                        bin   <= bin + 1'b1;
                        state <= S_ADDR;
                    end
                end

                S_CSUM: begin
                    byte_reg  <= csum;
                    ret_state <= S_IDLE;
                    state     <= S_SEND;
                end

                // ---- send one byte and wait for it to finish ----
                S_SEND: begin
                    if (!tx_busy) begin
                        tx_data <= byte_reg;
                        tx_send <= 1'b1;
                        state   <= S_WBUSY;
                    end
                end

                S_WBUSY: begin
                    if (tx_busy)
                        state <= S_WDONE;
                end

                S_WDONE: begin
                    if (!tx_busy)
                        state <= ret_state;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule