# Panduan Menjalankan Skrip Evaluasi Jurnal Veyora (Bab 4)

Folder ini berisi skrip pengujian otomatis yang menghasilkan seluruh angka evaluasi, tabel `.csv`, dan grafik `.png` beresolusi tinggi (300 DPI) untuk **Bab 4 (Hasil dan Pembahasan)**.

---

## 1. Persiapan Environment Python

Pastikan Python 3.9+ telah terpasang, lalu instal dependensi berikut:

```bash
pip install numpy pandas scipy scikit-learn matplotlib seaborn joblib
```

---

## 2. Daftar Skrip Pengujian & Cara Menjalankan

### A. Evaluasi Sinyal PPG & Akurasi BPM (Bab 4.2 — Dataset Welltory)
Menguji algoritma `PpgProcessor` (porting 1:1 dari `lib/services/ppg_processor.dart`) terhadap nilai *ground truth* Polar H10 pada **Welltory PPG Dataset**. Skrip akan mengunduh data langsung dari GitHub Welltory dan menyimpannya ke `evaluation/data/welltory/`.

```bash
cd evaluation
python eval_welltory_ppg.py
```

**Output yang dihasilkan di `evaluation/results/`:**
- `tabel_4_1_welltory_bpm.csv` (Tabel 4.1: ID rekaman, durasi, FPS, BPM Ground Truth, BPM Estimasi, Error Absolut, plus ringkasan MAE, RMSE, dan Korelasi Pearson $r$)
- `gambar_4_2_sinyal_ppg.png` (Gambar 4.2: Sinyal PPG mentah vs terfilter + titik puncak sistolik)
- `gambar_4_3_korelasi_welltory.png` (Gambar 4.3: Scatter Plot Korelasi & Bland-Altman Plot)

---

### B. Evaluasi Model Random Forest Biner (Bab 4.3 — Dataset SWELL-KW)
Menguji **file biner asli** yang tertanam di aplikasi (`assets/models/stress_forest.bin` & `assets/models/scaler.json`) terhadap data uji SWELL-KW (`test.csv`).

> **Catatan Path Dataset:** Letakkan `test.csv` di `../hrv dataset/data/final/test.csv` atau `evaluation/data/swell/test.csv`.

```bash
cd evaluation
python eval_swell_rf.py
```

**Output yang dihasilkan di `evaluation/results/`:**
- `tabel_4_2_rf_metrics.csv` (Tabel 4.2: Accuracy, Precision, Recall, F1-Score per kelas & keseluruhan)
- `gambar_4_4_confusion_matrix.png` (Gambar 4.4: Confusion Matrix klasifikasi biner)
- `gambar_4_5_feature_importance.png` (Gambar 4.5: Grafik tingkat kepentingan 8 fitur HRV)

---

### C. Benchmark Komputasi On-Device & Studi Ablasi (Bab 4.4 — Dart/Flutter)
Mengukur ukuran file model biner, *load time* (30x pengulangan), *inference latency* (30x pengulangan), serta memverifikasi studi ablasi *artifact filter* dan *domain adaptation* (`_adaptRmssdToModelDomain`).

Jalankan dari root folder `veyora`:

```bash
flutter test test/benchmark_ondevice_test.dart
```
*(Catatan: Untuk pengukuran latensi asli di perangkat fisik Redmi Note 12 Android 15 mode `release`, jalankan aplikasi dengan `flutter run --release` atau ekstrak waktu dari log perangkat).*
