import 'package:flutter/material.dart';

import '../../../models/stress_monitor.dart';
import '../../../theme/quantivita_colors.dart';
import '../../../widgets/panel.dart';

class StressMonitorPanel extends StatelessWidget {
  const StressMonitorPanel({
    required this.monitor,
    required this.selectedFilter,
    required this.onFilterChanged,
    super.key,
  });

  final StressMonitor monitor;
  final StressFilter selectedFilter;
  final ValueChanged<StressFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.ssid_chart_rounded,
                color: QuantivitaColors.sleep,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Stress Monitor',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _ScoreBadge(score: monitor.score),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in StressFilter.values) ...[
                  ChoiceChip(
                    selected: filter == selectedFilter,
                    onSelected: (_) => onFilterChanged(filter),
                    label: Text(filter.label),
                  ),
                  if (filter != StressFilter.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(height: 168, child: _StressGraph(samples: monitor.samples)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StressStat(
                  label: 'Highest',
                  value: '${monitor.highest}',
                  color: QuantivitaColors.strain,
                ),
              ),
              Expanded(
                child: _StressStat(
                  label: 'Lowest',
                  value: '${monitor.lowest}',
                  color: QuantivitaColors.sleep,
                ),
              ),
              Expanded(
                child: _StressStat(
                  label: 'Average',
                  value: '${monitor.average}',
                  color: QuantivitaColors.recovery,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ZoneRow(
            label: 'Low',
            percent: monitor.lowPercent,
            duration: monitor.duration,
            color: QuantivitaColors.sleep,
          ),
          const SizedBox(height: 8),
          _ZoneRow(
            label: 'Med',
            percent: monitor.mediumPercent,
            duration: '0:30:00',
            color: QuantivitaColors.strain,
          ),
          const SizedBox(height: 8),
          _ZoneRow(
            label: 'High',
            percent: monitor.highPercent,
            duration: '0:00:00',
            color: QuantivitaColors.activity,
          ),
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$score', style: Theme.of(context).textTheme.titleLarge),
          Text('Low', style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _StressStat extends StatelessWidget {
  const _StressStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.label,
    required this.percent,
    required this.duration,
    required this.color,
  });

  final String label;
  final int percent;
  final String duration;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 9,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 78,
          child: Text(
            '$percent% $duration',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}

class _StressGraph extends StatelessWidget {
  const _StressGraph({required this.samples});

  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StressGraphPainter(
        samples: samples,
        gridColor: Theme.of(context).colorScheme.outline,
      ),
      size: Size.infinite,
    );
  }
}

class _StressGraphPainter extends CustomPainter {
  const _StressGraphPainter({required this.samples, required this.gridColor});

  final List<double> samples;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final bandPaint = Paint()
      ..color = QuantivitaColors.sleep.withValues(alpha: 0.08);
    final linePaint = Paint()
      ..shader = const LinearGradient(
        colors: [QuantivitaColors.sleep, QuantivitaColors.strain],
      ).createShader(Offset.zero & size)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * 0.32, size.height),
      bandPaint,
    );

    for (final yFactor in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final y = size.height * yFactor;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (samples.length < 2) return;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = size.width * i / (samples.length - 1);
      final y = size.height - samples[i].clamp(0, 1) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _StressGraphPainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.gridColor != gridColor;
  }
}
