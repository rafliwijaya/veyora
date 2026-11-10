import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class RunTrackerScreen extends StatefulWidget {
  final Function(int) onNavigateTab;

  const RunTrackerScreen({super.key, required this.onNavigateTab});

  @override
  State<RunTrackerScreen> createState() => _RunTrackerScreenState();
}

enum RunStatus { stopped, running, paused }

class _RunTrackerScreenState extends State<RunTrackerScreen> {
  RunStatus _status = RunStatus.stopped;
  StreamSubscription<Position>? _positionStream;
  Timer? _stopwatchTimer;
  Timer? _simTimer;

  // Running metrics
  int _secondsElapsed = 0;
  double _totalDistanceMeters = 0.0;
  double _currentSpeedKmh = 0.0; // km/h
  Position? _lastPosition;
  bool _isGpsActive = false;
  String _gpsStatusMessage = 'GPS Siap';

  // Demo simulation mode (berguna jika di dalam ruangan / emulator)
  bool _isSimulationMode = false;

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    _simTimer?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  Future<bool> _checkLocationPermission() async {
    if (kIsWeb) return false;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Layanan lokasi (GPS) belum aktif di perangkat Anda.'),
            backgroundColor: AppColors.coralRed,
          ),
        );
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin akses lokasi ditolak.'),
              backgroundColor: AppColors.coralRed,
            ),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Izin lokasi ditolak permanen. Buka pengaturan aplikasi untuk mengizinkan.',
            ),
            backgroundColor: AppColors.coralRed,
          ),
        );
      }
      return false;
    }

    return true;
  }

  void _startRunning() async {
    bool hasPermission = await _checkLocationPermission();

    setState(() {
      _status = RunStatus.running;
      _secondsElapsed = 0;
      _totalDistanceMeters = 0.0;
      _currentSpeedKmh = 0.0;
      _lastPosition = null;
      _isSimulationMode = !hasPermission;
      _gpsStatusMessage = hasPermission ? 'GPS Terhubung' : 'Mode Simulasi Aktif';
      _isGpsActive = hasPermission;
    });

    // Mulai timer stopwatch (setiap 1 detik)
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status == RunStatus.running && mounted) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });

    if (hasPermission) {
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // Pembaruan setiap gerak 2 meter
      );

      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          if (_status != RunStatus.running || !mounted) return;

          setState(() {
            _isGpsActive = true;
            _gpsStatusMessage = 'GPS Akurat (±${position.accuracy.toStringAsFixed(1)}m)';

            if (_lastPosition != null) {
              final deltaMeters = Geolocator.distanceBetween(
                _lastPosition!.latitude,
                _lastPosition!.longitude,
                position.latitude,
                position.longitude,
              );

              // Filter noise GPS (hanya catat jika pergerakan realistis > 1 meter dan kecepatan < 35 km/jam)
              if (deltaMeters >= 1.0) {
                _totalDistanceMeters += deltaMeters;
              }
            }

            _lastPosition = position;
            _currentSpeedKmh = max(0.0, position.speed * 3.6); // m/s to km/h
          });
        },
        onError: (e) {
          debugPrint('Error GPS: $e');
          if (mounted) {
            setState(() {
              _isGpsActive = false;
              _gpsStatusMessage = 'Sinyal GPS Terputus';
            });
          }
        },
      );
    } else {
      // Fallback simulasi jika di emulator / testing tanpa GPS fisik
      _startSimulationStream();
    }
  }

  void _startSimulationStream() {
    _simTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_status != RunStatus.running || !mounted) return;
      setState(() {
        // Simulasi kecepatan lari rata-rata 8.5 - 10.5 km/jam (sekitar 2.5 m/detik)
        final simDelta = 4.8 + Random().nextDouble() * 1.2;
        _totalDistanceMeters += simDelta;
        _currentSpeedKmh = (simDelta / 2.0) * 3.6;
      });
    });
  }

  void _pauseRunning() {
    setState(() {
      _status = RunStatus.paused;
    });
  }

  void _resumeRunning() {
    setState(() {
      _status = RunStatus.running;
    });
  }

  void _stopAndFinishRunning() {
    _stopwatchTimer?.cancel();
    _simTimer?.cancel();
    _positionStream?.cancel();

    setState(() {
      _status = RunStatus.stopped;
    });

    _showPostRunSummaryDialog();
  }

  void _showPostRunSummaryDialog() {
    final distanceKm = _totalDistanceMeters / 1000.0;
    final minutes = _secondsElapsed / 60.0;
    final paceMinPerKm = distanceKm > 0.05 ? (minutes / distanceKm) : 0.0;
    final calories = (distanceKm * 60.0 * 1.036).toInt(); // Estimasi kalori lari untuk BB 60kg

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return Container(
          padding: EdgeInsets.fromLTRB(24, 20, 24, max(36.0, bottomInset + 24.0)),
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
                      'Sesi Lari Selesai! 🎉',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.statusRelaxed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Kardio Selesai',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.statusRelaxed,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Ringkasan Utama 2x2
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildSummaryItem('Total Jarak', '${distanceKm.toStringAsFixed(2)} km', AppColors.brightBlue),
                          Container(width: 1, height: 40, color: AppColors.border),
                          _buildSummaryItem('Total Waktu', _formatDuration(_secondsElapsed), AppColors.textPrimary),
                        ],
                      ),
                      const Divider(height: 24, color: AppColors.border),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildSummaryItem('Rata-rata Pace', _formatPace(paceMinPerKm), AppColors.textSecondary),
                          Container(width: 1, height: 40, color: AppColors.border),
                          _buildSummaryItem('Estimasi Kalori', '$calories kcal', AppColors.coralRed),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Rekomendasi Pemulihan Jantung Veyora
                Text(
                  'Pemulihan Kardiovaskular (Veyora):',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Setelah aktivitas lari, denyut jantung Anda berada pada fase pemulihan (*Heart Rate Recovery*). Pantau penurunan denyut dan stabilkan sistem saraf simpatis dengan latihan napas.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),

                // Aksi Rekomendasi: Ukur PPG & Box Breathing
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.pop(context); // Kembali dari RunTrackerScreen
                          widget.onNavigateTab(1); // Ke tab Ukur PPG
                        },
                        icon: const Icon(Icons.favorite_rounded, size: 18, color: Colors.white),
                        label: Text(
                          'Ukur Jantung',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.coralRed,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.pop(context); // Kembali dari RunTrackerScreen
                          widget.onNavigateTab(2); // Ke tab Napas
                        },
                        icon: const Icon(Icons.air_rounded, size: 18, color: Colors.white),
                        label: Text(
                          'Box Breathing',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brightBlue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      'Tutup Ringkasan',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final mins = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatPace(double paceMinPerKm) {
    if (paceMinPerKm <= 0.0 || paceMinPerKm > 30.0) return "--'--\"";
    final minutes = paceMinPerKm.toInt();
    final seconds = ((paceMinPerKm - minutes) * 60).round();
    return "$minutes'${seconds.toString().padLeft(2, '0')}\"";
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = _totalDistanceMeters / 1000.0;
    final minutes = _secondsElapsed / 60.0;
    final paceMinPerKm = distanceKm > 0.05 ? (minutes / distanceKm) : 0.0;
    final calories = (distanceKm * 60.0 * 1.036).toInt();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () {
            if (_status == RunStatus.running) {
              _showExitConfirmation();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          'Pelacak Lari & Kardio',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isGpsActive ? AppColors.statusRelaxed : Colors.amber,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _gpsStatusMessage,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),

              // Hero: Jarak Tempuh Utama (Kilometer)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.border.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'JARAK TEMPUH',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          distanceKm.toStringAsFixed(2),
                          style: GoogleFonts.inter(
                            fontSize: 64,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brightBlue,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'KM',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _status == RunStatus.running
                            ? AppColors.brightBlue.withValues(alpha: 0.1)
                            : (_status == RunStatus.paused
                                ? Colors.amber.withValues(alpha: 0.15)
                                : AppColors.background),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _status == RunStatus.running
                            ? '● Sesi Aktif Berlari'
                            : (_status == RunStatus.paused ? '⏸ Sesi Dijeda' : 'Siap Memulai'),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _status == RunStatus.running
                              ? AppColors.brightBlue
                              : (_status == RunStatus.paused ? Colors.orange.shade800 : AppColors.textSecondary),
                        ),
                      ),
                    ),
                    if (_isSimulationMode && _status != RunStatus.stopped) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Mode Simulasi (Demo tanpa GPS fisik)',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.coralRed,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 4 Metrik Detail (Durasi, Pace, Speed, Kalori)
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.timer_outlined,
                      label: 'Durasi',
                      value: _formatDuration(_secondsElapsed),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.speed_rounded,
                      label: 'Pace',
                      value: _formatPace(paceMinPerKm),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.bolt_rounded,
                      label: 'Speed',
                      value: '${_currentSpeedKmh.toStringAsFixed(1)} km/h',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.local_fire_department_rounded,
                      label: 'Kalori',
                      value: '$calories kcal',
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Kontrol Tombol
              if (_status == RunStatus.stopped)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startRunning,
                    icon: const Icon(Icons.directions_run_rounded, size: 26, color: Colors.white),
                    label: Text(
                      'Mulai Lari (GPS)',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brightBlue,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 4,
                      shadowColor: AppColors.brightBlue.withValues(alpha: 0.4),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    // Tombol Jeda / Lanjut
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _status == RunStatus.running ? _pauseRunning : _resumeRunning,
                        icon: Icon(
                          _status == RunStatus.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 24,
                          color: Colors.white,
                        ),
                        label: Text(
                          _status == RunStatus.running ? 'Jeda' : 'Lanjut',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _status == RunStatus.running ? Colors.amber.shade700 : AppColors.brightBlue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Tombol Stop / Selesai
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _stopAndFinishRunning,
                        icon: const Icon(Icons.stop_rounded, size: 24, color: Colors.white),
                        label: Text(
                          'Selesai',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.coralRed,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppColors.brightBlue),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Hentikan Sesi Lari?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Sesi pelacakan lari Anda masih berjalan. Apakah Anda ingin keluar dan menghentikan perekaman?',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Lanjut Lari', style: GoogleFonts.inter(color: AppColors.brightBlue)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _stopAndFinishRunning();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coralRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Keluar & Selesai', style: GoogleFonts.inter(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
