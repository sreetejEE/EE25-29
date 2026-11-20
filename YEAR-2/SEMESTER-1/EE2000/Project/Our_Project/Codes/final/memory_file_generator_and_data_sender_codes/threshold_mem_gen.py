#************Written by Sreetej*************
import json
import math
import pandas as pd
from pathlib import Path

ROOT_DIR = Path(r"C:\Users\vishw\Documents\Vibration Dataset")
SPEEDS = [50, 75, 100]

CLASS_FOLDERS = [
    "healthy 2",          # 0: HEALTHY
    "bearing bpfo 2",     # 1: BPFO
    "bearing bpfi 2",     # 2: BPFI
    "stator short 1",     # 3: STATOR_SHORT
    "broken rotor bar",   # 4: BROKEN_ROTOR_BAR
]

BANDS = [
    (0, 500), (500, 1000), (1000, 1500), (1500, 2000), (2000, 2500),
    (2500, 3000), (3000, 3500), (3500, 4000), (4000, 4500), (4500, 5000),
]

FS = 10000
FFT_SIZE = 1024

# Must match MATLAB INT16_SCALE (16000.0) / xfft_0 scaling (256 for 16'h0155)
INT16_SCALE = 16000.0
XFFT_DIV    = 256.0
MAG_SCALE   = INT16_SCALE / XFFT_DIV  # 62.5

# ------------------------------------------------------------
# 1. Generate hann_1024_q15.mem (Symmetric n / (N - 1) to match np.hanning)
# ------------------------------------------------------------
with open("hann_1024_q15.mem", "w") as f:
    for n in range(FFT_SIZE):
        w = 0.5 * (1.0 - math.cos(2.0 * math.pi * n / (FFT_SIZE - 1)))
        q15 = min(32767, int(round(w * 32768.0)))
        f.write(f"{q15:04X}\n")

# ------------------------------------------------------------
# 2. Generate exp_lut.mem (512 entries: exp(-u) for u in [0, 8), Q0.16)
# ------------------------------------------------------------
with open("exp_lut.mem", "w") as f:
    for i in range(512):
        u = i / 64.0
        val = min(65535, int(round(65535.0 * math.exp(-u))))
        f.write(f"{val:04X}\n")

# ------------------------------------------------------------
# 3. Generate gauss_features.mem (450 entries) & decision_thresh.mem (9 entries)
# ------------------------------------------------------------
with open("gauss_features.mem", "w") as f_feat, open("decision_thresh.mem", "w") as f_th:
    for speed in SPEEDS:
        th_json = ROOT_DIR / str(speed) / "classification_test_results" / "three_channel_decision_thresholds.json"
        with open(th_json, "r", encoding="utf-8") as jf:
            th_cfg = json.load(jf)["channel_thresholds"]

        print(f"\nSpeed {speed}:")
        for ch in [1, 2, 3]:
            min_s = float(th_cfg[str(ch)]["min_score"])
            min_m = float(th_cfg[str(ch)]["min_margin"])
            status = th_cfg[str(ch)].get("status", "OK")
            print(f"  CH{ch}: min_score={min_s:.4f}, min_margin={min_m:.4f} ({status})")

            min_score_q4_16  = min(0xFFFFF, int(round(min_s * 65536.0)))
            min_margin_q4_16 = min(0xFFFFF, int(round(min_m * 65536.0)))
            th_word = (min_score_q4_16 << 20) | min_margin_q4_16
            f_th.write(f"{th_word:010X}\n")

            for folder in CLASS_FOLDERS:
                csv_path = ROOT_DIR / str(speed) / folder / f"thresholds_ch{ch}.csv"
                df = pd.read_csv(csv_path, index_col=0)
                med_row = df.loc["MEDIAN"]
                sig_row = df.loc["GAUSSIAN_SIGMA"]

                for low_hz, high_hz in BANDS:
                    f_col = f"{low_hz}_{high_hz}Hz_freq_Hz"
                    m_col = f"{low_hz}_{high_hz}Hz_mag"

                    # Frequency in Q10.6 bins
                    f_med_q10_6 = min(0xFFFF, int(round((float(med_row[f_col]) * FFT_SIZE / FS) * 64.0)))
                    f_sig_q10_6 = (float(sig_row[f_col]) * FFT_SIZE / FS) * 64.0
                    f_inv_sig   = 0 if f_sig_q10_6 == 0 else min(0xFFFFFF, int(round(1048576.0 / f_sig_q10_6)))

                    # Magnitude in Q16.0
                    m_med     = min(0xFFFF, int(round(float(med_row[m_col]) * MAG_SCALE)))
                    m_sig     = float(sig_row[m_col]) * MAG_SCALE
                    m_inv_sig = 0 if m_sig == 0 else min(0xFFFFFF, int(round(1048576.0 / m_sig)))

                    word = (f_med_q10_6 << 64) | (f_inv_sig << 40) | (m_med << 24) | m_inv_sig
                    f_feat.write(f"{word:020X}\n")

print("\nGenerated hann_1024_q15.mem, exp_lut.mem, gauss_features.mem, decision_thresh.mem")