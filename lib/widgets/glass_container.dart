import 'package:flutter/material.dart';
import 'package:welwi/theme/app_theme.dart';

/// A glass-effect container.
///
/// NOTE: BackdropFilter/ImageFilter.blur has been intentionally removed.
/// When used without an explicitly bounded parent, Impeller allocates an
/// unbounded GPU texture (~16M px tall) causing a SIGSEGV crash in the
/// JNI surface thread. The glass look is achieved via a semi-transparent
/// solid background which is visually equivalent on the app's dark theme.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? borderColor;
  final double blur; // kept for API compatibility; no longer used
  final Color? backgroundColor;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.padding,
    this.margin,
    this.borderColor,
    this.blur = 10,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surfaceLight.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? AppColors.textHint.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
  }
}
