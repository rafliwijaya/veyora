import 'run_tracker_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/measurement.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../widgets/blue_highlight_card.dart';
import '../widgets/glassmorphism_card.dart';
import '../widgets/status_badge.dart';

class HomeScreen extends StatefulWidget {
  final Function(int) onNavigateTab;

  const HomeScreen({super.key, required this.onNavigateTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Measurement? _latestMeasurement;

  @override
  void initState() {
    super.initState();
    _loadLatestMeasurement();
  }

  Future<void> _loadLatestMeasurement() async {
    final latest = await DatabaseService.instance.getLatestMeasurement();
    if (mounted) {
      setState(() {
        _latestMeasurement = latest;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.brightBlue,
          onRefresh: _loadLatestMeasurement,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top App Header
                _buildHeader(),
                const SizedBox(height: 16),

                // Hero Section: 3D Anatomical Heart with Floating Glass Info Cards
                _buildHeroAnatomicalHeart(),
                const SizedBox(height: 20),

                // Blue Highlight Card (Card Utama BPM)
                BlueHighlightCard(
                  bpm: _latestMeasurement?.bpm ?? 72.0,
                  title: 'Heart Rate Monitor',
                  subtitle: _latestMeasurement != null ? 'Terakhir diukur' : 'Mode Siap',
                  onTap: () => widget.onNavigateTab(1), // ke tab Ukur
                ),
                const SizedBox(height: 18),

                // 2x2 Rounded Cards Layout (Fitur HRV & Status Medis)
                _buildHrvMetricsGrid(),
                const SizedBox(height: 20),

                // Action Banner: Box Breathing
                _buildBreathingBanner(),
                const SizedBox(height: 16),

                // Action Banner: Pelacak Lari & Kardio
                _buildRunTrackerBanner(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brightBlue.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.asset(
                      'assets/images/veyora-main.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'VEYORA',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Your Body. Your Rhythm.',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        // Refresh / Status Pill
        GestureDetector(
          onTap: _loadLatestMeasurement,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: AppColors.border.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.statusRelaxed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Sensor Siap',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroAnatomicalHeart() {
    return SizedBox(
      height: 320,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background soft radial glow behind heart
          Container(
            width: 230,
            height: 230,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.coralRed.withValues(alpha: 0.20),
                  AppColors.softPink.withValues(alpha: 0.05),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Central 3D Anatomical Heart Image (Cukup besar & Center di tengah)
          Center(
            child: Hero(
              tag: 'heart_illustration',
              child: Image.asset(
                'assets/images/heart.png',
                height: 295,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.favorite_rounded,
                    size: 170,
                    color: AppColors.coralRed.withValues(alpha: 0.85),
                  );
                },
              ),
            ),
          ),

          // Floating Glass Card 1 (Top Left): Heart Rate badge dengan soft glassmorphism tembus pandang
          Positioned(
            left: 32,
            top: 30,
            child: GlassmorphismCard(
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              blur: 1.0,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.65),
                width: 1.2,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              borderRadius: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite_border_rounded, size: 14, color: AppColors.coralRed),
                      const SizedBox(width: 4),
                      Text(
                        'Heart Rate',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _latestMeasurement != null ? _latestMeasurement!.bpm.toStringAsFixed(0) : '72',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'bpm',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Floating Glass Card 2 (Bottom Right): RMSSD / Vagal Tone tembus pandang
          Positioned(
            right: 32,
            bottom: 25,
            child: GlassmorphismCard(
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              blur: 1.0,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.65),
                width: 1.2,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              borderRadius: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.show_chart_rounded, size: 14, color: AppColors.brightBlue),
                      const SizedBox(width: 4),
                      Text(
                        'HRV (RMSSD)',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _latestMeasurement != null ? _latestMeasurement!.rmssd.toStringAsFixed(1) : '42.5',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'ms',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHrvMetricsGrid() {
    final hasData = _latestMeasurement != null;
    final status = _latestMeasurement?.stressStatus ?? 'Rileks';
    final rmssd = _latestMeasurement?.rmssd ?? 42.5;
    final lfHf = _latestMeasurement?.lfHfRatio ?? 1.45;
    final dateStr = hasData
        ? DateFormat('dd MMM, HH:mm').format(_latestMeasurement!.timestamp)
        : 'Belum diukur';

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.25,
      children: [
        // Card 1: Status Stres AI
        GlassmorphismCard(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          onTap: () => widget.onNavigateTab(3), // riwayat
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Status Stres',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Icon(Icons.psychology_outlined, size: 18, color: AppColors.brightBlue),
                ],
              ),
              StatusBadge(status: status),
              Text(
                'AI Model RF (SWELL)',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        // Card 2: RMSSD (Parasympathetic / Vagal)
        GlassmorphismCard(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'HRV RMSSD',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Icon(Icons.bolt_rounded, size: 18, color: AppColors.coralRed),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    rmssd.toStringAsFixed(1),
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'ms',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Text(
                rmssd >= 35 ? 'Aktivitas vagal optimal' : 'Aktivitas vagal menurun',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: rmssd >= 35 ? AppColors.statusRelaxed : AppColors.coralRed,
                ),
              ),
            ],
          ),
        ),

        // Card 3: LF/HF Ratio (Sympathovagal Balance)
        GlassmorphismCard(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Rasio LF/HF',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Icon(Icons.balance_rounded, size: 18, color: AppColors.brightBlue),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    lfHf.toStringAsFixed(2),
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'ratio',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Text(
                lfHf <= 2.2 ? 'Keseimbangan otonom baik' : 'Dominasi simpatis (stres)',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: lfHf <= 2.2 ? AppColors.statusRelaxed : AppColors.statusMild,
                ),
              ),
            ],
          ),
        ),

        // Card 4: Waktu Pengukuran Terakhir
        GlassmorphismCard(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          onTap: () => widget.onNavigateTab(1), // ke tab Ukur
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Perekaman',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Icon(Icons.camera_alt_outlined, size: 18, color: AppColors.brightBlue),
                ],
              ),
              Text(
                dateStr,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Row(
                children: [
                  Text(
                    'Ukur Ulang',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brightBlue,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 13, color: AppColors.brightBlue),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBreathingBanner() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.border.withValues(alpha: 0.35),
            offset: const Offset(0, 6),
            blurRadius: 18,
            spreadRadius: -2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.softPink.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.air_rounded,
              color: AppColors.coralRed,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Box Breathing 4-4-4-4',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Terapi relaksasi napas terbukti menurunkan kortisol dan menstabilkan HRV.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => widget.onNavigateTab(2), // ke tab Napas
            icon: const Icon(
              Icons.play_circle_fill_rounded,
              color: AppColors.brightBlue,
              size: 34,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunTrackerBanner() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.border.withValues(alpha: 0.35),
            offset: const Offset(0, 6),
            blurRadius: 18,
            spreadRadius: -2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.brightBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.directions_run_rounded,
              color: AppColors.brightBlue,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pelacak Lari & Kardio',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Hitung jarak lari (GPS), durasi, pace, dan pantau pemulihan detak jantung.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RunTrackerScreen(
                    onNavigateTab: widget.onNavigateTab,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brightBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              elevation: 0,
            ),
            child: Text(
              'Mulai',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
