import 'package:flutter/material.dart';

class Sparkline extends StatelessWidget {
  const Sparkline({required this.values, required this.color, super.key});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _SparklinePainter(values: values, color: color),
        size: Size.infinite,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final path = Path();
    final fillPath = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i].clamp(0, 1) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath
      ..lineTo(size.width, size.height)
      ..close();

    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (final fraction in const [0.25, 0.5, 0.75]) {
      final y = size.height * fraction;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    final lastValue = values.last.clamp(0, 1);
    final lastPoint = Offset(size.width, size.height - lastValue * size.height);
    canvas
      ..drawCircle(lastPoint, 6, Paint()..color = color.withValues(alpha: 0.18))
      ..drawCircle(lastPoint, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
