import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../widgets/glassmorphism_card.dart';

enum BreathingPhase {
  inhale,
  holdIn,
  exhale,
  holdOut,
}

class BreathingScreen extends StatefulWidget {
  final Function(int) onNavigateTab;

  const BreathingScreen({super.key, required this.onNavigateTab});

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  bool _isActive = false;
  int _selectedDurationMinutes = 2; // default 2 menit
  int _secondsLeft = 120;
  int _phaseSecondsLeft = 4;
  int _completedCycles = 0;

  BreathingPhase _currentPhase = BreathingPhase.inhale;
  Timer? _sessionTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.25).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _triggerHaptic() {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  void _startBreathing() {
    setState(() {
      _isActive = true;
      _secondsLeft = _selectedDurationMinutes * 60;
      _completedCycles = 0;
      _currentPhase = BreathingPhase.inhale;
      _phaseSecondsLeft = 4;
    });

    _triggerHaptic();
    _animController.forward(from: 0.0);

    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      setState(() {
        if (_secondsLeft > 1) {
          _secondsLeft--;
          _phaseSecondsLeft--;

          if (_phaseSecondsLeft <= 0) {
            _advancePhase();
          }
        } else {
          _finishSession();
        }
      });
    });
  }

  void _advancePhase() {
    _triggerHaptic();
    _phaseSecondsLeft = 4;

    switch (_currentPhase) {
      case BreathingPhase.inhale:
        _currentPhase = BreathingPhase.holdIn;
        // Hold controller at max
        _animController.value = 1.0;
        break;
      case BreathingPhase.holdIn:
        _currentPhase = BreathingPhase.exhale;
        _animController.reverse(from: 1.0);
        break;
      case BreathingPhase.exhale:
        _currentPhase = BreathingPhase.holdOut;
        _animController.value = 0.0;
        break;
      case BreathingPhase.holdOut:
        _currentPhase = BreathingPhase.inhale;
        _completedCycles++;
        _animController.forward(from: 0.0);
        break;
    }
  }

  void _stopBreathing() {
    _sessionTimer?.cancel();
    _animController.stop();
    setState(() {
      _isActive = false;
      _secondsLeft = _selectedDurationMinutes * 60;
      _phaseSecondsLeft = 4;
      _currentPhase = BreathingPhase.inhale;
    });
  }

  void _finishSession() {
    _sessionTimer?.cancel();
    _animController.stop();

    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    setState(() {
      _isActive = false;
      _completedCycles++;
    });

    _showCompletionDialog();
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.statusRelaxed, size: 28),
            const SizedBox(width: 10),
            Text(
              'Sesi Selesai!',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Luar biasa! Anda telah menyelesaikan $_completedCycles siklus Box Breathing (4-4-4-4).',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Aktivitas vagal Anda kini meningkat. Silakan lakukan pengukuran ulang untuk melihat penurunan tingkat stres.',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Nanti Saja',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onNavigateTab(1); // Navigasi ke tab Ukur
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brightBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: Text(
              'Ukur Ulang HRV',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getPhaseText() {
    switch (_currentPhase) {
      case BreathingPhase.inhale:
        return 'Tarik Napas';
      case BreathingPhase.holdIn:
        return 'Tahan Napas';
      case BreathingPhase.exhale:
        return 'Hembuskan Napas';
      case BreathingPhase.holdOut:
        return 'Tahan Napas';
    }
  }

  String _getPhaseInstruction() {
    switch (_currentPhase) {
      case BreathingPhase.inhale:
        return 'Tarik napas perlahan melalui hidung selama 4 detik';
      case BreathingPhase.holdIn:
        return 'Tahan udara di dalam paru-paru Anda dengan santai';
      case BreathingPhase.exhale:
        return 'Hembuskan napas lembut melalui mulut hingga kosong';
      case BreathingPhase.holdOut:
        return 'Tahan paru-paru dalam keadaan kosong sebelum menghirup lagi';
    }
  }

  Color _getPhaseColor() {
    switch (_currentPhase) {
      case BreathingPhase.inhale:
        return AppColors.brightBlue;
      case BreathingPhase.holdIn:
        return const Color(0xFF6366F1); // Indigo
      case BreathingPhase.exhale:
        return AppColors.statusRelaxed;
      case BreathingPhase.holdOut:
        return const Color(0xFF0EA5E9); // Sky
    }
  }

  @override
  Widget build(BuildContext context) {
    final phaseColor = _getPhaseColor();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Box Breathing 4-4-4-4',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Terapi biofeedback pernapasan untuk stimulasi nervus vagus.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Duration selector (hanya bisa diubah jika belum aktif)
              if (!_isActive) _buildDurationSelector(),
              const SizedBox(height: 24),

              // Animated Breathing Sphere Box
              SizedBox(
                height: 290,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow wave
                    AnimatedBuilder(
                      animation: _scaleAnimation,
                      builder: (context, child) {
                        return Container(
                          width: 230 * (_isActive ? _scaleAnimation.value : 1.0),
                          height: 230 * (_isActive ? _scaleAnimation.value : 1.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: phaseColor.withValues(alpha: 0.12),
                          ),
                        );
                      },
                    ),

                    // Middle circle
                    AnimatedBuilder(
                      animation: _scaleAnimation,
                      builder: (context, child) {
                        return Container(
                          width: 180 * (_isActive ? _scaleAnimation.value : 1.0),
                          height: 180 * (_isActive ? _scaleAnimation.value : 1.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.white,
                                phaseColor.withValues(alpha: 0.25),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: phaseColor.withValues(alpha: 0.35),
                                blurRadius: 28,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isActive ? '$_phaseSecondsLeft' : '4',
                                  style: GoogleFonts.inter(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w700,
                                    color: phaseColor,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _isActive ? _getPhaseText() : 'Mulai',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Instruction card
              GlassmorphismCard(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                borderRadius: 18,
                child: Column(
                  children: [
                    Text(
                      _isActive ? _getPhaseInstruction() : 'Duduk dengan posisi tegak dan rileks. Tekan tombol di bawah untuk memulai.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    if (_isActive) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Total Waktu: ${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')} • Siklus ke-${_completedCycles + 1}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brightBlue,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Control Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isActive ? _stopBreathing : _startBreathing,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isActive ? AppColors.coralRed : AppColors.brightBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    elevation: 4,
                    shadowColor: (_isActive ? AppColors.coralRed : AppColors.brightBlue).withValues(alpha: 0.4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isActive ? Icons.stop_rounded : Icons.spa_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isActive ? 'Hentikan Sesi' : 'Mulai Latihan Napas',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDurationSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [1, 2, 3, 5].map((mins) {
        final isSelected = _selectedDurationMinutes == mins;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: () => setState(() => _selectedDurationMinutes = mins),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brightBlue : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? AppColors.brightBlue : AppColors.border,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.brightBlue.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : null,
              ),
              child: Text(
                '$mins Menit',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
