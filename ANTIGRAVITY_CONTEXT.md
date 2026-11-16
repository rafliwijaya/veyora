# ANTIGRAVITY_CONTEXT.md — Panduan Konteks Proyek Veyora untuk AI Assistant

## 1. Gambaran Umum Proyek & Konteks Akademik
- **Nama Aplikasi:** **Veyora** (*Your Body. Your Rhythm.*)
- **Tujuan Aplikasi:** Aplikasi mobile *offline-first* berbasis Flutter untuk memantau detak jantung (BPM), mengekstraksi parameter variabilitas denyut nadi (PRV/HRV) menggunakan kamera belakang dan lampu kilat (*torch*) smartphone (**Photoplethysmography / PPG**), mengklasifikasikan tingkat stres secara lokal (*on-device*) menggunakan model **Random Forest**, serta menyediakan intervensi relaksasi **Box Breathing (4-4-4-4)**.
- **Target Publikasi:** Artikel Jurnal Ilmiah SINTA (format IMRAD: Pendahuluan, Kajian Literatur, Metodologi Penelitian, Hasil dan Pembahasan, Kesimpulan).
- **Kebaruan Utama (Research Gap & Contribution):**
  1. Arsitektur **100% *on-device* (*offline-first*)**: Tidak mengirim data biometrik mentah ke server cloud; menjaga privasi dan bekerja tanpa koneksi internet.
  2. **Native Binary Random Forest Inference di Dart**: Mengonversi model `scikit-learn` (`.pkl`) menjadi struktur pohon biner datar (`assets/models/stress_forest.bin`) dan menjalankannya langsung di Dart tanpa *Python runtime*.
  3. **Physiological Artifact Filtering & Domain Adaptation**: Mengatasi *motion artifact* kamera jari dan menjembatani perbedaan distribusi antara HRV berbasis ECG laboratorium (**SWELL-KW**) dengan PRV kamera smartphone.
  4. **Intervensi Terpadu**: Panduan relaksasi visual & haptik *Box Breathing* langsung setelah deteksi stres.

---

## 2. Struktur Direktori & File Kunci

```text
veyora/
├── assets/
│   ├── images/
│   │   ├── heart.png
│   │   └── veyora-main.png
│   └── models/
│       ├── stress_forest.bin     # 200 pohon keputusan Random Forest hasil konversi dari .pkl (~4.85 MB)
│       └── scaler.json           # Parameter mean & scale StandardScaler dari dataset SWELL-KW
├── lib/
│   ├── main.dart                 # Entry point, pre-load SQLite & model ML, MainNavigationScaffold (4 tab)
│   ├── models/
│   │   └── measurement.dart      # Data model Measurement & mapping SQLite
│   ├── screens/
│   │   ├── splash_screen.dart    # Layar pembuka aplikasi
│   │   ├── home_screen.dart      # Dashboard beranda, metrik HRV terakhir, akses cepat
│   │   ├── measure_screen.dart   # Akuisisi kamera PPG 60 detik, live waveform, bottom sheet hasil AI
│   │   ├── breathing_screen.dart # Modul latihan napas Box Breathing 4-4-4-4 + haptic feedback
│   │   ├── history_screen.dart   # Grafik tren BPM/RMSSD (fl_chart) & daftar riwayat SQLite
│   │   └── run_tracker_screen.dart # Fitur pelacak lari GPS (geolocator)
│   ├── services/
│   │   ├── ppg_processor.dart    # Pipeline DSP: detrending, bandpass filter, peak detection, artifact filter, ekstraksi PRV
│   │   ├── stress_classifier.dart# Parser biner stress_forest.bin, domain adaptation, StandardScaler, voting 200 pohon
│   │   └── database_service.dart # Layanan CRUD database lokal SQLite (veyora_measurements.db)
│   ├── theme/
│   │   ├── app_colors.dart
│   │   └── app_theme.dart
│   └── widgets/
│       ├── blue_highlight_card.dart
│       ├── glassmorphism_card.dart # Kartu translucent ringan (tanpa BackdropFilter demi 60-120 FPS)
│       ├── ppg_waveform_widget.dart
│       └── status_badge.dart
└── pubspec.yaml
```

---

## 3. Spesifikasi Teknis Implementasi (Fakta Kode Sumber)

> **Aturan untuk AI:** Saat membantu menulis Metodologi atau Hasil, **WAJIB** merujuk angka dan logika aktual dari kode di bawah ini agar tidak terjadi kontradiksi dengan aplikasi.

