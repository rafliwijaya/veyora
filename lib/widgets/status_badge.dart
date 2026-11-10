import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final bool isLarge;

  const StatusBadge({
    super.key,
    required this.status,
    this.isLarge = false,
  });

  Color _getStatusColor() {
    switch (status.toLowerCase()) {
      case 'rileks':
      case 'relax':
        return AppColors.statusRelaxed;
      case 'stres sedang':
      case 'sedang':
        return AppColors.statusMild;
      case 'stres tinggi':
      case 'tinggi':
      case 'stres':
        return AppColors.coralRed;
      default:
        return AppColors.brightBlue;
    }
  }

  IconData _getStatusIcon() {
    switch (status.toLowerCase()) {
      case 'rileks':
      case 'relax':
        return Icons.spa_rounded;
      case 'stres sedang':
      case 'sedang':
        return Icons.sentiment_neutral_rounded;
      case 'stres tinggi':
      case 'tinggi':
      case 'stres':
        return Icons.warning_amber_rounded;
      default:
        return Icons.favorite_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    final icon = _getStatusIcon();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLarge ? 14 : 10,
        vertical: isLarge ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: isLarge ? 18 : 14,
            color: color,
          ),
          SizedBox(width: isLarge ? 8 : 5),
          Text(
            status,
            style: GoogleFonts.inter(
              fontSize: isLarge ? 14 : 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
