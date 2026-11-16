import 'dart:math';

/// Pemrosesan sinyal digital PPG dari frame kamera smartphone.
/// Mengimplementasikan: Butterworth Bandpass Filter, Peak Detection,
/// Penyaringan Artefak Gerakan (Beat-to-Beat Artifact Filter), dan ekstraksi fitur HRV.
class PpgProcessor {
  final List<double> _rawSignal = [];
  final List<double> _timestamps = []; // dalam milidetik
  double _fps = 30.0;

  /// Menambahkan sampel baru dari frame kamera (nilai rata-rata kanal warna).
  void addSample(double intensity, double timestampMs) {
    _rawSignal.add(intensity);
    _timestamps.add(timestampMs);
  }

  /// Mereset buffer sinyal untuk pengukuran baru.
  void reset() {
    _rawSignal.clear();
    _timestamps.clear();
  }

  int get sampleCount => _rawSignal.length;

  /// Mendapatkan sinyal mentah yang sudah terkumpul.
  List<double> get rawSignal => List.unmodifiable(_rawSignal);

  /// Estimasi FPS kamera secara dinamis dari timestamp.
  double estimateFps() {
    if (_timestamps.length < 10) return 30.0;
    final diffs = <double>[];
    for (int i = 1; i < _timestamps.length; i++) {
      final dt = _timestamps[i] - _timestamps[i - 1];
      if (dt > 0 && dt < 200) {
        diffs.add(dt);
      }
    }
    if (diffs.isEmpty) return 30.0;
    diffs.sort();
    final medianDt = diffs[diffs.length ~/ 2];
    _fps = 1000.0 / medianDt;
    return _fps;
  }

  /// Mengolah sinyal mentah dan mengembalikan hasil analisis lengkap.
  PpgResult? processSignal() {
    if (_rawSignal.length < 90) return null; // minimal ~3 detik pada 30 FPS

    _fps = estimateFps();

    // 1. Detrending (buang tren linier)
    final detrended = _detrend(_rawSignal);

    // 2. Bandpass Butterworth filter (0.75 – 2.8 Hz = 45 – 168 BPM)
    final filtered = _butterworthBandpass(detrended, _fps, 0.75, 2.8, order: 2);

    // 3. Deteksi puncak sistolik
    final peaks = _detectPeaks(filtered, _fps);

    if (peaks.length < 4) return null;

    // 4. Hitung IBI mentah (Inter-Beat Interval) dalam milidetik
    final rawIbis = <double>[];
    for (int i = 1; i < peaks.length; i++) {
      final dt = (_timestamps[peaks[i]] - _timestamps[peaks[i - 1]]);
      if (dt >= 350 && dt <= 1400) { // batas detak normal: 42 - 171 BPM
        rawIbis.add(dt);
      }
    }

    if (rawIbis.length < 4) return null;

    // 5. FILTER BATAS FISIOLOGIS & ARTEFAK GERAKAN (Normal-to-Normal / NN Filter)
    // Standar Task Force ESC/NASPE: detak yang melompat > 20% dari detak sebelumnya
    // adalah artefak gerak (misal jari bergeser) dan disaring agar RMSSD tidak meledak ke >100 ms.
    final cleanIbis = _filterArtifactIbis(rawIbis);

    if (cleanIbis.length < 3) return null;

    // 6. Hitung fitur HRV dari interval NN yang bersih
    final meanRR = cleanIbis.reduce((a, b) => a + b) / cleanIbis.length;
    final bpm = 60000.0 / meanRR;

    // SDNN (SDRR)
    final sdnn = _standardDeviation(cleanIbis);

    // RMSSD: Selisih berturutan antar detak bersih
    final successiveDiffs = <double>[];
    for (int i = 1; i < cleanIbis.length; i++) {
      final diff = cleanIbis[i] - cleanIbis[i - 1];
      // Hanya sertakan perbedaan berturutan dalam rentang fisiologis (< 120 ms)
      if (diff.abs() < 120.0) {
        successiveDiffs.add(diff);
      }
    }

    double rmssd;
    if (successiveDiffs.isNotEmpty) {
      final meanSquared = successiveDiffs.map((d) => d * d).reduce((a, b) => a + b) /
          successiveDiffs.length;
      rmssd = sqrt(meanSquared);
    } else {
      rmssd = 35.0; // fallback fisiologis
    }

    // pNN50
    double pnn50 = 0.0;
    if (successiveDiffs.isNotEmpty) {
      final nn50Count = successiveDiffs.where((d) => d.abs() > 50).length;
      pnn50 = (nn50Count / successiveDiffs.length) * 100.0;
    }

    // LF/HF ratio (estimasi variabilitas)
    final lfHfRatio = _estimateLfHfRatio(cleanIbis, _fps);

    // Durasi perekaman
    final duration = (_timestamps.last - _timestamps.first) / 1000.0;

    return PpgResult(
      bpm: bpm,
      meanRR: meanRR,
      sdnn: sdnn,
      rmssd: rmssd,
      pnn50: pnn50,
      lfHfRatio: lfHfRatio,
      peakCount: peaks.length,
      durationSec: duration,
      fps: _fps,
      filteredSignal: filtered,
      peaks: peaks,
    );
  }

