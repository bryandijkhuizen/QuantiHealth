import 'dart:math' as math;

import 'package:flutter/material.dart';

class ScoreRing extends StatelessWidget {
  const ScoreRing({
    required this.score,
    required this.color,
    required this.label,
    this.size = 118,
    super.key,
  });

  final int score;
  final Color color;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                progress: score / 100,
                color: color,
                trackColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$score',
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(letterSpacing: 0),
                ),
                const SizedBox(height: 2),
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 12.0;
    final rect = Offset.zero & size;
    final insetRect = rect.deflate(strokeWidth / 2);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [color.withValues(alpha: 0.35), color],
      ).createShader(insetRect);

    canvas.drawArc(insetRect, 0, math.pi * 2, false, basePaint);
    canvas.drawArc(
      insetRect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
