`timescale 1ns / 1ps
//******Written by Dhanush************************
module fft_controller (
    input  wire        clk,
    input  wire        reset,

    // Parser buffer control
    input  wire        buffer_full,
    output reg         buffer_release,

    // Parser sample interface
    output wire [9:0]  parser_addr,
    input  wire signed [15:0] parser_x,
    input  wire signed [15:0] parser_y,
    input  wire signed [15:0] parser_z,

    // Spectrum selection
    // [11:10] = axis (0=X, 1=Y, 2=Z), [9:0] = FFT bin
    input  wire [11:0] bin_addr,

    // Selected FFT result (Synchronous BRAM read, 1-cycle latency)
    output reg signed [31:0] bin_re,
    output reg signed [31:0] bin_im,

    // FFT completion
    output reg         fft_done
);

    localparam [15:0] FFT_CONFIG = 16'h0155; // Forward FFT with scaling

    localparam [2:0] IDLE     = 3'd0,
                     CONFIG   = 3'd1,
                     PREFETCH = 3'd2,
                     SEND     = 3'd3,
                     WAIT     = 3'd4,
                     NEXT     = 3'd5,
                     FINISH   = 3'd6;

    reg [2:0] state;
    reg [1:0] axis;
    reg [9:0] sample_index;
    reg [9:0] output_index;

    reg  config_valid;
    reg  data_valid;
    wire config_ready;
    wire data_ready;

    wire        output_valid;
    wire        output_last;
    wire [31:0] output_data;
    wire        output_ready;

    // Only accept data when the controller is actively storing results
    assign output_ready = (state == WAIT);

    assign parser_addr = sample_index;

    reg signed [15:0] selected_sample;
    always @(*) begin
        case (axis)
            2'd0:    selected_sample = parser_x;
            2'd1:    selected_sample = parser_y;
            2'd2:    selected_sample = parser_z;
            default: selected_sample = 16'sd0;
        endcase
    end

    // Xilinx FFT AXI4-Stream data format:
    // [15:0]  = Real (XN_RE)
    // [31:16] = Imaginary (XN_IM)
    wire [31:0] fft_input_data = {16'd0, selected_sample};

    // ------------------------------------------------
    // Xilinx FFT IP Instantiation
    // ------------------------------------------------
    xfft_0 fft_inst (
        .aclk(clk),

        .s_axis_config_tdata(FFT_CONFIG),
        .s_axis_config_tvalid(config_valid),
        .s_axis_config_tready(config_ready),

        .s_axis_data_tdata(fft_input_data),
        .s_axis_data_tvalid(data_valid),
        .s_axis_data_tready(data_ready),
        .s_axis_data_tlast(data_valid && (sample_index == 10'd1023)),

        .m_axis_data_tdata(output_data),
        .m_axis_data_tvalid(output_valid),
        .m_axis_data_tready(output_ready),
        .m_axis_data_tlast(output_last),

        .event_frame_started(),
        .event_tlast_unexpected(),
        .event_tlast_missing(),
        .event_status_channel_halt(),
        .event_data_in_channel_halt(),
        .event_data_out_channel_halt()
    );

    // ------------------------------------------------
    // Result Storage (Infers True Block RAM)
    // ------------------------------------------------
    (* ram_style = "block" *) reg signed [15:0] fft_x_real [0:1023];
    (* ram_style = "block" *) reg signed [15:0] fft_x_imag [0:1023];
    (* ram_style = "block" *) reg signed [15:0] fft_y_real [0:1023];
    (* ram_style = "block" *) reg signed [15:0] fft_y_imag [0:1023];
    (* ram_style = "block" *) reg signed [15:0] fft_z_real [0:1023];
    (* ram_style = "block" *) reg signed [15:0] fft_z_imag [0:1023];

    // Synchronous BRAM Readout (1-clock cycle latency)
    always @(posedge clk) begin
        case (bin_addr[11:10])
            2'd0: begin
                bin_re <= {{16{fft_x_real[bin_addr[9:0]][15]}}, fft_x_real[bin_addr[9:0]]};
                bin_im <= {{16{fft_x_imag[bin_addr[9:0]][15]}}, fft_x_imag[bin_addr[9:0]]};
            end
            2'd1: begin
                bin_re <= {{16{fft_y_real[bin_addr[9:0]][15]}}, fft_y_real[bin_addr[9:0]]};
                bin_im <= {{16{fft_y_imag[bin_addr[9:0]][15]}}, fft_y_imag[bin_addr[9:0]]};
            end
            2'd2: begin
                bin_re <= {{16{fft_z_real[bin_addr[9:0]][15]}}, fft_z_real[bin_addr[9:0]]};
                bin_im <= {{16{fft_z_imag[bin_addr[9:0]][15]}}, fft_z_imag[bin_addr[9:0]]};
            end
            default: begin
                bin_re <= 32'sd0;
                bin_im <= 32'sd0;
            end
        endcase
    end

    // ------------------------------------------------
    // FSM Control
    // ------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state          <= IDLE;
            axis           <= 2'd0;
            sample_index   <= 10'd0;
            output_index   <= 10'd0;
            config_valid   <= 1'b0;
            data_valid     <= 1'b0;
            buffer_release <= 1'b0;
            fft_done       <= 1'b0;
        end else begin
            buffer_release <= 1'b0;
            fft_done       <= 1'b0;

            case (state)
                IDLE: begin
                    config_valid <= 1'b0;
                    data_valid   <= 1'b0;
                    sample_index <= 10'd0;
                    output_index <= 10'd0;
                    axis         <= 2'd0;

                    if (buffer_full)
                        state <= CONFIG;
                end

                CONFIG: begin
                    config_valid <= 1'b1;
                    if (config_valid && config_ready) begin
                        config_valid <= 1'b0;
                        sample_index <= 10'd0;
                        state        <= PREFETCH;
                    end
                end

                PREFETCH: begin
                    // 1 cycle wait for synchronous parser BRAM to output sample 0
                    data_valid <= 1'b1;
                    state      <= SEND;
                end

                SEND: begin
                    if (data_valid && data_ready) begin
                        if (sample_index == 10'd1023) begin
                            data_valid   <= 1'b0;
                            output_index <= 10'd0;
                            state        <= WAIT;
                        end else begin
                            sample_index <= sample_index + 10'd1;
                            data_valid   <= 1'b0;
                            state        <= PREFETCH;
                        end
                    end
                end

                WAIT: begin
                    if (output_valid && output_ready) begin
                        // PG109 standard bit packing: [15:0] = Real, [31:16] = Imag
                        case (axis)
                            2'd0: begin
                                fft_x_real[output_index] <= $signed(output_data[15:0]);
                                fft_x_imag[output_index] <= $signed(output_data[31:16]);
                            end
                            2'd1: begin
                                fft_y_real[output_index] <= $signed(output_data[15:0]);
                                fft_y_imag[output_index] <= $signed(output_data[31:16]);
                            end
                            2'd2: begin
                                fft_z_real[output_index] <= $signed(output_data[15:0]);
                                fft_z_imag[output_index] <= $signed(output_data[31:16]);
                            end
                            default: ;
                        endcase

                        if (output_last) begin
                            state <= NEXT;
                        end else begin
                            output_index <= output_index + 10'd1;
                        end
                    end
                end

                NEXT: begin
                    if (axis == 2'd0) begin
                        axis         <= 2'd1;
                        sample_index <= 10'd0;
                        state        <= CONFIG;
                    end else if (axis == 2'd1) begin
                        axis         <= 2'd2;
                        sample_index <= 10'd0;
                        state        <= CONFIG;
                    end else begin
                        state <= FINISH;
                    end
                end

                FINISH: begin
                    buffer_release <= 1'b1;
                    fft_done       <= 1'b1;
                    state          <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule