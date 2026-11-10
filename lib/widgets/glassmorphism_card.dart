import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Kartu bergaya Soft Glassmorphism dengan sudut membulat 18-22dp,
/// efek blur lembut, dan bayangan halus untuk kesan melayang (floating).
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
    final cardContent = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor ?? AppColors.cardWhite.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(borderRadius),
            border: border ??
                Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 1.2,
                ),
            boxShadow: [
              BoxShadow(
                color: AppColors.border.withValues(alpha: 0.45),
                offset: const Offset(0, 8),
                blurRadius: 20,
                spreadRadius: -4,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.8),
                offset: const Offset(-2, -2),
                blurRadius: 10,
                spreadRadius: 0,
              ),
            ],
          ),
          child: child,
        ),
      ),
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
