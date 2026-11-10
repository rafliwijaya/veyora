import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Blue Highlight Card: Kartu sorotan biru terang (#4692F6) untuk menonjolkan
/// informasi utama (Heart Rate Monitor / Real-time BPM) dengan garis grafik detak jantung tipis putih.
class BlueHighlightCard extends StatelessWidget {
  final double bpm;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const BlueHighlightCard({
    super.key,
    required this.bpm,
    this.title = 'Heart Rate Monitor',
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF5CA3FF),
              AppColors.brightBlue,
              Color(0xFF2979E6),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.brightBlue.withValues(alpha: 0.38),
              offset: const Offset(0, 10),
              blurRadius: 24,
              spreadRadius: -2,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Row: Icon + Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite_border_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                ),
                if (subtitle != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      subtitle!,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // BPM Number Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  bpm > 0 ? bpm.toStringAsFixed(0) : '--',
                  style: GoogleFonts.inter(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'bpm',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Subtle ECG pulse line visualization
            SizedBox(
              height: 38,
              width: double.infinity,
              child: CustomPaint(
                painter: _MiniEcgPainter(color: Colors.white.withValues(alpha: 0.75)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniEcgPainter extends CustomPainter {
  final Color color;
  _MiniEcgPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final h = size.height;
    final mid = h * 0.55;
    final w = size.width;

    path.moveTo(0, mid);
    path.lineTo(w * 0.15, mid);
    path.lineTo(w * 0.20, mid - 4); // P wave
    path.lineTo(w * 0.25, mid);
    path.lineTo(w * 0.30, mid);
    path.lineTo(w * 0.33, mid + 5); // Q
    path.lineTo(w * 0.38, mid - 22); // R peak
    path.lineTo(w * 0.43, mid + 12); // S
    path.lineTo(w * 0.47, mid);
    path.lineTo(w * 0.54, mid - 7); // T wave
    path.lineTo(w * 0.60, mid);
    path.lineTo(w * 0.70, mid);
    path.lineTo(w * 0.73, mid + 4);
    path.lineTo(w * 0.78, mid - 18);
    path.lineTo(w * 0.82, mid + 9);
    path.lineTo(w * 0.86, mid);
    path.lineTo(w, mid);

    canvas.drawPath(path, paint);

    // Subtle faint baseline grid line
    final baseLinePaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(0, mid + 10), Offset(w, mid + 10), baseLinePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
