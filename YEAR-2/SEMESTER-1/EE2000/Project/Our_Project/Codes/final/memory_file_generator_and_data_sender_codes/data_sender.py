#************Written by Sreetej*************
import time
from pathlib import Path

import numpy as np
import pandas as pd
import serial
from scipy.signal import firwin, resample_poly

# ============================================================
# 1. MANUAL CONFIGURATION (Edit these lists as you like)
# ============================================================
COM_PORT = "COM6"
BAUD_RATE = 2_000_000
ROOT_DIR = Path(r"C:\Users\vishw\Documents\Vibration Dataset")

# Choose which speeds, faults (and their order), and columns to test:
SPEEDS = [50, 75, 100]
FAULTS = [
    "SOFT"
]
COLUMNS = [4, 5,10, 13,]

REAL_TIME_PACE = True  # False = ~3.8s/recording, True = 12s/recording

# ============================================================
# 2. FIXED SETTINGS & ONE ANTI-ALIAS FILTER
# ============================================================
FAULT_FOLDERS = {
    "HEALTHY":          "healthy 2",
    "BPFO":             "bearing bpfo 2",
    "BPFI":             "bearing bpfi 2",
    "STATOR_SHORT":     "stator short 1",
    "BROKEN_ROTOR_BAR": "broken rotor bar",
    "SOFT": "soft foot 1"
}
CLS_NAMES = ["HEALTHY", "BPFO", "BPFI", "STATOR_SHORT", "BROKEN_ROTOR_BAR", "UNKNOWN", "SOFT"]

FS_ORIG = 20_000
FS = 10_000
FFT_SIZE = 1024
NUM_BLOCKS = 117
REQ_SAMPLES = NUM_BLOCKS * FFT_SIZE
INT16_SCALE = 16000.0
BLOCK_TIME = FFT_SIZE / FS  # 0.1024 s

# Single 401-tap Kaiser anti-alias filter (20 kHz -> 10 kHz)
FIR_COEFF = firwin(401, 4750, window=("kaiser", 8.6), fs=FS_ORIG)

# ============================================================
# 3. RUN TESTS
# ============================================================
total = 0
correct = 0

def upload_mem_to_fpga(ser, feat_file="gauss_features.mem", thresh_file="decision_thresh.mem"):
    with open(feat_file, "r") as f:
        feat_bytes = b"".join(bytes.fromhex(line.strip()) for line in f if line.strip())
    with open(thresh_file, "r") as f:
        thresh_bytes = b"".join(bytes.fromhex(line.strip()) for line in f if line.strip())

    assert len(feat_bytes) == 450 * 10, f"Expected 4500 feature bytes, got {len(feat_bytes)}"
    assert len(thresh_bytes) == 9 * 5, f"Expected 45 threshold bytes, got {len(thresh_bytes)}"

    ser.reset_input_buffer()
    ser.write(b"\xAA\x66" + feat_bytes + thresh_bytes)
    ack = ser.read(2)
    if ack != b"\xCC\x77":
        raise RuntimeError(f"FPGA calibration ACK failed (got {ack!r})")
    print("Uploaded live .mem thresholds to FPGA over UART (ACK OK).")


with serial.Serial(COM_PORT, BAUD_RATE, timeout=2.0) as ser:
    upload_mem_to_fpga(ser)

    for spd in SPEEDS:
        header = bytes([0xAA, 0x55, spd])

        for fault in FAULTS:
            folder = FAULT_FOLDERS[fault]
            base_dir = ROOT_DIR / str(spd) / folder
            stem = f"Vibration_Motor-2_{spd}_time-{folder}"

            # Load CH1, CH2, CH3 CSVs once for this speed & fault
            dfs = [pd.read_csv(base_dir / f"{stem}-ch{ch}.csv", header=None) for ch in (1, 2, 3)]
            print(f"\n=== Speed {spd} | {fault} ===")

            for col in COLUMNS:
                # Preprocess all 3 channels
                proc_int16 = np.zeros((REQ_SAMPLES, 3), dtype=np.int16)
                for ch in range(3):
                    sig = pd.to_numeric(dfs[ch].iloc[:, col - 1], errors="coerce").dropna().to_numpy(dtype=np.float64)
                    sig = sig - np.mean(sig)
                    ds = resample_poly(sig, up=1, down=2, window=FIR_COEFF)[:REQ_SAMPLES]
                    proc_int16[:, ch] = np.clip(np.round(ds * INT16_SCALE), -32768, 32767).astype(np.int16)

                # Stream 117 blocks over UART
                ser.reset_input_buffer()
                for blk in range(NUM_BLOCKS):
                    t0 = time.perf_counter()
                    s_i = blk * FFT_SIZE
                    payload = proc_int16[s_i : s_i + FFT_SIZE, :].astype(">i2").tobytes()
                    ser.write(header + payload)

                    if REAL_TIME_PACE:
                        while (time.perf_counter() - t0) < BLOCK_TIME:
                            pass
                    else:
                        time.sleep(0.001)

                # Read FPGA result (145 bytes)
                rx = ser.read(145)
                if len(rx) == 145 and rx[0] == 0xBB and rx[1] == 0x66:
                    ch1, ch2, ch3, final = (CLS_NAMES[rx[2]], CLS_NAMES[rx[3]], CLS_NAMES[rx[4]], CLS_NAMES[rx[5]])
                    ok = (final == fault)
                    total += 1
                    correct += int(ok)
                    print(f"  Col {col:2d}: CH1={ch1:<16s} CH2={ch2:<16s} CH3={ch3:<16s} => FINAL={final:<16s} [{'OK' if ok else 'WRONG'}]")
                else:
                    total += 1
                    print(f"  Col {col:2d}: TIMEOUT (got {len(rx)} bytes)")

print(f"\nDone: {correct} / {total} correct ({100.0 * correct / total:.2f}%)")