"""
Evaluasi Bab 4.2: Akurasi Ekstraksi Sinyal PPG & Estimasi BPM (Dataset Welltory)
Mengimplementasikan algoritma PpgProcessor (1:1 port dari lib/services/ppg_processor.dart)
dan membandingkannya dengan ground truth Polar H10 (RR.txt) pada dataset Welltory.

Output:
  - evaluation/results/tabel_4_1_welltory_bpm.csv
  - evaluation/results/gambar_4_2_sinyal_ppg.png
  - evaluation/results/gambar_4_3_korelasi_welltory.png
"""

import io
import math
import os
import urllib.request
import numpy as np
import pandas as pd
import scipy.stats
import matplotlib.pyplot as plt
import seaborn as sns

sns.set_theme(style="whitegrid", palette="muted")
plt.rcParams["font.size"] = 11

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(BASE_DIR)
DATA_DIR = os.path.join(BASE_DIR, "data", "welltory-ppg-dataset-master", "data")
RESULTS_DIR = os.path.join(BASE_DIR, "results")
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(RESULTS_DIR, exist_ok=True)


# ==============================================================================
# 1. PORTING 1:1 ALGORITMA PpgProcessor (lib/services/ppg_processor.dart)
# ==============================================================================

def estimate_fps(timestamps_ms):
    if len(timestamps_ms) < 10:
        return 30.0
    diffs = []
    for i in range(1, len(timestamps_ms)):
        dt = timestamps_ms[i] - timestamps_ms[i - 1]
        if 0 < dt < 200:
            diffs.append(dt)
    if not diffs:
        return 30.0
    diffs.sort()
    median_dt = diffs[len(diffs) // 2]
    return 1000.0 / median_dt


def detrend_linear(signal):
    n = len(signal)
    x = np.arange(n, dtype=np.float64)
    y = np.asarray(signal, dtype=np.float64)
    sum_x = np.sum(x)
    sum_y = np.sum(y)
    sum_xy = np.sum(x * y)
    sum_x2 = np.sum(x * x)
    denom = n * sum_x2 - sum_x * sum_x
    if abs(denom) < 1e-12:
        return y - np.mean(y)
    slope = (n * sum_xy - sum_x * sum_y) / denom
    intercept = (sum_y - slope * sum_x) / n
    return y - (slope * x + intercept)


def moving_average(data, window):
    n = len(data)
    result = np.zeros(n, dtype=np.float64)
    half = window // 2
    for i in range(n):
        start = max(0, i - half)
        end = min(n, i + half + 1)
        result[i] = np.mean(data[start:end])
    return result


def butterworth_bandpass_approx(signal, fs, low_cut=0.75, high_cut=2.8):
    low_pass_window = int(max(2, min(10, round(fs / high_cut))))
    high_pass_window = int(max(15, min(60, round(fs / low_cut))))
    smoothed = moving_average(signal, low_pass_window)
    baseline = moving_average(signal, high_pass_window)
    return smoothed - baseline


def detect_peaks(signal, fs):
    peaks = []
    min_distance = int(round(fs * 0.35))
    mean_val = float(np.mean(signal))
    std_val = float(np.std(signal, ddof=1)) if len(signal) >= 2 else 0.0
    threshold = mean_val + 0.3 * std_val

    for i in range(1, len(signal) - 1):
        if signal[i] > signal[i - 1] and signal[i] > signal[i + 1] and signal[i] > threshold:
            if not peaks or (i - peaks[-1]) >= min_distance:
                peaks.append(i)
            elif signal[i] > signal[peaks[-1]]:
                peaks[-1] = i
    return peaks


def filter_artifact_ibis(raw_ibis):
    if len(raw_ibis) < 4:
        return raw_ibis
    sorted_ibis = sorted(raw_ibis)
    median = sorted_ibis[len(sorted_ibis) // 2]
    clean = [val for val in raw_ibis if abs(val - median) / median <= 0.28]
    return clean if len(clean) >= 3 else raw_ibis


def run_ppg_processor(signal, timestamps_ms):
    if len(signal) < 90:
        return None
    fps = estimate_fps(timestamps_ms)
    detrended = detrend_linear(signal)
    filtered = butterworth_bandpass_approx(detrended, fps, 0.75, 2.8)
    peaks = detect_peaks(filtered, fps)
    if len(peaks) < 4:
        return None

    raw_ibis = []
    for i in range(1, len(peaks)):
        dt = timestamps_ms[peaks[i]] - timestamps_ms[peaks[i - 1]]
        if 350.0 <= dt <= 1400.0:
            raw_ibis.append(dt)

    if len(raw_ibis) < 4:
        return None

    clean_ibis = filter_artifact_ibis(raw_ibis)
    if len(clean_ibis) < 3:
        return None

    mean_rr = float(np.mean(clean_ibis))
    bpm = 60000.0 / mean_rr
    duration_sec = (timestamps_ms[-1] - timestamps_ms[0]) / 1000.0

    return {
        "bpm": bpm,
        "mean_rr": mean_rr,
        "fps": fps,
        "duration_sec": duration_sec,
        "peak_count": len(peaks),
        "filtered_signal": filtered,
        "peaks": peaks,
        "detrended": detrended,
    }


# ==============================================================================
# 2. PENGAMBILAN DATASET WELLTORY (CACHE LOKAL + AUTO-DOWNLOAD GITHUB)
# ==============================================================================

def load_welltory_record(record_id):
    sub_str = f"subject_{record_id:02d}"
    sub_dir = os.path.join(DATA_DIR, sub_str)
    ppg_path = os.path.join(sub_dir, "PPG.csv")
    rr_path = os.path.join(sub_dir, "RR.txt")

    if os.path.exists(ppg_path) and os.path.exists(rr_path):
        df_ppg = pd.read_csv(ppg_path)
        with open(rr_path, "r", encoding="utf-8") as f:
            rr_list = [float(x) for x in f.read().strip().split()]
        return df_ppg, rr_list

    base_url = "https://raw.githubusercontent.com/Welltory/welltory-ppg-dataset/master/data/"
    url_ppg = f"{base_url}{sub_str}/PPG.csv"
    url_rr = f"{base_url}{sub_str}/RR.txt"
    headers = {"User-Agent": "Mozilla/5.0"}

    try:
        with urllib.request.urlopen(urllib.request.Request(url_ppg, headers=headers), timeout=15) as resp:
            ppg_text = resp.read().decode("utf-8")
        with urllib.request.urlopen(urllib.request.Request(url_rr, headers=headers), timeout=15) as resp:
            rr_text = resp.read().decode("utf-8")

        os.makedirs(sub_dir, exist_ok=True)
        with open(ppg_path, "w", encoding="utf-8") as f:
            f.write(ppg_text)
        with open(rr_path, "w", encoding="utf-8") as f:
            f.write(rr_text)

        df_ppg = pd.read_csv(io.StringIO(ppg_text))
        rr_list = [float(x) for x in rr_text.strip().split()]
        return df_ppg, rr_list
    except Exception as e:
        print(f"  [Skip] {sub_str} tidak dapat dimuat: {e}")
        return None, None


# ==============================================================================
# 3. EKSEKUSI EVALUASI & PEMBUATAN TABEL + GRAFIK BAB 4.2
# ==============================================================================

def main():
    print("Memulai Evaluasi Welltory PPG Dataset menggunakan PpgProcessor Veyora...")
    records = []
    sample_for_plot = None

    for rec_id in range(1, 25):
        df_ppg, rr_list = load_welltory_record(rec_id)
        if df_ppg is None or not rr_list:
            continue

        # Normalisasi nama kolom waktu dan kanal merah/luminansi
        time_col = "time" if "time" in df_ppg.columns else df_ppg.columns[0]
        timestamps_ms = df_ppg[time_col].values.astype(np.float64)

        # Pada kamera ponsel dengan flash, kanal Merah (R) atau Luminansi Y (0.299R+0.587G+0.114B)
        if {"R", "G", "B"}.issubset(df_ppg.columns):
            sig = (0.299 * df_ppg["R"].values + 0.587 * df_ppg["G"].values + 0.114 * df_ppg["B"].values)
            if np.std(sig) < 1e-4:
                sig = df_ppg["R"].values
        else:
            sig = df_ppg.iloc[:, 1].values

        res = run_ppg_processor(sig, timestamps_ms)
        if res is None:
            print(f"  [Skip] subject_{rec_id:02d}: sinyal tidak memenuhi ambang minimal.")
            continue

        # Ground truth Polar H10 (filter outlier RR dasar 350-1400 ms)
        valid_gt_rr = [x for x in rr_list if 350.0 <= x <= 1400.0]
        if not valid_gt_rr:
            valid_gt_rr = rr_list
        gt_bpm = 60000.0 / float(np.mean(valid_gt_rr))

        abs_err = abs(res["bpm"] - gt_bpm)
        records.append({
            "ID_Rekaman": f"subject_{rec_id:02d}",
            "Durasi_Detik": round(res["duration_sec"], 1),
            "FPS": round(res["fps"], 1),
            "BPM_Ground_Truth": round(gt_bpm, 2),
            "BPM_Estimasi_Veyora": round(res["bpm"], 2),
            "Error_Absolut_BPM": round(abs_err, 2),
        })

        if sample_for_plot is None:
            sample_for_plot = (f"subject_{rec_id:02d}", timestamps_ms, sig, res)

        print(f"  [OK] subject_{rec_id:02d}: GT={gt_bpm:.2f} bpm | Est={res['bpm']:.2f} bpm | Err={abs_err:.2f} bpm")

    if not records:
        print("Tidak ada data Welltory yang berhasil diproses. Periksa koneksi internet atau folder data.")
        return

    df_res = pd.DataFrame(records)
    mae = df_res["Error_Absolut_BPM"].mean()
    rmse = math.sqrt(np.mean((df_res["BPM_Estimasi_Veyora"] - df_res["BPM_Ground_Truth"]) ** 2))
    r_val, p_val = scipy.stats.pearsonr(df_res["BPM_Ground_Truth"], df_res["BPM_Estimasi_Veyora"])

    # Simpan Tabel 4.1
    csv_path = os.path.join(RESULTS_DIR, "tabel_4_1_welltory_bpm.csv")
    df_res.to_csv(csv_path, index=False)

    print("\n" + "=" * 60)
    print(f"RINGKASAN EVALUASI WELLTORY ({len(df_res)} Rekaman)")
    print(f"  Durasi Rata-rata : {df_res['Durasi_Detik'].mean():.1f} detik")
    print(f"  FPS Rata-rata    : {df_res['FPS'].mean():.1f} fps")
    print(f"  MAE              : {mae:.3f} BPM")
    print(f"  RMSE             : {rmse:.3f} BPM")
    print(f"  Korelasi Pearson : r = {r_val:.4f} (p = {p_val:.2e})")
    print(f"  Tabel tersimpan  : {csv_path}")
    print("=" * 60)

    # Gambar 4.2: Sinyal PPG Mentah vs Terfilter + Puncak Terdeteksi (10 detik pertama)
    if sample_for_plot is not None:
        sub_name, ts, raw_sig, res_plot = sample_for_plot
        t_sec = (ts - ts[0]) / 1000.0
        mask = t_sec <= 12.0
        peaks_in_window = [p for p in res_plot["peaks"] if t_sec[p] <= 12.0]

        fig, axes = plt.subplots(2, 1, figsize=(10, 5.5), sharex=True)
        axes[0].plot(t_sec[mask], raw_sig[mask], color="#64748B", linewidth=1.2)
        axes[0].set_title(f"Sinyal PPG Mentah Kamera Smartphone ({sub_name})")
        axes[0].set_ylabel("Intensitas")

        axes[1].plot(t_sec[mask], res_plot["filtered_signal"][mask], color="#2563EB", linewidth=1.5, label="Sinyal Terfilter (0.75-2.8 Hz)")
        axes[1].scatter(t_sec[peaks_in_window], res_plot["filtered_signal"][peaks_in_window], color="#EF4444", zorder=5, label="Puncak Sistolik")
        axes[1].set_title("Sinyal Hasil Bandpass Filter & Deteksi Puncak Adaptif PpgProcessor")
        axes[1].set_xlabel("Waktu (detik)")
        axes[1].set_ylabel("Amplitudo Terfilter")
        axes[1].legend(loc="upper right")

        plt.tight_layout()
        fig42_path = os.path.join(RESULTS_DIR, "gambar_4_2_sinyal_ppg.png")
        plt.savefig(fig42_path, dpi=300)
        plt.close()
        print(f"  Gambar 4.2 tersimpan: {fig42_path}")

    # Gambar 4.3: Scatter Plot Korelasi & Bland-Altman Plot
    gt = df_res["BPM_Ground_Truth"].values
    est = df_res["BPM_Estimasi_Veyora"].values
    means = (gt + est) / 2.0
    diffs = est - gt
    md = np.mean(diffs)
    sd = np.std(diffs, ddof=1) if len(diffs) > 1 else 0.0

    fig, axes = plt.subplots(1, 2, figsize=(11, 4.8))
    # Scatter
    axes[0].scatter(gt, est, color="#2563EB", alpha=0.8, s=55, edgecolors="white")
    lims = [min(gt.min(), est.min()) - 4, max(gt.max(), est.max()) + 4]
    axes[0].plot(lims, lims, "r--", linewidth=1.2, label="Garis Ideal (y = x)")
    axes[0].set_xlim(lims)
    axes[0].set_ylim(lims)
    axes[0].set_title(f"Korelasi Estimasi BPM vs Polar H10 (r = {r_val:.3f})")
    axes[0].set_xlabel("BPM Ground Truth (Polar H10)")
    axes[0].set_ylabel("BPM Estimasi Veyora")
    axes[0].legend()

    # Bland-Altman
    axes[1].scatter(means, diffs, color="#0EA5E9", alpha=0.8, s=55, edgecolors="white")
    axes[1].axhline(md, color="#1E293B", linestyle="-", linewidth=1.2, label=f"Mean Bias: {md:.2f}")
    axes[1].axhline(md + 1.96 * sd, color="#EF4444", linestyle="--", linewidth=1.1, label=f"+1.96 SD: {md + 1.96 * sd:.2f}")
    axes[1].axhline(md - 1.96 * sd, color="#EF4444", linestyle="--", linewidth=1.1, label=f"-1.96 SD: {md - 1.96 * sd:.2f}")
    axes[1].set_title("Bland-Altman Plot Kesesuaian BPM")
    axes[1].set_xlabel("Rata-rata BPM (Ground Truth & Estimasi)")
    axes[1].set_ylabel("Selisih (Estimasi - Ground Truth)")
    axes[1].legend(fontsize=9)

    plt.tight_layout()
    fig43_path = os.path.join(RESULTS_DIR, "gambar_4_3_korelasi_welltory.png")
    plt.savefig(fig43_path, dpi=300)
    plt.close()
    print(f"  Gambar 4.3 tersimpan: {fig43_path}")


if __name__ == "__main__":
    main()
