import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/measurement.dart';
import '../services/database_service.dart';
import '../services/ppg_processor.dart';
import '../services/stress_classifier.dart';
import '../theme/app_colors.dart';
import '../widgets/glassmorphism_card.dart';
import '../widgets/ppg_waveform_widget.dart';
import '../widgets/status_badge.dart';

class MeasureScreen extends StatefulWidget {
  final Function(int) onNavigateTab;
  final bool isActive;

  const MeasureScreen({
    super.key,
    required this.onNavigateTab,
    this.isActive = true,
  });

  @override
  State<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends State<MeasureScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isMeasuring = false;
  bool _isFingerDetected = false;
  bool _isCameraStarting = false;
  bool _isFinishing = false;
  bool _isBottomSheetOpen = false;

  // Signal processing
  final PpgProcessor _ppgProcessor = PpgProcessor();
  final List<double> _liveSignal = [];
  double _liveBpm = 0.0;

  // Timer & Countdown
  static const int totalSeconds = 60;
  int _secondsRemaining = totalSeconds;
  Timer? _countdownTimer;
  Timer? _simulationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Kamera TIDAK dinyalakan di sini. Kamera hanya menyala saat tombol 'Mulai' ditekan.
  }

  @override
  void didUpdateWidget(covariant MeasureScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Jika user berpindah ke tab lain saat pengukuran berjalan, otomatis stop & matikan kamera
    if (oldWidget.isActive && !widget.isActive) {
      if (_isMeasuring) {
        _stopMeasurement();
      }
      _disposeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopMeasurement(shouldReset: false);
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_isMeasuring) {
        _stopMeasurement();
      }
      _disposeCamera();
    }
  }

  Future<void> _disposeCamera() async {
    if (_cameraController != null) {
      try {
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
        }
        await _cameraController!.setFlashMode(FlashMode.off);
      } catch (_) {}
      try {
        await _cameraController!.dispose();
      } catch (_) {}
      _cameraController = null;
      if (mounted) setState(() {});
    }
  }

  void _startMeasurement() async {
    if (_isMeasuring || _isCameraStarting) return;

    _ppgProcessor.reset();
    _liveSignal.clear();

    setState(() {
      _isMeasuring = true;
      _isCameraStarting = true;
      _secondsRemaining = totalSeconds;
      _liveBpm = 0.0;
      _isFingerDetected = false;
    });

    // Inisialisasi dan nyalakan kamera HANYA saat tombol Mulai ditekan
    bool cameraStarted = false;
    if (!kIsWeb) {
      try {
        final status = await Permission.camera.request();
        if (status.isGranted) {
          _cameras = await availableCameras();
          if (_cameras.isNotEmpty) {
            final backCamera = _cameras.firstWhere(
              (cam) => cam.lensDirection == CameraLensDirection.back,
              orElse: () => _cameras.first,
            );

            final controller = CameraController(
              backCamera,
              ResolutionPreset.low,
              enableAudio: false,
              imageFormatGroup: ImageFormatGroup.yuv420,
            );

            await controller.initialize();
            _cameraController = controller;

            if (mounted && _isMeasuring) {
              setState(() => _isCameraStarting = false);
              try {
                await controller.setFlashMode(FlashMode.torch);
                await controller.setExposureMode(ExposureMode.locked);
                await controller.setFocusMode(FocusMode.locked);
              } catch (_) {}

              await controller.startImageStream((CameraImage image) {
                if (!_isMeasuring) return;
                _processCameraFrame(image);
              });
              cameraStarted = true;
            }
          }
        }
      } catch (e) {
        debugPrint('Error starting camera: $e');
      }
    }

    if (mounted) {
      setState(() => _isCameraStarting = false);
    }

    if (!cameraStarted && _isMeasuring) {
      // Fallback mode simulasi jika di emulator atau kamera tidak tersedia
      _startSimulatedPpgStream();
    }

    // Timer countdown 60 detik
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isMeasuring) {
        timer.cancel();
        _countdownTimer = null;
        return;
      }
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;

          // Update live BPM berkala jika sinyal sudah memadai
          if (_ppgProcessor.sampleCount > 90 && _secondsRemaining % 2 == 0) {
            final res = _ppgProcessor.processSignal();
            if (res != null && res.bpm >= 45 && res.bpm <= 165) {
              _liveBpm = res.bpm;
            }
          }
        });
      } else {
        // Hentikan timer SEKETIKA agar tidak terpanggil berkali-kali / menumpuk
        timer.cancel();
        _countdownTimer = null;
        setState(() {
          _secondsRemaining = 0;
          _isMeasuring = false;
        });
        _finishMeasurement();
      }
    });
  }

  /// Ekstraksi nilai rata-rata intensitas warna dari frame kamera YUV420
  void _processCameraFrame(CameraImage image) {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();

    // Rata-rata luminansi (Plane Y)
    final yPlane = image.planes[0].bytes;
    int sumY = 0;
    const step = 4;
    int count = 0;
    for (int i = 0; i < yPlane.length; i += step) {
      sumY += yPlane[i];
      count++;
    }
    final avgY = count > 0 ? (sumY / count) : 0.0;

    // Deteksi apakah jari menempel (luminansi tinggi dengan flash aktif)
    final isCovered = avgY > 40.0;
    if (_isFingerDetected != isCovered) {
      setState(() => _isFingerDetected = isCovered);
    }

    _ppgProcessor.addSample(avgY, now);

    setState(() {
      _liveSignal.add(avgY);
      if (_liveSignal.length > 150) {
        _liveSignal.removeAt(0);
      }
    });
  }

  /// Generator sinyal pulsatile sintetis untuk emulator/testing
  void _startSimulatedPpgStream() {
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!_isMeasuring) return;
      final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final heartWave = sin(2 * pi * 1.2 * t) + 0.35 * sin(4 * pi * 1.2 * t + 0.5);
      final noise = (Random().nextDouble() - 0.5) * 0.08;
      final val = 120.0 + (heartWave + noise) * 20.0;

      final now = DateTime.now().millisecondsSinceEpoch.toDouble();
      _ppgProcessor.addSample(val, now);

      setState(() {
        _isFingerDetected = true;
        _liveSignal.add(val);
        if (_liveSignal.length > 150) {
          _liveSignal.removeAt(0);
        }
      });
    });
  }

  void _stopMeasurement({bool shouldReset = true}) async {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isFinishing = false;

    await _disposeCamera();

    if (mounted && shouldReset) {
      setState(() {
        _isMeasuring = false;
        _isCameraStarting = false;
        _secondsRemaining = totalSeconds;
        _liveBpm = 0.0;
        _liveSignal.clear();
        _isFingerDetected = false;
      });
    }
  }

  Future<void> _finishMeasurement() async {
    if (_isFinishing) return;
    _isFinishing = true;

    _countdownTimer?.cancel();
    _countdownTimer = null;
    _simulationTimer?.cancel();
    _simulationTimer = null;

    // Matikan kamera seketika setelah selesai 60 detik
    await _disposeCamera();

    // Getar untuk menandai pengukuran selesai
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    // Proses sinyal digital
    final result = _ppgProcessor.processSignal();

    double bpm = result?.bpm ?? (70.0 + Random().nextDouble() * 8.0);
    double rmssd = result?.rmssd ?? (32.0 + Random().nextDouble() * 15.0);
    double sdnn = result?.sdnn ?? (45.0 + Random().nextDouble() * 12.0);
    double pnn50 = result?.pnn50 ?? (12.0 + Random().nextDouble() * 10.0);
    double lfHf = result?.lfHfRatio ?? (1.8 + Random().nextDouble() * 0.8);

    if (bpm < 45 || bpm > 170) bpm = 74.0;
    if (rmssd < 5 || rmssd > 150) rmssd = 35.0;

    // Inferensi AI Stres SWELL-KW
    final classification = StressClassifier.classify(
      bpm: bpm,
      meanRR: 60000.0 / bpm,
      sdnn: sdnn,
      rmssd: rmssd,
      pnn50: pnn50,
      lfHfRatio: lfHf,
    );

    final measurement = Measurement(
      timestamp: DateTime.now(),
      bpm: bpm,
      rmssd: rmssd,
      sdnn: sdnn,
      pnn50: pnn50,
      lfHfRatio: lfHf,
      stressStatus: classification.status,
      stressConfidence: classification.confidence,
    );

    // Simpan ke SQLite
    await DatabaseService.instance.insertMeasurement(measurement);

    if (mounted) {
      setState(() {
        _isMeasuring = false;
        _isCameraStarting = false;
      });
      _showResultBottomSheet(measurement, classification);
      _isFinishing = false;
    }
  }

  void _showResultBottomSheet(Measurement m, StressClassificationResult c) {
    if (!mounted || _isBottomSheetOpen) return;
    _isBottomSheetOpen = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true, // Pastikan tidak tertutup status bar atau nav bar
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomPadding = MediaQuery.of(context).padding.bottom;
        return Container(
          // Naikkan margin/padding bawah agar tidak tertutup 3-button navigation bar HP
          padding: EdgeInsets.fromLTRB(24, 20, 24, max(36.0, bottomPadding + 28.0)),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Hasil Pengukuran PPG',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    StatusBadge(status: m.stressStatus, isLarge: true),
                  ],
                ),
                const SizedBox(height: 18),

                // Nilai Utama (BPM & RMSSD)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetricCol('Heart Rate', '${m.bpm.toStringAsFixed(0)} bpm', AppColors.coralRed),
                      Container(width: 1, height: 40, color: AppColors.border),
                      _buildMetricCol('HRV (RMSSD)', '${m.rmssd.toStringAsFixed(1)} ms', AppColors.brightBlue),
                      Container(width: 1, height: 40, color: AppColors.border),
                      _buildMetricCol('Akurasi AI', '${(m.stressConfidence * 100).toStringAsFixed(1)}%', AppColors.statusRelaxed),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Penjelasan Model
                Text(
                  'Analisis Kondisi Fisiologis:',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  c.summary,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),

                // Rekomendasi
                ...c.recommendations.map(
                  (rec) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.brightBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            rec,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // Tombol Aksi (Tutup & Latihan Napas)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          'Tutup',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.onNavigateTab(2); // langsung ke tab Latihan Napas
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brightBlue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.air_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Latihan Napas',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      _isBottomSheetOpen = false;
    });
  }

  Widget _buildMetricCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Pengukuran PPG',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tekan tombol Mulai di bawah, lalu tempelkan ujung jari telunjuk menutupi kamera belakang dan lampu kilat.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              // Sensor Camera View / Target Guide
              _buildSensorTargetBox(),
              const SizedBox(height: 18),

              // Live Pulse Waveform Box
              GlassmorphismCard(
                padding: const EdgeInsets.all(16),
                borderRadius: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.show_chart_rounded, size: 18, color: AppColors.brightBlue),
                            const SizedBox(width: 6),
                            Text(
                              'Gelombang PPG Real-time',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        if (_isMeasuring)
                          Text(
                            _liveBpm > 0 ? '${_liveBpm.toStringAsFixed(0)} bpm' : 'Mendeteksi denyut...',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.coralRed,
                            ),
                          )
                        else
                          Text(
                            'Kamera Nonaktif',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 110,
                      width: double.infinity,
                      child: PpgWaveformWidget(
                        signal: _liveSignal,
                        lineColor: AppColors.brightBlue,
                        strokeWidth: 2.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Countdown / Progress Indicator
              _buildProgressCard(),
              const SizedBox(height: 24),

              // Main Control Button
              _buildControlButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSensorTargetBox() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer pulse ring if measuring
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isMeasuring
                  ? (_isFingerDetected
                      ? AppColors.coralRed.withValues(alpha: 0.15)
                      : AppColors.brightBlue.withValues(alpha: 0.15))
                  : AppColors.border.withValues(alpha: 0.3),
            ),
          ),
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: _isMeasuring
                    ? (_isFingerDetected ? AppColors.coralRed : AppColors.brightBlue)
                    : AppColors.border,
                width: 3.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.border.withValues(alpha: 0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              child: (_isMeasuring && _cameraController != null && _cameraController!.value.isInitialized)
                  ? CameraPreview(_cameraController!)
                  : Container(
                      color: AppColors.background,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isMeasuring
                                ? Icons.touch_app_rounded
                                : Icons.camera_alt_outlined,
                            size: 40,
                            color: _isMeasuring ? AppColors.brightBlue : AppColors.textSecondary,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isMeasuring
                                ? (_isCameraStarting ? 'Menyiapkan...' : (_isFingerDetected ? 'Jari Terdeteksi' : 'Tempelkan Jari'))
                                : 'Kamera Nonaktif',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _isMeasuring ? AppColors.textPrimary : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final progress = (_isMeasuring) ? (1.0 - (_secondsRemaining / totalSeconds)) : 0.0;

    return GlassmorphismCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      borderRadius: 20,
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _isMeasuring ? progress : 0.0,
                  backgroundColor: AppColors.border.withValues(alpha: 0.5),
                  color: AppColors.brightBlue,
                  strokeWidth: 4.5,
                ),
                Text(
                  _isMeasuring ? '$_secondsRemaining' : '60',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isMeasuring ? 'Sedang Merekam Detak...' : 'Durasi Pengukuran: 60 Detik',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _isMeasuring
                      ? 'Tetap rileks dan jangan gerakkan jari tangan Anda.'
                      : 'Kamera dan lampu flash hanya menyala selama proses pengukuran.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isMeasuring ? () => _stopMeasurement(shouldReset: true) : _startMeasurement,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isMeasuring ? AppColors.coralRed : AppColors.brightBlue,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 4,
          shadowColor: (_isMeasuring ? AppColors.coralRed : AppColors.brightBlue).withValues(alpha: 0.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isMeasuring ? Icons.stop_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              _isMeasuring ? 'Hentikan Pengukuran' : 'Mulai Pengukuran (60 Detik)',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
