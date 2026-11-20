`timescale 1ns / 1ps

// Packet format:
//   0xAA 0x66
//   Then 450 x 10 bytes (80-bit big-endian) for gauss_features.mem
//   Then   9 x  5 bytes (40-bit big-endian) for decision_thresh.mem
//******Written by Dhanush************************
module uart_calib_loader (
    input  wire        clk,
    input  wire        reset,
    input  wire [7:0]  data_in,
    input  wire        data_valid,

    output wire        calib_busy,
    output reg         calib_done,

    // Write ports to vibration_gaussian_classifier
    output reg         cfg_feat_we,
    output reg  [8:0]  cfg_feat_addr,
    output reg  [79:0] cfg_feat_wdata,

    output reg         cfg_thresh_we,
    output reg  [3:0]  cfg_thresh_addr,
    output reg  [39:0] cfg_thresh_wdata
);

    localparam [1:0] S_WAIT_AA = 2'd0,
                     S_WAIT_66 = 2'd1,
                     S_FEAT    = 2'd2,
                     S_THRESH  = 2'd3;

    reg [1:0]  state;
    reg [3:0]  byte_cnt;
    reg [8:0]  entry_idx;
    reg [79:0] shift_reg;

    assign calib_busy = (state == S_FEAT) || (state == S_THRESH);

    always @(posedge clk) begin
        if (reset) begin
            state            <= S_WAIT_AA;
            byte_cnt         <= 4'd0;
            entry_idx        <= 9'd0;
            shift_reg        <= 80'd0;
            calib_done       <= 1'b0;
            cfg_feat_we      <= 1'b0;
            cfg_feat_addr    <= 9'd0;
            cfg_feat_wdata   <= 80'd0;
            cfg_thresh_we    <= 1'b0;
            cfg_thresh_addr  <= 4'd0;
            cfg_thresh_wdata <= 40'd0;
        end else begin
            calib_done    <= 1'b0;
            cfg_feat_we   <= 1'b0;
            cfg_thresh_we <= 1'b0;

            if (data_valid) begin
                case (state)
                    S_WAIT_AA: begin
                        if (data_in == 8'hAA)
                            state <= S_WAIT_66;
                    end

                    S_WAIT_66: begin
                        if (data_in == 8'h66) begin
                            byte_cnt  <= 4'd0;
                            entry_idx <= 9'd0;
                            state     <= S_FEAT;
                        end else if (data_in != 8'hAA) begin
                            state <= S_WAIT_AA;
                        end
                    end

                    S_FEAT: begin
                        if (byte_cnt == 4'd9) begin
                            cfg_feat_we    <= 1'b1;
                            cfg_feat_addr  <= entry_idx;
                            cfg_feat_wdata <= {shift_reg[71:0], data_in};
                            byte_cnt       <= 4'd0;

                            if (entry_idx == 9'd449) begin
                                entry_idx <= 9'd0;
                                state     <= S_THRESH;
                            end else begin
                                entry_idx <= entry_idx + 9'd1;
                            end
                        end else begin
                            shift_reg <= {shift_reg[71:0], data_in};
                            byte_cnt  <= byte_cnt + 4'd1;
                        end
                    end

                    S_THRESH: begin
                        if (byte_cnt == 4'd4) begin
                            cfg_thresh_we    <= 1'b1;
                            cfg_thresh_addr  <= entry_idx[3:0];
                            cfg_thresh_wdata <= {shift_reg[31:0], data_in};
                            byte_cnt         <= 4'd0;

                            if (entry_idx == 9'd8) begin
                                calib_done <= 1'b1;
                                state      <= S_WAIT_AA;
                            end else begin
                                entry_idx <= entry_idx + 9'd1;
                            end
                        end else begin
                            shift_reg <= {shift_reg[71:0], data_in};
                            byte_cnt  <= byte_cnt + 4'd1;
                        end
                    end

                    default: state <= S_WAIT_AA;
                endcase
            end
        end
    end

endmodule