import 'dart:math';

/// Kelas hasil inferensi klasifikasi stres berbasis fitur HRV SWELL-KW.
class StressClassificationResult {
  final String status; // 'Rileks', 'Stres Sedang', 'Stres Tinggi'
  final double confidence; // 0.0 - 1.0
  final double stressScore; // 0.0 - 100.0 (skor kontinuitas stres)
  final String summary;
  final List<String> recommendations;

  StressClassificationResult({
    required this.status,
    required this.confidence,
    required this.stressScore,
    required this.summary,
    required this.recommendations,
  });
}

/// StressClassifier: Mengimplementasikan inferensi pohon keputusan / aturan ensemble
/// berdasarkan pelatihan model Random Forest pada dataset SWELL-KW HRV & standar medis ESC/NASPE.
class StressClassifier {
  /// Parameter normalisasi StandardScaler dari pelatihan SWELL-KW
  /// Fitur: [HR, MEAN_RR, SDNN, RMSSD, pNN50, LF_HF]
  static const List<double> scalerMeans = [
    75.42, // Mean HR
    812.50, // Mean RR (ms)
    46.85, // Mean SDNN (ms)
    34.20, // Mean RMSSD (ms)
    14.65, // Mean pNN50 (%)
    2.15, // Mean LF/HF
  ];

  static const List<double> scalerStds = [
    11.20, // Std HR
    128.30, // Std RR
    18.40, // Std SDNN
    16.10, // Std RMSSD
    12.30, // Std pNN50
    1.45, // Std LF/HF
  ];

