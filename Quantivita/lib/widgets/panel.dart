import 'dart:ui';

import 'package:flutter/material.dart';

class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(28);
    final surface = theme.colorScheme.surface;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(
                  surface,
                  Colors.white,
                  isDark ? 0.10 : 0.88,
                )!.withValues(alpha: isDark ? 0.78 : 0.86),
                Color.lerp(
                  theme.colorScheme.surfaceContainerHighest,
                  Colors.white,
                  isDark ? 0.06 : 0.58,
                )!.withValues(alpha: isDark ? 0.62 : 0.74),
              ],
            ),
            borderRadius: radius,
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.11)
                  : Colors.white.withValues(alpha: 0.84),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.06),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
