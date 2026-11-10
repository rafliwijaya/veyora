import 'dart:math';

/// Pemrosesan sinyal digital PPG dari frame kamera smartphone.
/// Mengimplementasikan: Butterworth Bandpass Filter, Peak Detection, dan ekstraksi fitur HRV.
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

    if (peaks.length < 3) return null;

    // 4. Hitung IBI (Inter-Beat Interval) dalam milidetik
    final ibis = <double>[];
    for (int i = 1; i < peaks.length; i++) {
      final dt = (_timestamps[peaks[i]] - _timestamps[peaks[i - 1]]);
      if (dt >= 300 && dt <= 1500) {
        ibis.add(dt);
      }
    }

    if (ibis.length < 3) return null;

    // 5. Hitung fitur HRV
    final meanRR = ibis.reduce((a, b) => a + b) / ibis.length;
    final bpm = 60000.0 / meanRR;

    // SDNN
    final sdnn = _standardDeviation(ibis);

    // RMSSD
    final successiveDiffs = <double>[];
    for (int i = 1; i < ibis.length; i++) {
      successiveDiffs.add(ibis[i] - ibis[i - 1]);
    }
    final rmssd = sqrt(
      successiveDiffs.map((d) => d * d).reduce((a, b) => a + b) /
          successiveDiffs.length,
    );

    // pNN50
    final nn50Count = successiveDiffs.where((d) => d.abs() > 50).length;
    final pnn50 = (nn50Count / successiveDiffs.length) * 100.0;

    // LF/HF ratio (estimasi sederhana dari variabilitas)
    final lfHfRatio = _estimateLfHfRatio(ibis, _fps);

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
    final nyq = 0.5 * fs;
    final low = lowCut / nyq;
    final high = highCut / nyq;

    // Biquad bandpass filter coefficients (2nd order)
    final w0Low = tan(pi * low);
    final w0High = tan(pi * high);
    final bw = w0High - w0Low;
    final w02 = w0Low * w0High;

    final q = sqrt(w02) / bw;
    final w0 = sqrt(w02);
    final alpha = sin(2 * atan(w0)) / (2 * q);

    final a0 = 1 + alpha;
    final b0 = alpha / a0;
    final b1 = 0.0;
    final b2 = -alpha / a0;
    final a1 = (-2 * cos(2 * atan(w0))) / a0;
    final a2 = (1 - alpha) / a0;

    // Forward pass
    final forward = _applyFilter(signal, b0, b1, b2, a1, a2);
    // Backward pass (zero-phase filtering / filtfilt)
    final reversed = forward.reversed.toList();
    final backward = _applyFilter(reversed, b0, b1, b2, a1, a2);
    return backward.reversed.toList();
  }

  List<double> _applyFilter(
    List<double> signal,
    double b0,
    double b1,
    double b2,
    double a1,
    double a2,
  ) {
    final output = List<double>.filled(signal.length, 0);
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (int i = 0; i < signal.length; i++) {
      final x0 = signal[i];
      final y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      output[i] = y0;
      x2 = x1;
      x1 = x0;
      y2 = y1;
      y1 = y0;
    }
    return output;
  }

  /// Deteksi puncak sistolik dengan jarak minimum dan prominence adaptif.
  List<int> _detectPeaks(List<double> signal, double fps) {
    final minDistance = max((fps * 0.35).round(), 5); // Minimal 0.35 detik (170 BPM)
    final threshold = _standardDeviation(signal) * 0.35;

    final peaks = <int>[];
    for (int i = 2; i < signal.length - 2; i++) {
      if (signal[i] > signal[i - 1] &&
          signal[i] > signal[i - 2] &&
          signal[i] > signal[i + 1] &&
          signal[i] > signal[i + 2] &&
          signal[i] > threshold) {
        if (peaks.isEmpty || (i - peaks.last) >= minDistance) {
          peaks.add(i);
        } else if (signal[i] > signal[peaks.last]) {
          peaks[peaks.length - 1] = i; // Ganti dengan puncak lebih tinggi
        }
      }
    }
    return peaks;
  }

  /// Estimasi rasio LF/HF dari variabilitas IBI.
  double _estimateLfHfRatio(List<double> ibis, double fps) {
    if (ibis.length < 10) return 1.5;

    // Estimasi sederhana menggunakan rasio variabilitas jangka panjang vs pendek
    // LF: variabilitas lambat (pernapasan baroreflex ~0.04-0.15 Hz)
    // HF: variabilitas cepat (aritmia sinus respirasi ~0.15-0.40 Hz)
    final diffs = <double>[];
    for (int i = 1; i < ibis.length; i++) {
      diffs.add((ibis[i] - ibis[i - 1]).abs());
    }

    // Variabilitas jangka pendek (berturutan) ~ HF
    final hfPower = _standardDeviation(diffs);
    // Variabilitas total ~ LF + HF
    final totalPower = _standardDeviation(ibis);

    if (hfPower < 0.001) return 3.0;
    final lfPower = max(0.0, totalPower - hfPower);
    return lfPower / hfPower;
  }

  double _standardDeviation(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sumSqDiff =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b);
    return sqrt(sumSqDiff / (values.length - 1));
  }
}

/// Hasil pemrosesan sinyal PPG lengkap.
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