### A. Akuisisi Kamera (`lib/screens/measure_screen.dart`)
- **Durasi Pengukuran:** `totalSeconds = 60` detik.
- **Konfigurasi Kamera:** Kamera belakang (`CameraLensDirection.back`), `ResolutionPreset.low`, `ImageFormatGroup.yuv420`, `FlashMode.torch`, `ExposureMode.locked`, `FocusMode.locked`.
- **Ekstraksi Sinyal:** Mengambil rata-rata nilai luminansi (`avgY`) dari `image.planes[0].bytes` (Plane Y format YUV420) dengan `step = 4`.
- **Deteksi Jari:** Jari dianggap menutupi lensa & flash apabila `avgY > 40.0`.
- **Mode Fallback:** Terdapat `_startSimulatedPpgStream()` untuk pengujian pada emulator yang tidak memiliki kamera fisik.

### B. Pemrosesan Sinyal Digital (`lib/services/ppg_processor.dart`)
Class: `PpgProcessor`, Output: `PpgResult`.
1. **Estimasi FPS Dinamis (`estimateFps`):** Dihitung dari nilai median selisih waktu antar-frame (`1000.0 / medianDt`, default `30.0` FPS). Minimal butuh 90 sampel (~3 detik) sebelum memproses.
2. **Detrending (`_detrend`):** Menghilangkan tren linier (*least-squares linear detrending*) untuk menstabilkan garis dasar sinyal.
3. **Bandpass Filtering (`_butterworthBandpass`):** Rentang cut-off `0.75 Hz – 2.8 Hz` (setara 45–168 BPM) yang diimplementasikan menggunakan selisih dua *moving average* (*low-pass window* `(fs / highCut).round().clamp(2, 10)` dan *baseline high-pass window* `(fs / lowCut).round().clamp(15, 60)`).
4. **Deteksi Puncak Sistolik (`_detectPeaks`):** Ambang batas adaptif `mean + 0.3 * std`, dengan *refractory period* minimal `minDistance = (fs * 0.35).round()` (~350 ms, batas atas ~171 BPM).
5. **Filter Rentang Fisiologis & Artefak Gerakan (`_filterArtifactIbis`):**
   - Interval mentah (IBI) hanya diterima pada rentang `350 ms <= dt <= 1400 ms` (42–171 BPM).
   - *Moving Tolerance Filter*: Mengambil nilai median IBI sebagai jangkar, lalu menolak interval yang menyimpang **> 28%** dari median (`(val - median).abs() / median <= 0.28`) akibat goyangan jari.
   - Selisih berturutan (`successiveDiffs`) untuk perhitungan RMSSD & pNN50 dibatasi `< 120.0 ms` agar fluktuasi artefak tidak membuat RMSSD melonjak tak wajar (>100 ms).
6. **Ekstraksi Fitur:**
   - `meanRR` = rata-rata `cleanIbis` (ms)
   - `bpm` = `60000.0 / meanRR`
   - `sdnn` = standar deviasi sampel `cleanIbis`
   - `rmssd` = $\sqrt{\frac{1}{N} \sum (\Delta NN_i)^2}$ (fallback `35.0` jika kosong)
   - `pnn50` = persentase $|\Delta NN_i| > 50\text{ ms}$
   - `lfHfRatio` = `((sdnn / rmssd) * 0.9).clamp(0.5, 4.5)`

### C. Klasifikasi Random Forest On-Device (`lib/services/stress_classifier.dart`)
Class: `StressClassifier`, Output: `StressClassificationResult`.
- **Dataset Pelatihan Model:** **SWELL-KW** (klasifikasi biner: Kelas `0 = Rileks/No Stress`, Kelas `1 = Stres`).
- **8 Fitur Input (Urutan Ketat):** `['HR', 'MEAN_RR', 'SDRR', 'RMSSD', 'pNN50', 'LF_HF', 'SD1', 'SD2']`.
  - Fitur non-linear Poincaré `SD1` dan `SD2` dihitung dari `adaptedRmssd` dan `clampedSdnn`:
    - `SD1 = adaptedRmssd / sqrt(2.0)`
    - `SD2 = sqrt(max(10.0, 2.0 * clampedSdnn^2 - 0.5 * adaptedRmssd^2))`
