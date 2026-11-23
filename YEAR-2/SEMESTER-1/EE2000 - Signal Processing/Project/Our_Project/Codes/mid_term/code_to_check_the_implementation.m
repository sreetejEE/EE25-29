%% MATLAB VIBRATION GENERATOR, SENDER & FPGA SPECTRUM PLOTTER
% 1. Generates 256-sample blocks of 3-axis vibration data.
% 2. Plots generated Time-Domain signals & Theoretical FFT.
% 3. Sends packet to FPGA over UART.
% 4. Reads and plots the hardware-calculated FFT spectrum from FPGA.

clc;
clear;
close all;

%% Configuration
COM_PORT    = "COM6";       % Change to your board's COM port
BAUD_RATE   = 300000;
Fs          = 1500;         % Sample rate (Hz)
BUFFER_SIZE = 256;          % 256 frames per block
FSR_G       = 2.0;          % +/- 2g range
NOISE_AMP   = 0.01;         % Noise in g
MAX_BUFFERS = Inf;

current_rpm   = 1500;       % 1200, 1500, or 1800
current_fault = "unbalance";% healthy, unbalance, misalignment, broken_bar

switch current_rpm
    case 1200, speed_code = uint8(2);
    case 1500, speed_code = uint8(0);
    case 1800, speed_code = uint8(1);
    otherwise, error("Unsupported RPM.");
end

%% Open Serial Port
device = serialport(COM_PORT, BAUD_RATE, ...
    "DataBits", 8, "Parity", "none", ...
    "StopBits", 1, "FlowControl", "none");
device.Timeout = 1.0;
cleanupObj = onCleanup(@() cleanupSerial(device));
pause(1.5);
flush(device);

fprintf("Connected to %s at %d baud.\n", COM_PORT, BAUD_RATE);

%% Setup Live Plots
fig = figure("Name","Vibration Generator & FPGA Spectrum Monitor","Position",[80 80 1200 750]);
tiledlayout(3,2,"TileSpacing","compact","Padding","compact");

freq_axis = (0:127) * (Fs / BUFFER_SIZE);  % Bins 0..127 (0 Hz to ~744 Hz)

% Column 1: Generated Input (Time & Generated Spectrum)
axTimeX = nexttile(1); hTimeX = plot(axTimeX, nan, nan); grid(axTimeX,"on"); ylabel(axTimeX,"X (g)"); title(axTimeX,"Generated Time Signals");
axTimeY = nexttile(3); hTimeY = plot(axTimeY, nan, nan); grid(axTimeY,"on"); ylabel(axTimeY,"Y (g)");
axTimeZ = nexttile(5); hTimeZ = plot(axTimeZ, nan, nan); grid(axTimeZ,"on"); ylabel(axTimeZ,"Z (g)"); xlabel(axTimeZ,"Time (s)");

% Column 2: FPGA Hardware Spectrum Output
axFpgaX = nexttile(2); hFpgaX = plot(axFpgaX, freq_axis, zeros(1,128)); grid(axFpgaX,"on"); ylabel(axFpgaX,"|X| mag"); title(axFpgaX,"FPGA Output Spectrum (Bins 0-127)");
axFpgaY = nexttile(4); hFpgaY = plot(axFpgaY, freq_axis, zeros(1,128)); grid(axFpgaY,"on"); ylabel(axFpgaY,"|Y| mag");
axFpgaZ = nexttile(6); hFpgaZ = plot(axFpgaZ, freq_axis, zeros(1,128)); grid(axFpgaZ,"on"); ylabel(axFpgaZ,"|Z| mag"); xlabel(axFpgaZ,"Frequency (Hz)");

%% Main Streaming Loop
sample_index = 0;
buffer_count = 0;

while buffer_count < MAX_BUFFERS && isvalid(fig)
    loopTimer = tic;

    % 1. Accumulate full block of 256 samples
    t = (sample_index : sample_index + BUFFER_SIZE - 1) / Fs;
    f_rot = current_rpm / 60;

    sig_X = zeros(size(t));
    sig_Y = zeros(size(t));
    sig_Z = zeros(size(t));

    switch current_fault
        case "healthy"
        case "unbalance"
            sig_Z = 1.20 * sin(2*pi*f_rot*t);
        case "misalignment"
            sig_X = 0.20 * sin(2*pi*2*f_rot*t);
            sig_Y = 0.24 * sin(2*pi*2*f_rot*t + pi/4);
            sig_Z = 0.10 * sin(2*pi*3*f_rot*t);
        case "broken_bar"
            f_line = 50; slip = 0.03; f_bb = 2*f_line*(1-slip);
            sig_X = 0.16*sin(2*pi*f_bb*t) + 0.08*sin(2*pi*(f_bb-2*slip*f_line)*t);
            sig_Y = 0.08*sin(2*pi*(f_bb+2*slip*f_line)*t);
            sig_Z = 0.06*sin(2*pi*f_bb*t + pi/5);
    end

    % Add noise & clamp
    sig_X = min(max(sig_X + NOISE_AMP*randn(size(t)), -FSR_G), FSR_G);
    sig_Y = min(max(sig_Y + NOISE_AMP*randn(size(t)), -FSR_G), FSR_G);
    sig_Z = min(max(sig_Z + NOISE_AMP*randn(size(t)), -FSR_G), FSR_G);

    % Quantize to signed 16-bit
    qX = int16(round((sig_X / FSR_G) * 32767));
    qY = int16(round((sig_Y / FSR_G) * 32767));
    qZ = int16(round((sig_Z / FSR_G) * 32767));

    % 2. Update Generated Time Plots
    set(hTimeX, "XData", t, "YData", sig_X);
    set(hTimeY, "XData", t, "YData", sig_Y);
    set(hTimeZ, "XData", t, "YData", sig_Z);

    % 3. Interleave and transmit to FPGA
    interleaved = zeros(1, 3 * BUFFER_SIZE, "int16");
    interleaved(1:3:end) = qX;
    interleaved(2:3:end) = qY;
    interleaved(3:3:end) = qZ;

    payload = typecast(swapbytes(interleaved), "uint8");
    header  = uint8([hex2dec("AA"), hex2dec("55"), speed_code]);
    packet  = [header, payload];

    write(device, packet, "uint8");

    % 4. Read back FPGA Spectrum
    [re, im, ok] = read_spectrum_frame(device, 0.4);

    if ok
        % Compute magnitude = sqrt(re^2 + im^2) for bins 0..127
        mag_X = sqrt(re(:,1).^2 + im(:,1).^2);
        mag_Y = sqrt(re(:,2).^2 + im(:,2).^2);
        mag_Z = sqrt(re(:,3).^2 + im(:,3).^2);

        set(hFpgaX, "YData", mag_X);
        set(hFpgaY, "YData", mag_Y);
        set(hFpgaZ, "YData", mag_Z);
    end

    drawnow limitrate;

    buffer_count = buffer_count + 1;
    sample_index = sample_index + BUFFER_SIZE;

    % Pace to match sampling rate (256 / 1500 = 170.6 ms)
    targetTime = BUFFER_SIZE / Fs;
    remTime = targetTime - toc(loopTimer);
    if remTime > 0
        pause(remTime);
    end
end

function cleanupSerial(device)
    try
        if ~isempty(device) && isvalid(device)
            delete(device);
        end
    catch
    end
end