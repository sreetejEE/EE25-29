`timescale 1ns / 1ps

module uart_fft_top #(
    parameter integer CLK_FREQ   = 100_000_000,
    parameter integer BAUD_RATE  = 2_000_000,
    parameter integer NUM_BLOCKS = 117
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        uart_rxd,
    output wire        uart_txd,
    output reg  [15:0] led,
    output reg  [3:0]  D0_AN,
    output reg  [7:0]  D0_SEG
);
    //******Written by Dhanush************************
    //******from line 276 Written by Vishwambhar************************
    // ------------------------------------------------
    // Internal Interconnects
    // ------------------------------------------------
    wire [7:0]         uart_data;
    wire               uart_data_valid;
    wire               framing_error;

    // Mutual-exclusion gating between Sample Parser (0xAA 0x55) and Calib Loader (0xAA 0x66)
    wire               parser_busy;
    wire               calib_busy;
    wire               calib_done;
    wire               parser_data_valid = uart_data_valid & ~calib_busy;
    wire               calib_data_valid  = uart_data_valid & ~parser_busy;

    // Live Calibration Write Ports
    wire               cfg_feat_we;
    wire [8:0]         cfg_feat_addr;
    wire [79:0]        cfg_feat_wdata;
    wire               cfg_thresh_we;
    wire [3:0]         cfg_thresh_addr;
    wire [39:0]        cfg_thresh_wdata;

    // Parser <-> Hann Window
    wire [7:0]         speed_code;
    wire               parser_buffer_full;
    wire               parser_release;
    wire               overrun;
    wire [9:0]         parser_addr;
    wire signed [15:0] parser_x;
    wire signed [15:0] parser_y;
    wire signed [15:0] parser_z;

    // Hann Window <-> FFT Controller
    wire               win_buffer_full;
    wire               win_buffer_release;
    wire [9:0]         fft_addr;
    wire signed [15:0] win_x;
    wire signed [15:0] win_y;
    wire signed [15:0] win_z;

    // FFT Controller <-> Gaussian Classifier
    wire               fft_done;
    wire [11:0]        bin_addr;
    wire signed [31:0] bin_re;
    wire signed [31:0] bin_im;

    wire [6:0]         block_count;
    wire [2:0]         ch1_pred;
    wire [2:0]         ch2_pred;
    wire [2:0]         ch3_pred;
    wire [2:0]         fault_class;
    wire               class_valid;

    // Classifier Debug Readout
    reg  [4:0]         dbg_idx;
    wire [9:0]         dbg_med_freq;
    wire [15:0]        dbg_med_mag;
    wire [1:0]         dbg_speed_idx;
    wire [19:0]        dbg_ch1_s0;
    wire [19:0]        dbg_ch1_s1;
    wire [19:0]        dbg_ch1_s2;
    wire [19:0]        dbg_ch1_s3;
    wire [19:0]        dbg_ch1_s4;
    wire [19:0]        dbg_ch1_min_s;

    // ------------------------------------------------
    // 1. UART Receiver
    // ------------------------------------------------
    uart_rx #(
        .clk_freq(CLK_FREQ),
        .baud_rate(BAUD_RATE)
    ) uart_rx_inst (
        .clk(clk),
        .reset(reset),
        .uart_rxd(uart_rxd),
        .data_out(uart_data),
        .data_valid(uart_data_valid),
        .framing_error(framing_error)
    );

    // ------------------------------------------------
    // 2A. Live Calibration Loader (0xAA 0x66)
    // ------------------------------------------------
    uart_calib_loader calib_loader_inst (
        .clk              (clk),
        .reset            (reset),
        .data_in          (uart_data),
        .data_valid       (calib_data_valid),
        .calib_busy       (calib_busy),
        .calib_done       (calib_done),
        .cfg_feat_we      (cfg_feat_we),
        .cfg_feat_addr    (cfg_feat_addr),
        .cfg_feat_wdata   (cfg_feat_wdata),
        .cfg_thresh_we    (cfg_thresh_we),
        .cfg_thresh_addr  (cfg_thresh_addr),
        .cfg_thresh_wdata (cfg_thresh_wdata)
    );

    // ------------------------------------------------
    // 2B. XYZ Packet Parser & Sample Buffer (0xAA 0x55)
    // ------------------------------------------------
    xyz_packet_parser parser_inst (
        .clk(clk),
        .reset(reset),
        .data_in(uart_data),
        .data_valid(parser_data_valid),
        .buffer_release(parser_release),
        .speed_code(speed_code),
        .buffer_full(parser_buffer_full),
        .overrun(overrun),
        .parser_busy(parser_busy),

        .fft_read_addr_x(parser_addr),
        .fft_read_addr_y(parser_addr),
        .fft_read_addr_z(parser_addr),

        .fft_read_x(parser_x),
        .fft_read_y(parser_y),
        .fft_read_z(parser_z)
    );

    // ------------------------------------------------
    // 3. Hann Windowing Stage
    // ------------------------------------------------
    hann_window_xyz #(
        .BUFFER_SIZE(1024),
        .COEFF_FILE("hann_1024_q15.mem")
    ) hann_inst (
        .clk(clk),
        .reset(reset),

        .parser_buffer_full(parser_buffer_full),
        .parser_buffer_release(parser_release),
        .parser_read_addr(parser_addr),
        .parser_read_x(parser_x),
        .parser_read_y(parser_y),
        .parser_read_z(parser_z),

        .win_buffer_full(win_buffer_full),
        .win_buffer_release(win_buffer_release),
        .fft_read_addr_x(fft_addr),
        .fft_read_addr_y(fft_addr),
        .fft_read_addr_z(fft_addr),
        .fft_read_x(win_x),
        .fft_read_y(win_y),
        .fft_read_z(win_z)
    );

    // ------------------------------------------------
    // 4. FFT Controller (Sequential X -> Y -> Z execution)
    // ------------------------------------------------
    fft_controller fft_controller_inst (
        .clk(clk),
        .reset(reset),
        .buffer_full(win_buffer_full),
        .buffer_release(win_buffer_release),
        .parser_addr(fft_addr),
        .parser_x(win_x),
        .parser_y(win_y),
        .parser_z(win_z),
        .bin_addr(bin_addr),
        .bin_re(bin_re),
        .bin_im(bin_im),
        .fft_done(fft_done)
    );

    // ------------------------------------------------
    // 5. Latch Speed Code & Run Gaussian Classifier
    // ------------------------------------------------
    reg [7:0] active_speed_code;
    always @(posedge clk) begin
        if (reset)
            active_speed_code <= 8'd50;
        else if (parser_release)
            active_speed_code <= speed_code;
    end

    vibration_gaussian_classifier #(
        .NUM_BLOCKS      (NUM_BLOCKS),
        .FEAT_MEM_FILE   ("gauss_features.mem"),
        .THRESH_MEM_FILE ("decision_thresh.mem"),
        .EXP_LUT_FILE    ("exp_lut.mem")
    ) classifier_inst (
        .clk              (clk),
        .reset            (reset),
        .speed_code       (active_speed_code),
        .fft_done         (fft_done),
        .bin_addr         (bin_addr),
        .bin_re           (bin_re),
        .bin_im           (bin_im),
        .block_count      (block_count),
        .ch1_pred         (ch1_pred),
        .ch2_pred         (ch2_pred),
        .ch3_pred         (ch3_pred),
        .fault_class      (fault_class),
        .class_valid      (class_valid),
        .dbg_idx          (dbg_idx),
        .dbg_med_freq     (dbg_med_freq),
        .dbg_med_mag      (dbg_med_mag),
        .dbg_speed_idx    (dbg_speed_idx),
        .dbg_ch1_s0       (dbg_ch1_s0),
        .dbg_ch1_s1       (dbg_ch1_s1),
        .dbg_ch1_s2       (dbg_ch1_s2),
        .dbg_ch1_s3       (dbg_ch1_s3),
        .dbg_ch1_s4       (dbg_ch1_s4),
        .dbg_ch1_min_s    (dbg_ch1_min_s),
        .cfg_feat_we      (cfg_feat_we),
        .cfg_feat_addr    (cfg_feat_addr),
        .cfg_feat_wdata   (cfg_feat_wdata),
        .cfg_thresh_we    (cfg_thresh_we),
        .cfg_thresh_addr  (cfg_thresh_addr),
        .cfg_thresh_wdata (cfg_thresh_wdata)
    );

    // ------------------------------------------------
    // 6. Live Debug + Fault LED Display Driver
    // ------------------------------------------------
    reg [25:0] hb_cnt;
    reg        parser_prev;

    always @(posedge clk) begin
        if (reset) begin
            led         <= 16'h0000;
            hb_cnt      <= 26'd0;
            parser_prev <= 1'b0;
        end else begin
            hb_cnt  <= hb_cnt + 26'd1;
            led[15] <= hb_cnt[25];

            if (uart_data_valid)
                led[14] <= ~led[14];

            parser_prev <= parser_buffer_full;
            if (parser_buffer_full && !parser_prev)
                led[13] <= ~led[13];

            led[12:8] <= block_count[4:0];

            if (framing_error || overrun)
                led[7] <= 1'b1;

            if (class_valid) begin
                led[6] <= 1'b1;
                case (fault_class)
                    3'd0:    led[5:0] <= 6'b000001; // HEALTHY
                    3'd1:    led[5:0] <= 6'b000010; // BPFO
                    3'd2:    led[5:0] <= 6'b000100; // BPFI
                    3'd3:    led[5:0] <= 6'b001000; // STATOR_SHORT
                    3'd4:    led[5:0] <= 6'b010000; // BROKEN_ROTOR_BAR
                    default: led[5:0] <= 6'b100000; // UNKNOWN
                endcase
            end
        end
    end
    
    //**********Written by vishwambhar****************
    // ------------------------------------------------
    // 7. Debug UART Reporter (Sends 2-byte ACK or 145-byte Result)
    // ------------------------------------------------
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;

    uart_tx #(
        .clk_freq(CLK_FREQ),
        .baud_rate(BAUD_RATE)
    ) uart_tx_inst (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .uart_txd(uart_txd),
        .tx_busy(tx_busy)
    );

    reg [1:0] rpt_state;
    reg [7:0] rpt_byte_idx; // 0..144
    reg       rpt_is_ack;

    always @(posedge clk) begin
        if (reset) begin
            rpt_state    <= 2'd0;
            rpt_byte_idx <= 8'd0;
            rpt_is_ack   <= 1'b0;
            dbg_idx      <= 5'd0;
            tx_start     <= 1'b0;
            tx_data      <= 8'd0;
        end else begin
            tx_start <= 1'b0;

            case (rpt_state)
                2'd0: begin
                    if (calib_done) begin
                        rpt_is_ack   <= 1'b1;
                        rpt_byte_idx <= 8'd0;
                        rpt_state    <= 2'd1;
                    end else if (class_valid) begin
                        rpt_is_ack   <= 1'b0;
                        rpt_byte_idx <= 8'd0;
                        dbg_idx      <= 5'd0;
                        rpt_state    <= 2'd1;
                    end
                end

                2'd1: begin
                    if (rpt_is_ack) begin
                        tx_data <= (rpt_byte_idx == 8'd0) ? 8'hCC : 8'h77;
                    end else begin
                        case (rpt_byte_idx)
                            8'd0:   tx_data <= 8'hBB;
                            8'd1:   tx_data <= 8'h66;
                            8'd2:   tx_data <= {5'd0, ch1_pred};
                            8'd3:   tx_data <= {5'd0, ch2_pred};
                            8'd4:   tx_data <= {5'd0, ch3_pred};
                            8'd5:   tx_data <= {5'd0, fault_class};
                            8'd126: tx_data <= {6'd0, dbg_speed_idx};
                            8'd127: tx_data <= {4'd0, dbg_ch1_s0[19:16]};
                            8'd128: tx_data <= dbg_ch1_s0[15:8];
                            8'd129: tx_data <= dbg_ch1_s0[7:0];
                            8'd130: tx_data <= {4'd0, dbg_ch1_s1[19:16]};
                            8'd131: tx_data <= dbg_ch1_s1[15:8];
                            8'd132: tx_data <= dbg_ch1_s1[7:0];
                            8'd133: tx_data <= {4'd0, dbg_ch1_s2[19:16]};
                            8'd134: tx_data <= dbg_ch1_s2[15:8];
                            8'd135: tx_data <= dbg_ch1_s2[7:0];
                            8'd136: tx_data <= {4'd0, dbg_ch1_s3[19:16]};
                            8'd137: tx_data <= dbg_ch1_s3[15:8];
                            8'd138: tx_data <= dbg_ch1_s3[7:0];
                            8'd139: tx_data <= {4'd0, dbg_ch1_s4[19:16]};
                            8'd140: tx_data <= dbg_ch1_s4[15:8];
                            8'd141: tx_data <= dbg_ch1_s4[7:0];
                            8'd142: tx_data <= {4'd0, dbg_ch1_min_s[19:16]};
                            8'd143: tx_data <= dbg_ch1_min_s[15:8];
                            8'd144: tx_data <= dbg_ch1_min_s[7:0];
                            default: begin
                                // Bytes 6..125: 30 bands x 4 bytes
                                case ((rpt_byte_idx - 8'd6) & 8'd3)
                                    8'd0: tx_data <= {6'd0, dbg_med_freq[9:8]};
                                    8'd1: tx_data <= dbg_med_freq[7:0];
                                    8'd2: tx_data <= dbg_med_mag[15:8];
                                    8'd3: tx_data <= dbg_med_mag[7:0];
                                endcase
                            end
                        endcase
                    end
                    tx_start  <= 1'b1;
                    rpt_state <= 2'd2;
                end

                2'd2: begin
                    rpt_state <= 2'd3;
                end

                2'd3: begin
                    if (!tx_busy) begin
                        if ((rpt_is_ack && rpt_byte_idx == 8'd1) || (!rpt_is_ack && rpt_byte_idx == 8'd144)) begin
                            rpt_state <= 2'd0;
                        end else begin
                            rpt_byte_idx <= rpt_byte_idx + 8'd1;
                            if (!rpt_is_ack && rpt_byte_idx >= 8'd6 && rpt_byte_idx <= 8'd125 && (((rpt_byte_idx - 8'd6) & 8'd3) == 8'd3))
                                dbg_idx <= dbg_idx + 5'd1;
                            rpt_state <= 2'd1;
                        end
                    end
                end
            endcase
        end
    end

    // ------------------------------------------------
    // 8. 7-Segment Display Driver (D0: 4-Digit Multiplexed, Active-Low)
    // ------------------------------------------------
    localparam [7:0] SEG_A     = 8'h88,
                     SEG_B     = 8'h83,
                     SEG_E     = 8'h86,
                     SEG_F     = 8'h8E,
                     SEG_H     = 8'h89,
                     SEG_I     = 8'hF9,
                     SEG_L     = 8'hC7,
                     SEG_N     = 8'hAB,
                     SEG_O     = 8'hC0,
                     SEG_P     = 8'h8C,
                     SEG_R     = 8'hAF,
                     SEG_S     = 8'h92,
                     SEG_T     = 8'h87,
                     SEG_DASH  = 8'hBF,
                     SEG_BLANK = 8'hFF;

    reg [18:0] seg_cnt;
    wire [1:0] digit_sel = seg_cnt[18:17];

    reg [7:0] seg_d3, seg_d2, seg_d1, seg_d0;

    always @(*) begin
        if (!led[6]) begin
            seg_d3 = SEG_DASH; seg_d2 = SEG_DASH; seg_d1 = SEG_DASH; seg_d0 = SEG_DASH;
        end else begin
            case (fault_class)
                3'd0: begin // HEAL
                    seg_d3 = SEG_H; seg_d2 = SEG_E; seg_d1 = SEG_A; seg_d0 = SEG_L;
                end
                3'd1: begin // bPFO
                    seg_d3 = SEG_B; seg_d2 = SEG_P; seg_d1 = SEG_F; seg_d0 = SEG_O;
                end
                3'd2: begin // bPFI
                    seg_d3 = SEG_B; seg_d2 = SEG_P; seg_d1 = SEG_F; seg_d0 = SEG_I;
                end
                3'd3: begin // StAt
                    seg_d3 = SEG_S; seg_d2 = SEG_T; seg_d1 = SEG_A; seg_d0 = SEG_T;
                end
                3'd4: begin // brb
                    seg_d3 = SEG_B; seg_d2 = SEG_R; seg_d1 = SEG_B; seg_d0 = SEG_BLANK;
                end
                default: begin // nOnE (UNKNOWN)
                    seg_d3 = SEG_N; seg_d2 = SEG_O; seg_d1 = SEG_N; seg_d0 = SEG_E;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            seg_cnt <= 19'd0;
            D0_AN   <= 4'b1111;
            D0_SEG  <= SEG_BLANK;
        end else begin
            seg_cnt <= seg_cnt + 19'd1;
            case (digit_sel)
                2'd0: begin D0_AN <= 4'b1110; D0_SEG <= seg_d0; end
                2'd1: begin D0_AN <= 4'b1101; D0_SEG <= seg_d1; end
                2'd2: begin D0_AN <= 4'b1011; D0_SEG <= seg_d2; end
                2'd3: begin D0_AN <= 4'b0111; D0_SEG <= seg_d3; end
            endcase
        end
    end

endmodule