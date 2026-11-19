"""
Evaluasi Bab 4.3: Performa Model Klasifikasi Random Forest Biner (Dataset SWELL-KW)
Mengevaluasi langsung file biner `assets/models/stress_forest.bin` dan `assets/models/scaler.json`
yang tertanam pada aplikasi Flutter Veyora terhadap data uji SWELL-KW (`test.csv`).

Output:
  - evaluation/results/tabel_4_2_rf_metrics.csv
  - evaluation/results/gambar_4_4_confusion_matrix.png
  - evaluation/results/gambar_4_5_feature_importance.png
"""

import json
import os
import struct
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import (
    accuracy_score,
    precision_score,
    recall_score,
    f1_score,
    confusion_matrix,
    classification_report,
)

sns.set_theme(style="whitegrid")
plt.rcParams["font.size"] = 11

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(BASE_DIR)
RESULTS_DIR = os.path.join(BASE_DIR, "results")
os.makedirs(RESULTS_DIR, exist_ok=True)

BIN_PATH = os.path.join(REPO_ROOT, "assets", "models", "stress_forest.bin")
SCALER_PATH = os.path.join(REPO_ROOT, "assets", "models", "scaler.json")

# Path default test.csv & pkl relatif terhadap folder kerja proyek
DEFAULT_TEST_PATHS = [
    os.path.join(BASE_DIR, "data", "swell", "test.csv"),
    os.path.join(REPO_ROOT, "..", "hrv dataset", "hrv dataset", "data", "final", "test.csv"),
    os.path.join(REPO_ROOT, "..", "hrv dataset", "data", "final", "test.csv"),
]
DEFAULT_PKL_PATHS = [
    os.path.join(REPO_ROOT, "..", "poc_bpm_web", "model_mL", "random_forest_stress_model.pkl"),
    os.path.join(BASE_DIR, "data", "swell", "random_forest_stress_model.pkl"),
]


def find_existing_path(candidates):
    for p in candidates:
        norm = os.path.normpath(p)
        if os.path.exists(norm):
            return norm
    return None


def load_binary_forest(bin_path):
    with open(bin_path, "rb") as f:
        raw = f.read()

    n_trees = struct.unpack_from("<I", raw, 0)[0]
    tree_sizes = np.frombuffer(raw, dtype=np.uint32, count=n_trees, offset=4)
    total_nodes = int(np.sum(tree_sizes))

    feat_offset = 804
    thresh_offset = feat_offset + total_nodes
    left_offset = thresh_offset + total_nodes * 8
    right_offset = left_offset + total_nodes * 2

    features = np.frombuffer(raw, dtype=np.int8, count=total_nodes, offset=feat_offset)
    thresholds = np.frombuffer(raw, dtype=np.float64, count=total_nodes, offset=thresh_offset)
    left_children = np.frombuffer(raw, dtype=np.int16, count=total_nodes, offset=left_offset)
    right_children = np.frombuffer(raw, dtype=np.int16, count=total_nodes, offset=right_offset)

    return n_trees, tree_sizes, features, thresholds, left_children, right_children


def predict_binary_forest_batch(X_scaled, forest_tuple):
    n_trees, tree_sizes, features, thresholds, left_children, right_children = forest_tuple
    n_samples = X_scaled.shape[0]
    votes_class1 = np.zeros(n_samples, dtype=np.int32)

    tree_offset = 0
    for t in range(n_trees):
        size = int(tree_sizes[t])
        nodes = np.zeros(n_samples, dtype=np.int32)
        active = np.ones(n_samples, dtype=bool)

        while np.any(active):
            act_idx = np.where(active)[0]
            cur_nodes = tree_offset + nodes[act_idx]
            feats = features[cur_nodes]

            is_leaf = feats == -1
            if np.any(is_leaf):
                leaf_samples = act_idx[is_leaf]
                leaf_vals = thresholds[cur_nodes[is_leaf]]
                votes_class1[leaf_samples[leaf_vals >= 0.5]] += 1
                active[leaf_samples] = False

            is_split = ~is_leaf
            if np.any(is_split):
                split_samples = act_idx[is_split]
                split_nodes = cur_nodes[is_split]
                split_feats = feats[is_split]
                vals = X_scaled[split_samples, split_feats]
                go_left = vals <= thresholds[split_nodes]
                nodes[split_samples[go_left]] = left_children[split_nodes[go_left]]
                nodes[split_samples[~go_left]] = right_children[split_nodes[~go_left]]

        tree_offset += size

    probs = votes_class1 / float(n_trees)
    preds = (probs >= 0.5).astype(np.int32)
    return preds, probs


