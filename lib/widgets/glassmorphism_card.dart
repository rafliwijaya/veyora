import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Kartu bergaya Modern Soft Surface / Glassmorphism Ringan.
/// Dioptimalkan untuk performa 60-120 FPS tanpa BackdropFilter blur berat saat di-scroll.
class GlassmorphismCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final double blur;
  final Border? border;

  const GlassmorphismCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18.0),
    this.margin,
    this.borderRadius = 20.0,
    this.onTap,
    this.backgroundColor,
    this.blur = 12.0,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    // Gunakan warna semi-transparan dengan border lembut dan shadow ringan
    // Menghasilkan tampilan glassmorphism yang identik secara visual tanpa membebani GPU render loop
    final effectiveBg = backgroundColor ?? Colors.white.withValues(alpha: 0.88);

    final cardContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ??
            Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 1.2,
            ),
        boxShadow: [
          BoxShadow(
            color: AppColors.border.withValues(alpha: 0.35),
            offset: const Offset(0, 4),
            blurRadius: 12,
            spreadRadius: -2,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.6),
            offset: const Offset(-1, -1),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      return Container(
        margin: margin,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(borderRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: onTap,
            child: cardContent,
          ),
        ),
      );
    }

    return Container(
      margin: margin,
      child: cardContent,
    );
  }
}
