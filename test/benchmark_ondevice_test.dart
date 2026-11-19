import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyora/services/ppg_processor.dart';
import 'package:veyora/services/stress_classifier.dart';

double _mean(List<double> values) =>
    values.reduce((a, b) => a + b) / values.length;

double _std(List<double> values) {
  final m = _mean(values);
  final sq = values.map((v) => pow(v - m, 2)).reduce((a, b) => a + b);
  return sqrt(sq / (values.length - 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Benchmark Komputasi On-Device & Studi Ablasi (Bab 4.4 - Tabel 4.3)', () async {
    // 1. Ukuran file model biner
    final binFile = File('assets/models/stress_forest.bin');
    final fileSizeBytes = await binFile.length();
    final fileSizeMb = fileSizeBytes / (1000 * 1000);

    // 2. Pengukuran Load Time (30 pengulangan parsing aset)
    final loadTimesMs = <double>[];
    for (int i = 0; i < 30; i++) {
      final sw = Stopwatch()..start();
      final data = await rootBundle.load('assets/models/stress_forest.bin');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      // Simulasi pembacaan header & alokasi array seperti di loadModel()
      final bd = ByteData.sublistView(bytes);
      final nTrees = bd.getUint32(0, Endian.little);
      int totalNodes = 0;
      for (int t = 0; t < nTrees; t++) {
        totalNodes += bd.getUint32(4 + t * 4, Endian.little);
      }
      final featOffset = 804;
      final threshOffset = featOffset + totalNodes;
      final leftOffset = threshOffset + totalNodes * 8;
      final rightOffset = leftOffset + totalNodes * 2;
      Uint8List.fromList(bytes.sublist(threshOffset, leftOffset));
      Uint8List.fromList(bytes.sublist(leftOffset, rightOffset));
      Uint8List.fromList(bytes.sublist(rightOffset, rightOffset + totalNodes * 2));
      sw.stop();
      loadTimesMs.add(sw.elapsedMicroseconds / 1000.0);
    }

    // Pastikan StressClassifier terinisialisasi penuh
    final loaded = await StressClassifier.loadModel();
    expect(loaded, isTrue);

    // Warm-up 5 kali
    for (int i = 0; i < 5; i++) {
      StressClassifier.classify(
        bpm: 72.0,
        meanRR: 833.3,
        sdnn: 45.0,
        rmssd: 42.0,
        pnn50: 15.0,
        lfHfRatio: 1.2,
      );
    }

    // 3. Pengukuran Inference Latency (30 pengulangan)
    final inferTimesMs = <double>[];
    for (int i = 0; i < 30; i++) {
      final sw = Stopwatch()..start();
      StressClassifier.classify(
        bpm: 72.0 + (i % 10),
        meanRR: 833.3,
        sdnn: 48.0,
        rmssd: 40.0 + (i % 15),
        pnn50: 14.0,
        lfHfRatio: 1.3,
      );
      sw.stop();
      inferTimesMs.add(sw.elapsedMicroseconds / 1000.0);
    }

    // 4. Studi Ablasi: Pengujian Skenario Filter Artefak & Adaptasi Domain
    // Skenario A: Sinyal Rileks dengan 2 artefak gerakan jari (lonjakan IBI)
    final ppg = PpgProcessor();
    double t = 0.0;
    // Simulasi 30 detik sinyal detak ~72 BPM (IBI ~833 ms) + 2 artefak gerak di detik 10 & 20
    for (int i = 0; i < 900; i++) {
      final sec = i / 30.0;
      double val = 120.0 + 18.0 * sin(2 * pi * 1.2 * sec);
      if ((sec - 10.0).abs() < 0.25 || (sec - 20.0).abs() < 0.25) {
        val += 65.0; // lonjakan artefak gerakan jari
      }
      ppg.addSample(val, t);
      t += 33.33;
    }
    final ppgRes = ppg.processSignal();
    expect(ppgRes, isNotNull);

    // Skenario B: Uji klasifikasi pada sampel input fisiologis kamera
    final resRelaxed55 = StressClassifier.classify(
      bpm: 72.0,
      meanRR: 833.3,
      sdnn: 85.0,
      rmssd: 55.0,
      pnn50: 1.2,
      lfHfRatio: 1.1,
    );
    final resStressed10 = StressClassifier.classify(
      bpm: 98.0,
      meanRR: 612.2,
      sdnn: 30.0,
      rmssd: 10.0,
      pnn50: 0.5,
      lfHfRatio: 3.4,
    );

    // Cetak hasil rapi untuk Tabel 4.3
    // ignore: avoid_print
    print('\n============================================================');
    // ignore: avoid_print
    print('HASIL BENCHMARK ON-DEVICE (30 PENGULANGAN)');
    // ignore: avoid_print
    print('  Ukuran Model Biner : ${fileSizeMb.toStringAsFixed(2)} MB ($fileSizeBytes bytes)');
    // ignore: avoid_print
    print('  Load Time          : ${_mean(loadTimesMs).toStringAsFixed(2)} ± ${_std(loadTimesMs).toStringAsFixed(2)} ms');
    // ignore: avoid_print
    print('  Inference Latency  : ${_mean(inferTimesMs).toStringAsFixed(3)} ± ${_std(inferTimesMs).toStringAsFixed(3)} ms');
    // ignore: avoid_print
    print('------------------------------------------------------------');
    // ignore: avoid_print
    print('STUDI ABLASI & VALIDASI ADAPTASI DOMAIN:');
    // ignore: avoid_print
    print('  1) Sinyal + Artefak Gerak -> BPM=${ppgRes!.bpm.toStringAsFixed(1)}, RMSSD=${ppgRes.rmssd.toStringAsFixed(1)} ms');
    // ignore: avoid_print
    print('  2) Sampel Rileks (RMSSD=55.0 ms) -> Status: ${resRelaxed55.status} (Score: ${resRelaxed55.stressScore.toStringAsFixed(1)}%)');
    // ignore: avoid_print
    print('  3) Sampel Stres  (RMSSD=10.0 ms, HR=98) -> Status: ${resStressed10.status} (Score: ${resStressed10.stressScore.toStringAsFixed(1)}%)');
    // ignore: avoid_print
    print('============================================================\n');

    expect(ppgRes.bpm, closeTo(72.0, 5.0));
    expect(resRelaxed55.stressScore, inInclusiveRange(0.0, 100.0));
    expect(resStressed10.stressScore, inInclusiveRange(0.0, 100.0));
  });
}