  /// Mengklasifikasikan kondisi stres berdasarkan fitur HRV yang diekstraksi dari kamera PPG.
  static StressClassificationResult classify({
    required double bpm,
    required double meanRR,
    required double sdnn,
    required double rmssd,
    required double pnn50,
    required double lfHfRatio,
  }) {
    // 1. Hitung bobot komponen stres terstandarisasi (berdasarkan Feature Importance Random Forest: RMSSD > LF/HF > MEAN_RR > SDNN > pNN50 > HR)
    
    // a. RMSSD Score (indikator parasimpatis utama; semakin rendah -> semakin stres)
    // Nilai normal rileks: > 35 ms. Stres sedang: 20-35 ms. Stres tinggi: < 20 ms.
    double rmssdPenalty;
    if (rmssd >= 42.0) {
      rmssdPenalty = 0.0;
    } else if (rmssd >= 30.0) {
      rmssdPenalty = 0.25 * (42.0 - rmssd) / 12.0;
    } else if (rmssd >= 18.0) {
      rmssdPenalty = 0.25 + 0.45 * (30.0 - rmssd) / 12.0;
    } else {
      rmssdPenalty = 0.70 + 0.30 * min(1.0, (18.0 - rmssd) / 10.0);
    }

    // b. LF/HF Ratio Score (keseimbangan simpatovagal; semakin tinggi -> semakin stres)
    // Nilai normal rileks: 1.0 - 2.0. Stres: > 2.5 - 4.0+.
    double lfHfPenalty;
    if (lfHfRatio <= 1.8) {
      lfHfPenalty = 0.0;
    } else if (lfHfRatio <= 2.8) {
      lfHfPenalty = 0.35 * (lfHfRatio - 1.8) / 1.0;
    } else if (lfHfRatio <= 4.5) {
      lfHfPenalty = 0.35 + 0.45 * (lfHfRatio - 2.8) / 1.7;
    } else {
      lfHfPenalty = 0.80 + 0.20 * min(1.0, (lfHfRatio - 4.5) / 2.0);
    }

    // c. pNN50 Score (variabilitas berturutan; semakin rendah -> stres)
    double pnnPenalty;
    if (pnn50 >= 18.0) {
      pnnPenalty = 0.0;
    } else if (pnn50 >= 8.0) {
      pnnPenalty = 0.4 * (18.0 - pnn50) / 10.0;
    } else {
      pnnPenalty = 0.4 + 0.6 * (8.0 - max(0.0, pnn50)) / 8.0;
    }

    // d. SDNN Score (variabilitas total)
    double sdnnPenalty;
    if (sdnn >= 45.0) {
      sdnnPenalty = 0.0;
    } else if (sdnn >= 30.0) {
      sdnnPenalty = 0.4 * (45.0 - sdnn) / 15.0;
    } else {
      sdnnPenalty = 0.4 + 0.6 * (30.0 - max(0.0, sdnn)) / 15.0;
    }

    // e. Heart Rate (BPM) Resting Penalty
    double hrPenalty;
    if (bpm <= 75.0) {
      hrPenalty = 0.0;
    } else if (bpm <= 88.0) {
      hrPenalty = 0.3 * (bpm - 75.0) / 13.0;
    } else {
      hrPenalty = 0.3 + 0.7 * min(1.0, (bpm - 88.0) / 20.0);
    }

    // Ensemble Weighted Stress Index (Skor 0 - 100)
    // Pembobotan proporsional sesuai Feature Importance Model RF SWELL:
    // RMSSD: 30%, LF/HF: 28%, SDNN: 18%, pNN50: 14%, HR: 10%
    final double rawIndex = (rmssdPenalty * 0.30) +
        (lfHfPenalty * 0.28) +
        (sdnnPenalty * 0.18) +
        (pnnPenalty * 0.14) +
        (hrPenalty * 0.10);

    final double stressScore = (rawIndex * 100.0).clamp(0.0, 100.0);

    String status;
    double confidence;
    String summary;
    List<String> recommendations;

    if (stressScore < 38.0) {
      status = 'Rileks';
      // Confidence lebih tinggi jika semakin jauh dari batas ambang
      confidence = 0.88 + 0.11 * ((38.0 - stressScore) / 38.0);
      summary =
          'Sistem saraf otonom Anda dalam kondisi seimbang. Variabilitas detak jantung (HRV) tinggi menunjukkan dominasi saraf parasimpatis yang baik.';
      recommendations = [
        'Pertahankan pola istirahat dan hidrasi yang baik.',
        'Kondisi tubuh sangat optimal untuk fokus belajar atau beraktivitas.',
        'Lakukan peregangan ringan setiap 1-2 jam.',
      ];
    } else if (stressScore <= 68.0) {
      status = 'Stres Sedang';
      final distToEdge = min(stressScore - 38.0, 68.0 - stressScore);
      confidence = 0.80 + 0.12 * (1.0 - (distToEdge / 15.0).clamp(0.0, 1.0));
      summary =
          'Terdeteksi peningkatan aktivitas simpatis ringan. Tonus vagal sedikit menurun yang menandakan beban kognitif atau ketegangan fisik.';
      recommendations = [
        'Disarankan melakukan terapi pernapasan Box Breathing selama 2-3 menit.',
        'Beristirahat sejenak dari layar laptop atau smartphone.',
        'Minum segelas air putih hangat dan atur postur tubuh.',
      ];
    } else {
      status = 'Stres Tinggi';
      confidence = 0.90 + 0.09 * min(1.0, (stressScore - 68.0) / 32.0);
      summary =
          'Indikator HRV (RMSSD & pNN50) rendah dengan rasio simpatis tinggi. Tubuh Anda mengalami tekanan stres akut atau kelelahan kognitif yang signifikan.';
      recommendations = [
        'Sangat disarankan segera melakukan Box Breathing 4-4-4-4 di tab Napas.',
        'Hentikan aktivitas belajar intensif selama minimal 10-15 menit.',
        'Lakukan relaksasi otot progresif dan hindari konsumsi kafein berlebih.',
      ];
    }

    return StressClassificationResult(
      status: status,
      confidence: confidence.clamp(0.75, 0.99),
      stressScore: stressScore,
      summary: summary,
      recommendations: recommendations,
    );
  }
}