def main():
    with open(SCALER_PATH, "r", encoding="utf-8") as f:
        scaler_cfg = json.load(f)

    feature_names = scaler_cfg["features"]
    means = np.array(scaler_cfg["mean"], dtype=np.float64)
    scales = np.array(scaler_cfg["scale"], dtype=np.float64)

    test_path = find_existing_path(DEFAULT_TEST_PATHS)
    if test_path is None:
        print("❌ File test.csv SWELL-KW tidak ditemukan.")
        print("   Letakkan test.csv di evaluation/data/swell/test.csv atau ../hrv dataset/data/final/test.csv")
        return

    print(f"Memuat data uji SWELL-KW dari: {test_path}")
    df_test = pd.read_csv(test_path)

    # Pemetaan label biner: no stress -> 0 (Rileks), interruption / time pressure -> 1 (Stres)
    y_true = np.where(df_test["condition"].str.lower() == "no stress", 0, 1)
    X_raw = df_test[feature_names].values.astype(np.float64)
    X_scaled = (X_raw - means) / scales

    print(f"Memuat model biner Veyora: {BIN_PATH}")
    forest = load_binary_forest(BIN_PATH)
    print(f"Menjalankan inferensi pada {len(y_true):,} sampel uji melalui {forest[0]} pohon biner...")
    y_pred, _ = predict_binary_forest_batch(X_scaled, forest)

    acc = accuracy_score(y_true, y_pred)
    prec = precision_score(y_true, y_pred)
    rec = recall_score(y_true, y_pred)
    f1 = f1_score(y_true, y_pred)
    cm = confusion_matrix(y_true, y_pred)

    print("\n" + "=" * 60)
    print("HASIL EVALUASI RANDOM FOREST (SWELL-KW TEST SET)")
    print(f"  Accuracy  : {acc * 100:.2f}%")
    print(f"  Precision : {prec * 100:.2f}%")
    print(f"  Recall    : {rec * 100:.2f}%")
    print(f"  F1-Score  : {f1 * 100:.2f}%")
    print("\nLaporan Per Kelas:")
    print(classification_report(y_true, y_pred, target_names=["Rileks (0)", "Stres (1)"], digits=4))
    print("=" * 60)

    # Simpan Tabel 4.2
    report_dict = classification_report(y_true, y_pred, target_names=["Rileks", "Stres"], output_dict=True)
    df_tbl = pd.DataFrame([
        {
            "Kelas": "Rileks (no stress)",
            "Precision": round(report_dict["Rileks"]["precision"], 4),
            "Recall": round(report_dict["Rileks"]["recall"], 4),
            "F1-Score": round(report_dict["Rileks"]["f1-score"], 4),
            "Support": int(report_dict["Rileks"]["support"]),
        },
        {
            "Kelas": "Stres (interruption + time pressure)",
            "Precision": round(report_dict["Stres"]["precision"], 4),
            "Recall": round(report_dict["Stres"]["recall"], 4),
            "F1-Score": round(report_dict["Stres"]["f1-score"], 4),
            "Support": int(report_dict["Stres"]["support"]),
        },
        {
            "Kelas": "Keseluruhan (Weighted / Overall)",
            "Precision": round(report_dict["weighted avg"]["precision"], 4),
            "Recall": round(report_dict["weighted avg"]["recall"], 4),
            "F1-Score": round(report_dict["weighted avg"]["f1-score"], 4),
            "Support": int(len(y_true)),
        },
    ])
    df_tbl["Accuracy_Overall"] = round(acc, 4)
    tbl_path = os.path.join(RESULTS_DIR, "tabel_4_2_rf_metrics.csv")
    df_tbl.to_csv(tbl_path, index=False)
    print(f"  Tabel 4.2 tersimpan: {tbl_path}")

    # Gambar 4.4: Confusion Matrix
    plt.figure(figsize=(6.2, 5.2))
    sns.heatmap(
        cm,
        annot=True,
        fmt=",d",
        cmap="Blues",
        xticklabels=["Prediksi: Rileks", "Prediksi: Stres"],
        yticklabels=["Aktual: Rileks", "Aktual: Stres"],
        annot_kws={"size": 12, "weight": "bold"},
    )
    plt.title(f"Confusion Matrix Model Random Forest Biner (Acc: {acc * 100:.2f}%)", pad=12)
    plt.tight_layout()
    cm_path = os.path.join(RESULTS_DIR, "gambar_4_4_confusion_matrix.png")
    plt.savefig(cm_path, dpi=300)
    plt.close()
    print(f"  Gambar 4.4 tersimpan: {cm_path}")

    # Gambar 4.5: Feature Importance (dari pkl jika tersedia, atau frekuensi split pada biner)
    pkl_path = find_existing_path(DEFAULT_PKL_PATHS)
    if pkl_path:
        import joblib
        rf_model = joblib.load(pkl_path)
        importances = rf_model.feature_importances_
        imp_title = "Feature Importance Model Random Forest (Gini Importance)"
    else:
        feats_arr = forest[2]
        valid_feats = feats_arr[feats_arr >= 0]
        counts = np.bincount(valid_feats, minlength=len(feature_names))
        importances = counts / np.sum(counts)
        imp_title = "Proporsi Penggunaan Fitur Split pada 200 Pohon Biner"

    idx_sorted = np.argsort(importances)
    plt.figure(figsize=(8, 4.8))
    plt.barh(
        [feature_names[i] for i in idx_sorted],
        importances[idx_sorted],
        color="#3B82F6",
        edgecolor="#1D4ED8",
    )
    plt.xlabel("Skor Kepentingan Fitur (Relative Importance)")
    plt.title(imp_title)
    plt.tight_layout()
    fi_path = os.path.join(RESULTS_DIR, "gambar_4_5_feature_importance.png")
    plt.savefig(fi_path, dpi=300)
    plt.close()
    print(f"  Gambar 4.5 tersimpan: {fi_path}")


if __name__ == "__main__":
    main()
