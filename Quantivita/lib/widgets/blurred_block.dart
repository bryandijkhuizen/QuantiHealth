import 'package:flutter/material.dart';

class BlurredBlock extends StatelessWidget {
  const BlurredBlock({
    required this.height,
    this.width = double.infinity,
    this.radius = 14,
    super.key,
  });

  final double height;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        gradient: LinearGradient(
          colors: [
            Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
            Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
            Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
          ],
          stops: const [0, 0.48, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}