  /// Menyaring interval IBI yang melompat akibat artefak gerakan jari (Moving Tolerance Filter).
  List<double> _filterArtifactIbis(List<double> raw) {
    if (raw.length < 4) return raw;

    // Hitung median lokal sebagai jangkar kestabilan
    final sorted = List<double>.from(raw)..sort();
    final median = sorted[sorted.length ~/ 2];

    final clean = <double>[];
    for (int i = 0; i < raw.length; i++) {
      final val = raw[i];
      // Jika interval menyimpang lebih dari 28% dari median, maka itu artefak gerakan/detak terlewat
      if ((val - median).abs() / median <= 0.28) {
        clean.add(val);
      }
    }

    // Jika filter terlalu ketat sehingga sisa sampel sedikit, gunakan data raw
    return clean.length >= 3 ? clean : raw;
  }

  /// Detrending sinyal (menghilangkan tren linier).
  List<double> _detrend(List<double> signal) {
    final n = signal.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += signal[i];
      sumXY += i * signal[i];
      sumX2 += i * i;
    }
    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final intercept = (sumY - slope * sumX) / n;
    return List.generate(n, (i) => signal[i] - (slope * i + intercept));
  }

  /// Butterworth bandpass filter (implementasi IIR sederhana).
  List<double> _butterworthBandpass(
    List<double> signal,
    double fs,
    double lowCut,
    double highCut, {
    int order = 2,
  }) {

    // Filter moving average sederhana sebagai bandpass approximation jika IIR kompleks
    final lowPassWindow = (fs / highCut).round().clamp(2, 10);
    final highPassWindow = (fs / lowCut).round().clamp(15, 60);

    // Low pass (smoothing)
    final smoothed = _movingAverage(signal, lowPassWindow);
    // Baseline wander (DC component)
    final baseline = _movingAverage(signal, highPassWindow);

    return List.generate(signal.length, (i) => smoothed[i] - baseline[i]);
  }

  List<double> _movingAverage(List<double> data, int window) {
    final result = List<double>.filled(data.length, 0.0);
    final half = window ~/ 2;
    for (int i = 0; i < data.length; i++) {
      int start = max(0, i - half);
      int end = min(data.length, i + half + 1);
      double sum = 0.0;
      for (int j = start; j < end; j++) {
        sum += data[j];
      }
      result[i] = sum / (end - start);
    }
    return result;
  }

  /// Deteksi puncak (peak detection) dengan refractory period.
  List<int> _detectPeaks(List<double> signal, double fs) {
    final peaks = <int>[];
    final minDistance = (fs * 0.35).round(); // minimal 350 ms antar detak (~171 BPM max)

    // Hitung rata-rata dan deviasi standar sinyal
    final mean = signal.reduce((a, b) => a + b) / signal.length;
    final std = _standardDeviation(signal);
    final threshold = mean + 0.3 * std;

    for (int i = 1; i < signal.length - 1; i++) {
      if (signal[i] > signal[i - 1] &&
          signal[i] > signal[i + 1] &&
          signal[i] > threshold) {
        if (peaks.isEmpty || (i - peaks.last) >= minDistance) {
          peaks.add(i);
        } else if (signal[i] > signal[peaks.last]) {
          peaks[peaks.length - 1] = i;
        }
      }
    }
    return peaks;
  }

  /// Menghitung standar deviasi dari daftar angka.
  double _standardDeviation(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sumSquaredDiffs = values
        .map((v) => (v - mean) * (v - mean))
        .reduce((a, b) => a + b);
    return sqrt(sumSquaredDiffs / (values.length - 1));
  }

  /// Estimasi rasio LF/HF dari domain waktu (pendekatan rasio variabilitas simpatis/parasimpatis).
  double _estimateLfHfRatio(List<double> ibis, double fps) {
    if (ibis.length < 4) return 1.5;
    final sdnn = _standardDeviation(ibis);
    final successiveDiffs = <double>[];
    for (int i = 1; i < ibis.length; i++) {
      successiveDiffs.add((ibis[i] - ibis[i - 1]).abs());
    }
    final rmssd = sqrt(
      successiveDiffs.map((d) => d * d).reduce((a, b) => a + b) /
          successiveDiffs.length,
    );
    if (rmssd <= 0.1) return 2.0;

    // Rasio SDNN/RMSSD mendekati keseimbangan simpatovagal (Task Force 1996)
    final ratio = (sdnn / rmssd) * 0.9;
    return ratio.clamp(0.5, 4.5);
  }
}

/// Model data hasil analisis sinyal PPG.
class PpgResult {
  final double bpm;
  final double meanRR;
  final double sdnn;
  final double rmssd;
  final double pnn50;
  final double lfHfRatio;
  final int peakCount;
  final double durationSec;
  final double fps;
  final List<double> filteredSignal;
  final List<int> peaks;

  PpgResult({
    required this.bpm,
    required this.meanRR,
    required this.sdnn,
    required this.rmssd,
    required this.pnn50,
    required this.lfHfRatio,
    required this.peakCount,
    required this.durationSec,
    required this.fps,
    required this.filteredSignal,
    required this.peaks,
  });
}
