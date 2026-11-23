`timescale 1ns / 1ps
//******Written by Vishwambhar************************
module vibration_gaussian_classifier #(
    parameter integer NUM_BLOCKS      = 117,
    parameter         FEAT_MEM_FILE   = "gauss_features.mem",
    parameter         THRESH_MEM_FILE = "decision_thresh.mem",
    parameter         EXP_LUT_FILE    = "exp_lut.mem"
)(
    input  wire        clk,
    input  wire        reset,
    // Debug readout for median features (idx 0..29 = ch*10 + band)
        input  wire [4:0]  dbg_idx,
        output wire [9:0]  dbg_med_freq,
        output wire [15:0] dbg_med_mag,
    output reg  [1:0]  dbg_speed_idx,
            output reg  [19:0] dbg_ch1_s0,
            output reg  [19:0] dbg_ch1_s1,
            output reg  [19:0] dbg_ch1_s2,
            output reg  [19:0] dbg_ch1_s3,
            output reg  [19:0] dbg_ch1_s4,
            output reg  [19:0] dbg_ch1_min_s,
            input  wire        cfg_feat_we,
            input  wire [8:0]  cfg_feat_addr,
            input  wire [79:0] cfg_feat_wdata,
            input  wire        cfg_thresh_we,
            input  wire [3:0]  cfg_thresh_addr,
            input  wire [39:0] cfg_thresh_wdata,
    // Speed code from packet parser (50, 75, 100 or 0, 1, 2)
    input  wire [7:0]  speed_code,

    // Interface to fft_controller
    input  wire        fft_done,
    output wire [11:0] bin_addr,       // [11:10]=axis (0=X,1=Y,2=Z), [9:0]=bin
    input  wire signed [31:0] bin_re,  // 1-cycle synchronous BRAM latency
    input  wire signed [31:0] bin_im,

    // Status & outputs
    output reg  [6:0]  block_count,    // Current accumulated block (0..117)
    output reg  [2:0]  ch1_pred,
    output reg  [2:0]  ch2_pred,
    output reg  [2:0]  ch3_pred,

    // 0:HEALTHY, 1:BPFO, 2:BPFI, 3:STATOR_SHORT, 4:BROKEN_ROTOR_BAR, 5:UNKNOWN
    output reg  [2:0]  fault_class,
    output reg         class_valid
);

    localparam integer MEDIAN_IDX = (NUM_BLOCKS - 1) / 2;

    localparam [2:0] CLS_HEALTHY          = 3'd0,
                     CLS_BPFO             = 3'd1,
                     CLS_BPFI             = 3'd2,
                     CLS_STATOR_SHORT     = 3'd3,
                     CLS_BROKEN_ROTOR_BAR = 3'd4,
                     CLS_UNKNOWN          = 3'd5;

    // ------------------------------------------------------------
    // 1. Calibration & Exp LUT ROMs
    // ------------------------------------------------------------
    // 3 speeds x 3 channels x 5 classes x 10 bands = 450 entries (80-bit each)
    // [79:64] freq_median    (Q10.6 bins)
    // [63:40] freq_inv_sigma (2^20 / (sigma_bins * 64), matches Q10.6 diff -> Q20 product)
    // [39:24] mag_median     (Q16.0)
    // [23:0]  mag_inv_sigma  (Q4.20 = 2^20 / sigma_mag)
    (* ram_style = "block" *) reg [79:0] feat_rom [0:449];
        initial $readmemh(FEAT_MEM_FILE, feat_rom);
    
        reg [8:0]  feat_rom_addr;
        reg [79:0] feat_rom_data;
        always @(posedge clk) begin
            if (cfg_feat_we) feat_rom[cfg_feat_addr] <= cfg_feat_wdata;
            feat_rom_data <= feat_rom[feat_rom_addr];
        end
    
        // 3 speeds x 3 channels = 9 entries (40-bit each)
        // [39:20] min_score (Q4.16), [19:0] min_margin (Q4.16)
        (* ram_style = "distributed" *) reg [39:0] thresh_rom [0:8];
        initial $readmemh(THRESH_MEM_FILE, thresh_rom);
    
        reg [3:0]  thresh_rom_addr;
        reg [39:0] thresh_rom_data;
        always @(posedge clk) begin
            if (cfg_thresh_we) thresh_rom[cfg_thresh_addr] <= cfg_thresh_wdata;
            thresh_rom_data <= thresh_rom[thresh_rom_addr];
        end

    // 512-entry exp(-u) LUT for u in [0, 8), Q0.16 output
    (* rom_style = "block" *) reg [15:0] exp_lut [0:511];
    initial $readmemh(EXP_LUT_FILE, exp_lut);

    reg [8:0]  exp_lut_addr;
    reg [15:0] exp_lut_data;
    always @(posedge clk) exp_lut_data <= exp_lut[exp_lut_addr];

    // ------------------------------------------------------------
    // 2. Block Feature BRAMs (3 channels x 10 bands x 117 blocks = 3510)
    // ------------------------------------------------------------
    (* ram_style = "block" *) reg [9:0]  blk_freq_mem [0:3509];
    (* ram_style = "block" *) reg [15:0] blk_mag_mem  [0:3509];

    reg        blk_freq_we;
    reg        blk_mag_we;
    reg [11:0] blk_addr;
    reg [9:0]  blk_freq_wdata;
    reg [15:0] blk_mag_wdata;
    reg [9:0]  blk_freq_rdata;
    reg [15:0] blk_mag_rdata;

    always @(posedge clk) begin
        if (blk_freq_we) blk_freq_mem[blk_addr] <= blk_freq_wdata;
        if (blk_mag_we)  blk_mag_mem[blk_addr]  <= blk_mag_wdata;
        blk_freq_rdata <= blk_freq_mem[blk_addr];
        blk_mag_rdata  <= blk_mag_mem[blk_addr];
    end

    // Computed median features (30 bands total across 3 channels)
    reg [9:0]  med_freq [0:29];
    reg [15:0] med_mag  [0:29];
    assign dbg_med_freq = med_freq[dbg_idx];
        assign dbg_med_mag  = med_mag[dbg_idx];

    // ------------------------------------------------------------
    // 3. Lookup Functions
    // ------------------------------------------------------------
    function [1:0] map_speed(input [7:0] code);
        case (code)
            8'd50,  8'd0: map_speed = 2'd0;
            8'd75,  8'd1: map_speed = 2'd1;
            8'd100, 8'd2: map_speed = 2'd2;
            default:      map_speed = 2'd0;
        endcase
    endfunction

    function [9:0] get_band_start(input [3:0] b);
        case (b)
            4'd0: get_band_start = 10'd0;
            4'd1: get_band_start = 10'd52;
            4'd2: get_band_start = 10'd103;
            4'd3: get_band_start = 10'd154;
            4'd4: get_band_start = 10'd205;
            4'd5: get_band_start = 10'd256;
            4'd6: get_band_start = 10'd308;
            4'd7: get_band_start = 10'd359;
            4'd8: get_band_start = 10'd410;
            4'd9: get_band_start = 10'd461;
            default: get_band_start = 10'd0;
        endcase
    endfunction

    function [9:0] get_band_end(input [3:0] b);
        case (b)
            4'd0: get_band_end = 10'd51;
            4'd1: get_band_end = 10'd102;
            4'd2: get_band_end = 10'd153;
            4'd3: get_band_end = 10'd204;
            4'd4: get_band_end = 10'd255;
            4'd5: get_band_end = 10'd307;
            4'd6: get_band_end = 10'd358;
            4'd7: get_band_end = 10'd409;
            4'd8: get_band_end = 10'd460;
            4'd9: get_band_end = 10'd511; // Matches freqs < 5000 Hz
            default: get_band_end = 10'd51;
        endcase
    endfunction

    // ------------------------------------------------------------
    // 4. FSM & Datapath
    // ------------------------------------------------------------
    localparam [4:0] S_IDLE             = 5'd0,
                     S_BAND_INIT        = 5'd1,
                     S_SCAN_ISSUE       = 5'd2,
                     S_SCAN_LAST        = 5'd3,
                     S_SQRT_INIT        = 5'd4,
                     S_SQRT_STEP        = 5'd5,
                     S_BLK_STORE        = 5'd6,
                     // Median sorting states
                     S_SORT_INIT        = 5'd7,
                     S_SORT_READ_I      = 5'd8,
                     S_SORT_WAIT_I      = 5'd9,
                     S_SORT_READ_J      = 5'd10,
                     S_SORT_WAIT_J      = 5'd11,
                     S_SORT_SWAP_A      = 5'd12,
                     S_SORT_SWAP_B      = 5'd13,
                     // Gaussian scoring states
                     S_GAUSS_LOAD       = 5'd14,
                     S_GAUSS_WAIT_ROM   = 5'd15,
                     S_GAUSS_DIFF       = 5'd16,
                     S_GAUSS_MUL_Z      = 5'd17,
                     S_GAUSS_SQ_U       = 5'd18,
                     S_GAUSS_LUT_WAIT   = 5'd19,
                     S_GAUSS_ACCUM      = 5'd20,
                     S_CH_DECIDE        = 5'd21,
                     S_VOTE             = 5'd22,
                     S_SORT_WAIT_J_BRAM = 5'd23;

    reg [4:0] state;
    reg [1:0] speed_idx;
    reg [1:0] ch;
    reg [3:0] band;
    reg [2:0] cls;
    reg       sort_is_mag; // 0 = sorting freq, 1 = sorting mag

    reg [9:0] bin_idx, bin_idx_d1;
    reg       scan_valid_d1;
    assign bin_addr = {ch, bin_idx};

    reg [31:0] max_mag_sq;
    reg [9:0]  peak_bin;

    // Signed squaring to prevent Verilog unsigned LHS coercion
    wire signed [15:0] re16       = bin_re[15:0];
    wire signed [15:0] im16       = bin_im[15:0];
    wire signed [31:0] re_sq_s    = re16 * re16;
    wire signed [31:0] im_sq_s    = im16 * im16;
    wire [31:0]        cur_mag_sq = $unsigned(re_sq_s) + $unsigned(im_sq_s);

    // 16-cycle integer sqrt registers
    reg [31:0] sqrt_rad;
    reg [17:0] sqrt_rem;
    reg [15:0] sqrt_root;
    reg [4:0]  sqrt_cnt;

    // Sort registers
    reg [11:0] sort_base;
    reg [6:0]  sort_i, sort_j, sort_min_idx;
    reg [15:0] sort_i_val, sort_min_val;

    // Gaussian math registers & signed squaring wires
    reg        gauss_is_mag; // 0 = freq, 1 = mag
    reg signed [16:0] g_diff;
    reg [23:0]        g_inv_sig;
    reg signed [40:0] g_z_q20;
    reg               g_exact_zero;
    reg               g_zero_sig;
    reg               g_overflow;
    reg [15:0]        freq_score_q16;

    wire signed [28:0] z_q8_full  = g_z_q20 >>> 12;
    wire signed [11:0] z_q8_s     = z_q8_full[11:0];
    wire signed [23:0] z_sq_q16_s = z_q8_s * z_q8_s;

    // Class scores in Q4.16 (0 to 10.0)
    reg [19:0] class_score [0:4];
    reg [2:0]  ch_pred [0:2];

    reg [2:0]  best_cls;
    reg [19:0] best_scr, second_scr;
    integer k;
    always @(*) begin
        best_cls   = 3'd0;
        best_scr   = 20'd0;
        second_scr = 20'd0;
        for (k = 0; k < 5; k = k + 1) begin
            if (class_score[k] > best_scr) begin
                second_scr = best_scr;
                best_scr   = class_score[k];
                best_cls   = k[2:0];
            end else if (class_score[k] > second_scr) begin
                second_scr = class_score[k];
            end
        end
    end

    wire [15:0] cur_med_freq_q10_6 = feat_rom_data[79:64];
    wire [23:0] cur_inv_sig_freq   = feat_rom_data[63:40];
    wire [15:0] cur_med_mag        = feat_rom_data[39:24];
    wire [23:0] cur_inv_sig_mag    = feat_rom_data[23:0];

    wire [19:0] cur_min_score  = thresh_rom_data[39:20];
    wire [19:0] cur_min_margin = thresh_rom_data[19:0];

    wire [15:0] cur_feat_val = gauss_is_mag ? med_mag[ch*10 + band] : {med_freq[ch*10 + band], 6'd0};
    wire [15:0] cur_feat_med = gauss_is_mag ? cur_med_mag           : cur_med_freq_q10_6;
    wire [23:0] cur_feat_inv = gauss_is_mag ? cur_inv_sig_mag       : cur_inv_sig_freq;

    always @(posedge clk) begin
        if (reset) begin
            state         <= S_IDLE;
            block_count   <= 7'd0;
            speed_idx     <= 2'd0;
            ch            <= 2'd0;
            band          <= 4'd0;
            cls           <= 3'd0;
            bin_idx       <= 10'd0;
            bin_idx_d1    <= 10'd0;
            scan_valid_d1 <= 1'b0;
            max_mag_sq    <= 32'd0;
            peak_bin      <= 10'd0;
            blk_freq_we   <= 1'b0;
            blk_mag_we    <= 1'b0;
            blk_addr      <= 12'd0;
            fault_class   <= CLS_UNKNOWN;
            class_valid   <= 1'b0;
            ch1_pred      <= CLS_UNKNOWN;
            ch2_pred      <= CLS_UNKNOWN;
            ch3_pred      <= CLS_UNKNOWN;
            for (k = 0; k < 5; k = k + 1) class_score[k] <= 20'd0;
            for (k = 0; k < 3; k = k + 1) ch_pred[k]     <= CLS_UNKNOWN;
        end else begin
            class_valid <= 1'b0;
            blk_freq_we <= 1'b0;
            blk_mag_we  <= 1'b0;

            // Strict '>' matches np.argmax first-index tie-breaking
            if (scan_valid_d1 && (cur_mag_sq > max_mag_sq)) begin
                max_mag_sq <= cur_mag_sq;
                peak_bin   <= bin_idx_d1;
            end

            case (state)
                // ------------------------------------------------
                // A. Wait for FFT Block & Extract Band Peaks
                // ------------------------------------------------
                S_IDLE: begin
                    scan_valid_d1 <= 1'b0;
                    if (fft_done) begin
                        if (block_count == 7'd0)
                            speed_idx <= map_speed(speed_code);
                        ch    <= 2'd0;
                        band  <= 4'd0;
                        state <= S_BAND_INIT;
                    end
                end

                S_BAND_INIT: begin
                    bin_idx       <= get_band_start(band);
                    max_mag_sq    <= 32'd0;
                    peak_bin      <= get_band_start(band);
                    scan_valid_d1 <= 1'b0;
                    state         <= S_SCAN_ISSUE;
                end

                S_SCAN_ISSUE: begin
                    bin_idx_d1    <= bin_idx;
                    scan_valid_d1 <= 1'b1;
                    if (bin_idx == get_band_end(band))
                        state <= S_SCAN_LAST;
                    else
                        bin_idx <= bin_idx + 10'd1;
                end

                S_SCAN_LAST: begin
                    scan_valid_d1 <= 1'b0;
                    state         <= S_SQRT_INIT;
                end

                S_SQRT_INIT: begin
                    sqrt_rad  <= max_mag_sq;
                    sqrt_rem  <= 18'd0;
                    sqrt_root <= 16'd0;
                    sqrt_cnt  <= 5'd16;
                    state     <= S_SQRT_STEP;
                end

                S_SQRT_STEP: begin
                    if ({sqrt_rem[15:0], sqrt_rad[31:30]} >= {sqrt_root, 2'b01}) begin
                        sqrt_rem  <= {sqrt_rem[15:0], sqrt_rad[31:30]} - {sqrt_root, 2'b01};
                        sqrt_root <= {sqrt_root[14:0], 1'b1};
                    end else begin
                        sqrt_rem  <= {sqrt_rem[15:0], sqrt_rad[31:30]};
                        sqrt_root <= {sqrt_root[14:0], 1'b0};
                    end
                    sqrt_rad <= {sqrt_rad[29:0], 2'b00};
                    if (sqrt_cnt == 5'd1)
                        state <= S_BLK_STORE;
                    else
                        sqrt_cnt <= sqrt_cnt - 5'd1;
                end

                S_BLK_STORE: begin
                    blk_freq_we    <= 1'b1;
                    blk_mag_we     <= 1'b1;
                    blk_addr       <= ((ch * 12'd10 + {8'd0, band}) * NUM_BLOCKS) + {5'd0, block_count};
                    blk_freq_wdata <= peak_bin;
                    blk_mag_wdata  <= sqrt_root;

                    if (band == 4'd9) begin
                        if (ch == 2'd2) begin
                            if (block_count == (NUM_BLOCKS - 1)) begin
                                block_count <= 7'd0;
                                ch          <= 2'd0;
                                band        <= 4'd0;
                                sort_is_mag <= 1'b0;
                                state       <= S_SORT_INIT;
                            end else begin
                                block_count <= block_count + 7'd1;
                                state       <= S_IDLE;
                            end
                        end else begin
                            ch    <= ch + 2'd1;
                            band  <= 4'd0;
                            state <= S_BAND_INIT;
                        end
                    end else begin
                        band  <= band + 4'd1;
                        state <= S_BAND_INIT;
                    end
                end

                // ------------------------------------------------
                // B. Partial Selection Sort for Exact Median
                // ------------------------------------------------
                S_SORT_INIT: begin
                    sort_base <= (ch * 12'd10 + {8'd0, band}) * NUM_BLOCKS;
                    sort_i    <= 7'd0;
                    state     <= S_SORT_READ_I;
                end

                S_SORT_READ_I: begin
                    blk_addr <= sort_base + {5'd0, sort_i};
                    state    <= S_SORT_WAIT_I;
                end

                S_SORT_WAIT_I: begin
                    state <= S_SORT_READ_J;
                end

                S_SORT_READ_J: begin
                    sort_i_val   <= sort_is_mag ? blk_mag_rdata : {6'd0, blk_freq_rdata};
                    sort_min_val <= sort_is_mag ? blk_mag_rdata : {6'd0, blk_freq_rdata};
                    sort_min_idx <= sort_i;
                    sort_j       <= sort_i + 7'd1;
                    blk_addr     <= sort_base + {5'd0, sort_i + 7'd1};
                    state        <= S_SORT_WAIT_J_BRAM;
                end

                S_SORT_WAIT_J_BRAM: begin
                    state <= S_SORT_WAIT_J;
                end

                S_SORT_WAIT_J: begin
                    if ((sort_is_mag ? blk_mag_rdata : {6'd0, blk_freq_rdata}) < sort_min_val) begin
                        sort_min_val <= sort_is_mag ? blk_mag_rdata : {6'd0, blk_freq_rdata};
                        sort_min_idx <= sort_j;
                    end

                    if (sort_j == (NUM_BLOCKS - 1)) begin
                        state <= S_SORT_SWAP_A;
                    end else begin
                        sort_j   <= sort_j + 7'd1;
                        blk_addr <= sort_base + {5'd0, sort_j + 7'd1};
                        state    <= S_SORT_WAIT_J_BRAM;
                    end
                end

                S_SORT_SWAP_A: begin
                    if (sort_i == MEDIAN_IDX[6:0]) begin
                        if (sort_is_mag)
                            med_mag[ch*10 + band] <= sort_min_val;
                        else
                            med_freq[ch*10 + band] <= sort_min_val[9:0];

                        if (!sort_is_mag) begin
                            sort_is_mag <= 1'b1;
                            state       <= S_SORT_INIT;
                        end else begin
                            sort_is_mag <= 1'b0;
                            if (band == 4'd9) begin
                                if (ch == 2'd2) begin
                                    ch    <= 2'd0;
                                    band  <= 4'd0;
                                    cls   <= 3'd0;
                                    for (k = 0; k < 5; k = k + 1) class_score[k] <= 20'd0;
                                    state <= S_GAUSS_LOAD;
                                end else begin
                                    ch    <= ch + 2'd1;
                                    band  <= 4'd0;
                                    state <= S_SORT_INIT;
                                end
                            end else begin
                                band  <= band + 4'd1;
                                state <= S_SORT_INIT;
                            end
                        end
                    end else begin
                        if (sort_min_idx != sort_i) begin
                            blk_freq_we    <= ~sort_is_mag;
                            blk_mag_we     <= sort_is_mag;
                            blk_addr       <= sort_base + {5'd0, sort_i};
                            blk_freq_wdata <= sort_min_val[9:0];
                            blk_mag_wdata  <= sort_min_val;
                            state          <= S_SORT_SWAP_B;
                        end else begin
                            sort_i <= sort_i + 7'd1;
                            state  <= S_SORT_READ_I;
                        end
                    end
                end

                S_SORT_SWAP_B: begin
                    blk_freq_we    <= ~sort_is_mag;
                    blk_mag_we     <= sort_is_mag;
                    blk_addr       <= sort_base + {5'd0, sort_min_idx};
                    blk_freq_wdata <= sort_i_val[9:0];
                    blk_mag_wdata  <= sort_i_val;
                    sort_i         <= sort_i + 7'd1;
                    state          <= S_SORT_READ_I;
                end

                // ------------------------------------------------
                // C. Gaussian Similarity Scoring & Majority Vote
                // ------------------------------------------------
                S_GAUSS_LOAD: begin
                    feat_rom_addr   <= (speed_idx * 9'd150) + (ch * 9'd50) + (cls * 9'd10) + {5'd0, band};
                    thresh_rom_addr <= (speed_idx * 4'd3) + {2'd0, ch};
                    gauss_is_mag    <= 1'b0;
                    state           <= S_GAUSS_WAIT_ROM;
                end

                S_GAUSS_WAIT_ROM: begin
                    state <= S_GAUSS_DIFF;
                end

                S_GAUSS_DIFF: begin
                    g_diff       <= $signed({1'b0, cur_feat_val}) - $signed({1'b0, cur_feat_med});
                    g_inv_sig    <= cur_feat_inv;
                    g_zero_sig   <= (cur_feat_inv == 24'd0);
                    g_exact_zero <= (cur_feat_val == cur_feat_med);
                    state        <= S_GAUSS_MUL_Z;
                end

                S_GAUSS_MUL_Z: begin
                    g_z_q20 <= g_diff * $signed({1'b0, g_inv_sig});
                    state   <= S_GAUSS_SQ_U;
                end

                S_GAUSS_SQ_U: begin
                    if (z_q8_full >= 29'sd1024 || z_q8_full <= -29'sd1024) begin
                        g_overflow   <= 1'b1;
                        exp_lut_addr <= 9'd511;
                    end else begin
                        g_overflow   <= 1'b0;
                        exp_lut_addr <= z_sq_q16_s[19:11];
                    end
                    state <= S_GAUSS_LUT_WAIT;
                end

                S_GAUSS_LUT_WAIT: begin
                    state <= S_GAUSS_ACCUM;
                end

                S_GAUSS_ACCUM: begin
                    if (!gauss_is_mag) begin
                        freq_score_q16 <= g_zero_sig ? (g_exact_zero ? 16'hFFFF : 16'd0) :
                                          (g_overflow ? 16'd0 : exp_lut_data);
                        gauss_is_mag   <= 1'b1;
                        state          <= S_GAUSS_DIFF;
                    end else begin
                        class_score[cls] <= class_score[cls] +
                            (({4'd0, freq_score_q16} +
                              {4'd0, (g_zero_sig ? (g_exact_zero ? 16'hFFFF : 16'd0) :
                                     (g_overflow ? 16'd0 : exp_lut_data))}) >> 1);

                        if (cls == 3'd4) begin
                            if (band == 4'd9) begin
                                state <= S_CH_DECIDE;
                            end else begin
                                band  <= band + 4'd1;
                                cls   <= 3'd0;
                                state <= S_GAUSS_LOAD;
                            end
                        end else begin
                            cls   <= cls + 3'd1;
                            state <= S_GAUSS_LOAD;
                        end
                    end
                end

                S_CH_DECIDE: begin
                    if (ch == 2'd0) begin
                        dbg_speed_idx <= speed_idx;
                        dbg_ch1_s0    <= class_score[0];
                        dbg_ch1_s1    <= class_score[1];
                        dbg_ch1_s2    <= class_score[2];
                        dbg_ch1_s3    <= class_score[3];
                        dbg_ch1_s4    <= class_score[4];
                        dbg_ch1_min_s <= cur_min_score;
                    end
                    if ((best_scr >= cur_min_score) && ((best_scr - second_scr) >= cur_min_margin))
                        ch_pred[ch] <= best_cls;
                    else
                        ch_pred[ch] <= CLS_UNKNOWN;

                    if (ch == 2'd2) begin
                        state <= S_VOTE;
                    end else begin
                        ch   <= ch + 2'd1;
                        band <= 4'd0;
                        cls  <= 3'd0;
                        for (k = 0; k < 5; k = k + 1) class_score[k] <= 20'd0;
                        state <= S_GAUSS_LOAD;
                    end
                end

                S_VOTE: begin
                    ch1_pred <= ch_pred[0];
                    ch2_pred <= ch_pred[1];
                    ch3_pred <= ch_pred[2];

                    if ((ch_pred[0] != CLS_UNKNOWN) &&
                        ((ch_pred[0] == ch_pred[1]) || (ch_pred[0] == ch_pred[2]))) begin
                        fault_class <= ch_pred[0];
                    end else if ((ch_pred[1] != CLS_UNKNOWN) && (ch_pred[1] == ch_pred[2])) begin
                        fault_class <= ch_pred[1];
                    end else begin
                        fault_class <= CLS_UNKNOWN;
                    end

                    class_valid <= 1'b1;
                    state       <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule