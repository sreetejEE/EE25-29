`timescale 1ns / 1ps

module fft_controller (

    input wire clk,
    input wire reset,

    // Parser buffer control
    input wire buffer_full,
    output reg buffer_release,

    // Parser sample interface
    output reg [7:0] parser_addr,

    input wire signed [15:0] parser_x,
    input wire signed [15:0] parser_y,
    input wire signed [15:0] parser_z,

    // Spectrum selection
    input wire [9:0] bin_addr,

    // Selected FFT result
    output wire signed [31:0] bin_re,
    output wire signed [31:0] bin_im,

    // FFT completion
    output reg fft_done
);

    localparam [15:0] FFT_CONFIG = 16'h0155;

    // STATE MACHINE

    localparam IDLE   = 3'd0;
    localparam CONFIG = 3'd1;
    localparam SEND   = 3'd2;
    localparam WAIT   = 3'd3;
    localparam NEXT   = 3'd4;
    localparam FINISH = 3'd5;

    reg [2:0] state;

    // Axis:
    // 0 = X
    // 1 = Y
    // 2 = Z

    reg [1:0] axis;

    // Input sample index: 0 to 255
    reg [7:0] sample_index;

    // FFT output index: 0 to 255
    reg [7:0] output_index;

    // FFT IP CONTROL SIGNALS

    reg config_valid;
    reg data_valid;

    wire config_ready;
    wire data_ready;

    wire output_valid;
    wire output_last;

    wire [31:0] output_data;

    wire output_ready;

    assign output_ready = 1'b1;

    // PARSER SAMPLE SELECTION

    always @(*) begin

        parser_addr = sample_index;

    end

    reg signed [15:0] selected_sample;

    always @(*) begin

        case (axis)

            2'd0:
                selected_sample = parser_x;

            2'd1:
                selected_sample = parser_y;

            2'd2:
                selected_sample = parser_z;

            default:
                selected_sample = 16'sd0;

        endcase

    end

    // FFT input format:
    // Upper 16 bits = real
    // Lower 16 bits = imaginary

    wire [31:0] fft_input_data;

    assign fft_input_data = {
        selected_sample,
        16'd0
    };

    // FFT IP

    xfft_0 fft_inst (

        .aclk(clk),

        // Configuration channel
        .s_axis_config_tdata(FFT_CONFIG),
        .s_axis_config_tvalid(config_valid),
        .s_axis_config_tready(config_ready),

        // Input channel
        .s_axis_data_tdata(fft_input_data),
        .s_axis_data_tvalid(data_valid),
        .s_axis_data_tready(data_ready),

        .s_axis_data_tlast(
            data_valid &&
            (sample_index == 8'd255)
        ),

        // Output channel
        .m_axis_data_tdata(output_data),
        .m_axis_data_tvalid(output_valid),
        .m_axis_data_tready(output_ready),
        .m_axis_data_tlast(output_last),

        // Event outputs unused
        .event_frame_started(),
        .event_tlast_unexpected(),
        .event_tlast_missing(),
        .event_status_channel_halt(),
        .event_data_in_channel_halt(),
        .event_data_out_channel_halt()

    );

    // FFT RESULT MEMORY
    //
    // 256 bins for X
    // 256 bins for Y
    // 256 bins for Z
    //
    // Each bin stores signed 16-bit real and imaginary values.

    reg signed [15:0] fft_x_real [0:255];
    reg signed [15:0] fft_x_imag [0:255];

    reg signed [15:0] fft_y_real [0:255];
    reg signed [15:0] fft_y_imag [0:255];

    reg signed [15:0] fft_z_real [0:255];
    reg signed [15:0] fft_z_imag [0:255];

    // SPECTRUM READOUT
    //
    // bin_addr[9:8] = axis
    // bin_addr[7:0] = FFT bin
    //
    // 00 = X
    // 01 = Y
    // 10 = Z

    wire [1:0] selected_axis;
    wire [7:0] selected_bin;

    assign selected_axis = bin_addr[9:8];
    assign selected_bin  = bin_addr[7:0];

    reg signed [15:0] selected_real;
    reg signed [15:0] selected_imag;

    always @(*) begin

        selected_real = 16'sd0;
        selected_imag = 16'sd0;

        case (selected_axis)

            2'd0: begin

                selected_real = fft_x_real[selected_bin];
                selected_imag = fft_x_imag[selected_bin];

            end

            2'd1: begin

                selected_real = fft_y_real[selected_bin];
                selected_imag = fft_y_imag[selected_bin];

            end

            2'd2: begin

                selected_real = fft_z_real[selected_bin];
                selected_imag = fft_z_imag[selected_bin];

            end

            default: begin

                selected_real = 16'sd0;
                selected_imag = 16'sd0;

            end

        endcase

    end

    // Sign-extend 16-bit FFT values to 32 bits

    assign bin_re = {
        {16{selected_real[15]}},
        selected_real
    };

    assign bin_im = {
        {16{selected_imag[15]}},
        selected_imag
    };

    // MAIN CONTROLLER

    always @(posedge clk) begin

        if (reset) begin

            state <= IDLE;

            axis <= 2'd0;

            sample_index <= 8'd0;
            output_index <= 8'd0;

            config_valid <= 1'b0;
            data_valid <= 1'b0;

            buffer_release <= 1'b0;
            fft_done <= 1'b0;

        end

        else begin

            // Default pulse outputs
            buffer_release <= 1'b0;
            fft_done <= 1'b0;

            case (state)

                // WAIT FOR COMPLETE PARSER BUFFER

                IDLE: begin

                    config_valid <= 1'b0;
                    data_valid <= 1'b0;

                    sample_index <= 8'd0;
                    output_index <= 8'd0;

                    axis <= 2'd0;

                    if (buffer_full) begin

                        state <= CONFIG;

                    end

                end

                // ------------------------------------------------
                // SEND FFT CONFIGURATION
                // ------------------------------------------------

                CONFIG: begin

                    config_valid <= 1'b1;

                    if (config_valid && config_ready) begin

                        config_valid <= 1'b0;

                        sample_index <= 8'd0;

                        data_valid <= 1'b1;

                        state <= SEND;

                    end

                end

                // ------------------------------------------------
                // SEND 256 SAMPLES OF CURRENT AXIS
                // ------------------------------------------------

                SEND: begin

                    if (data_valid && data_ready) begin

                        if (sample_index == 8'd255) begin

                            data_valid <= 1'b0;

                            output_index <= 8'd0;

                            state <= WAIT;

                        end

                        else begin

                            sample_index <= sample_index + 1'b1;

                        end

                    end

                end

                // ------------------------------------------------
                // RECEIVE 256 FFT OUTPUTS
                // ------------------------------------------------

                WAIT: begin

                    if (output_valid && output_ready) begin

                        // output_data[31:16] = real
                        // output_data[15:0]  = imaginary

                        case (axis)

                            2'd0: begin

                                fft_x_real[output_index]
                                    <= $signed(output_data[31:16]);

                                fft_x_imag[output_index]
                                    <= $signed(output_data[15:0]);

                            end

                            2'd1: begin

                                fft_y_real[output_index]
                                    <= $signed(output_data[31:16]);

                                fft_y_imag[output_index]
                                    <= $signed(output_data[15:0]);

                            end

                            2'd2: begin

                                fft_z_real[output_index]
                                    <= $signed(output_data[31:16]);

                                fft_z_imag[output_index]
                                    <= $signed(output_data[15:0]);

                            end

                            default: begin

                            end

                        endcase

                        // Final output sample of this axis
                        if (output_last) begin

                            state <= NEXT;

                        end

                        else begin

                            output_index <= output_index + 1'b1;

                        end

                    end

                end

                // ------------------------------------------------
                // MOVE TO NEXT AXIS
                // ------------------------------------------------

                NEXT: begin

                    config_valid <= 1'b0;
                    data_valid <= 1'b0;

                    if (axis == 2'd0) begin

                        // X finished, start Y

                        axis <= 2'd1;

                        sample_index <= 8'd0;
                        output_index <= 8'd0;

                        state <= CONFIG;

                    end

                    else if (axis == 2'd1) begin

                        // Y finished, start Z

                        axis <= 2'd2;

                        sample_index <= 8'd0;
                        output_index <= 8'd0;

                        state <= CONFIG;

                    end

                    else begin

                        // X, Y and Z finished

                        state <= FINISH;

                    end

                end

                // ------------------------------------------------
                // RELEASE PARSER BUFFER
                // ------------------------------------------------

                FINISH: begin

                    buffer_release <= 1'b1;

                    fft_done <= 1'b1;

                    state <= IDLE;

                end

                // ------------------------------------------------
                // DEFAULT
                // ------------------------------------------------

                default: begin

                    state <= IDLE;

                    config_valid <= 1'b0;
                    data_valid <= 1'b0;

                    sample_index <= 8'd0;
                    output_index <= 8'd0;

                end

            endcase

        end

    end

endmodule