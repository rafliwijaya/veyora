import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PpgWaveformWidget extends StatelessWidget {
  final List<double> signal;
  final Color lineColor;
  final double strokeWidth;
  final bool showGrid;

  const PpgWaveformWidget({
    super.key,
    required this.signal,
    this.lineColor = AppColors.brightBlue,
    this.strokeWidth = 2.0,
    this.showGrid = true,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: Colors.white.withValues(alpha: 0.4),
        child: CustomPaint(
          size: Size.infinite,
          painter: _PpgWaveformPainter(
            signal: signal,
            lineColor: lineColor,
            strokeWidth: strokeWidth,
            showGrid: showGrid,
          ),
        ),
      ),
    );
  }
}

class _PpgWaveformPainter extends CustomPainter {
  final List<double> signal;
  final Color lineColor;
  final double strokeWidth;
  final bool showGrid;

  _PpgWaveformPainter({
    required this.signal,
    required this.lineColor,
    required this.strokeWidth,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Gambar grid medis lembut
    if (showGrid) {
      final gridPaint = Paint()
        ..color = AppColors.border.withValues(alpha: 0.35)
        ..strokeWidth = 0.6;

      const vSpacing = 24.0;
      const hSpacing = 24.0;

      for (double y = 0; y < h; y += hSpacing) {
        canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
      }
      for (double x = 0; x < w; x += vSpacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
      }
    }

    if (signal.isEmpty) {
      // Baseline flat line jika belum ada data
      final basePaint = Paint()
        ..color = lineColor.withValues(alpha: 0.3)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(0, h * 0.5), Offset(w, h * 0.5), basePaint);
      return;
    }

    // Ambil maksimal N sampel terakhir yang muat
    final int maxPoints = min(signal.length, 120);
    final visibleSignal = signal.sublist(signal.length - maxPoints);

    // Cari min & max untuk normalisasi vertikal
    double minVal = visibleSignal.reduce(min);
    double maxVal = visibleSignal.reduce(max);
    if ((maxVal - minVal).abs() < 1e-4) {
      minVal -= 1.0;
      maxVal += 1.0;
    }

    final path = Path();
    final stepX = w / (maxPoints - 1);

    for (int i = 0; i < maxPoints; i++) {
      final normY = (visibleSignal[i] - minVal) / (maxVal - minVal);
      // Invert Y karena canvas origin di kiri atas, beri padding vertikal 15%
      final y = h * 0.85 - (normY * h * 0.70);
      final x = i * stepX;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Gambar bayangan glow di bawah garis
    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, glowPaint);

    // Gambar garis utama
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Titik pulsa di ujung kanan sinyal terkini
    if (maxPoints > 0) {
      final lastNormY = (visibleSignal.last - minVal) / (maxVal - minVal);
      final lastY = h * 0.85 - (lastNormY * h * 0.70);
      final lastX = (maxPoints - 1) * stepX;

      final dotPaint = Paint()..color = lineColor;
      canvas.drawCircle(Offset(lastX, lastY), 4.5, dotPaint);

      final pulsePaint = Paint()
        ..color = lineColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(lastX, lastY), 8.0, pulsePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PpgWaveformPainter oldDelegate) {
    return true; // selalu repaint saat sinyal bertambah
  }
}