- **Format Biner `assets/models/stress_forest.bin`:**
  - Header 804 byte: `0..3` = `_nTrees` (`uint32` little-endian = `200`), `4..803` = `_treeSizes` (`200 * uint32` little-endian, total node across trees = `373.714`).
  - Array datar lanjutan: `_features` (`int8`, nilai `-1` menandakan *leaf node*), `_thresholds` (`float64`, pada *leaf node* berisi kelas prediksi `0.0` atau `1.0`), `_leftChildren` (`int16`), `_rightChildren` (`int16`).
  - *Catatan Teknis Memory Alignment:* Array `thresholds`, `leftChildren`, dan `rightChildren` disalin ke `Uint8List.fromList(...)` sebelum dibuatkan `TypedData` view untuk mencegah *unaligned memory crash* di perangkat ARM.
- **Adaptasi Domain (`_adaptRmssdToModelDomain`):**
  - Distribusi RMSSD pada SWELL-KW (berbasis ECG) berada di rentang sempit `5.5 – 26.6 ms` (mean `14.98 ms`). Sementara kamera PPG pada kondisi rileks sering menghasilkan RMSSD `>= 35 ms`. Tanpa adaptasi, nilai tinggi tersebut akan menjadi Z-score ekstrem (`Z > +5` s.d. `+29`) dan jatuh ke cabang *outlier* kelas stres.
  - Fungsi pemetaan di kode:
    - `realRmssd >= 35.0` $\rightarrow$ `14.0 ms` (zona *no-stress* SWELL-KW)
    - `22.0 <= realRmssd < 35.0` $\rightarrow$ `13.0 + (realRmssd - 22.0) / 13.0 * 1.5`
    - `12.0 <= realRmssd < 22.0` $\rightarrow$ `15.5 + (22.0 - realRmssd) / 10.0 * 2.0`
    - `realRmssd < 12.0` $\rightarrow$ `9.5 ms` (stres berat)
- **Normalisasi & Kategori Output:**
  - Z-score `(rawFeatures[i] - scalerMeans[i]) / scalerScales[i]` (sesuai `assets/models/scaler.json`).
  - Voting mayoritas 200 pohon menghasilkan `stressScore = (votesClass1 / 200) * 100.0`:
    - `< 35.0` $\rightarrow$ `'Rileks'`
    - `35.0 .. 65.0` $\rightarrow$ `'Stres Sedang'`
    - `> 65.0` $\rightarrow$ `'Stres Tinggi'`

### D. Penyimpanan Lokal SQLite (`lib/services/database_service.dart`)
- Menggunakan `sqflite` dengan nama database `veyora_measurements.db` (versi 1).
- Tabel `measurements`: `id` (PK autoincrement), `timestamp` (ISO8601), `bpm`, `rmssd`, `sdnn`, `pnn50`, `lf_hf_ratio`, `stress_status`, `stress_confidence`, `post_breathing` (integer 0/1).

### E. Modul Relaksasi & Performa UI
- **Box Breathing (`lib/screens/breathing_screen.dart`):** 4 fase (`inhale`, `holdIn`, `exhale`, `holdOut`) masing-masing 4 detik dengan animasi skala dan `HapticFeedback.mediumImpact()`.
- **Optimasi Rendering 60 FPS:** `GlassmorphismCard` tidak menggunakan `BackdropFilter` blur berat (diganti permukaan translusen `alpha: 0.88` + dual `BoxShadow`). Area grafik (`fl_chart`) di `history_screen.dart` dan komponen hero di `home_screen.dart` dibungkus `RepaintBoundary` serta `cacheWidth`/`cacheHeight` pada aset gambar.

---

## 4. Desain Evaluasi untuk Artikel Jurnal
Jika tim meminta bantuan untuk membuat skrip pengujian, grafik, atau menulis Bab 3 & Bab 4, gunakan pembagian peran dataset berikut:
1. **Validasi Sinyal PPG (BPM):** Menggunakan **Dataset Publik Welltory PPG** (membandingkan hasil algoritma `PpgProcessor` terhadap nilai *ground truth* Welltory menggunakan **MAE** dan **Korelasi Pearson $r$**).
2. **Validasi Klasifikasi Stres (AI):** Menggunakan **Dataset Benchmark SWELL-KW** (mengevaluasi model Random Forest 200 pohon menggunakan **Confusion Matrix**, **Accuracy**, **Precision**, **Recall**, **F1-Score**, dan **Feature Importance**).
3. **Evaluasi Komputasi On-Device:** Mengukur ukuran file biner (`stress_forest.bin`), waktu muat model (*load time*), latensi inferensi per prediksi (`< 2 ms`), serta skenario pengujian sebelum vs sesudah penerapan *artifact filter* dan *domain adaptation*.
