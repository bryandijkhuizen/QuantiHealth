import 'package:flutter/material.dart';

import '../../../models/dashboard_snapshot.dart';
import '../../../models/metric_model.dart';
import '../../../theme/quantivita_colors.dart';
import '../../../widgets/bar_trend.dart';
import '../../../widgets/panel.dart';
import '../../../widgets/sparkline.dart';

class HealthDetailsPanel extends StatelessWidget {
  const HealthDetailsPanel({
    required this.snapshot,
    required this.onMetricTap,
    super.key,
  });

  final DashboardSnapshot snapshot;
  final ValueChanged<MetricModel> onMetricTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.query_stats_rounded,
                color: QuantivitaColors.sleep,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _RecoveryDetail(snapshot: snapshot),
          const SizedBox(height: 14),
          for (final metric in snapshot.metrics) ...[
            _MetricDetail(metric: metric, onTap: onMetricTap),
            if (metric != snapshot.metrics.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _RecoveryDetail extends StatelessWidget {
  const _RecoveryDetail({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _DetailShell(
      icon: Icons.health_and_safety_rounded,
      title: 'Recovery',
      value: '${snapshot.recoveryScore}',
      color: QuantivitaColors.recovery,
      child: SizedBox(height: 96, child: BarTrend(values: snapshot.weekValues)),
    );
  }
}

class _MetricDetail extends StatelessWidget {
  const _MetricDetail({required this.metric, required this.onTap});

  final MetricModel metric;
  final ValueChanged<MetricModel> onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(metric),
      borderRadius: BorderRadius.circular(16),
      child: _DetailShell(
        icon: metric.icon,
        title: metric.title,
        value: metric.unit.isEmpty
            ? metric.value
            : '${metric.value} ${metric.unit}',
        color: metric.color,
        child: SizedBox(
          height: 62,
          child: Sparkline(values: metric.samples, color: metric.color),
        ),
      ),
    );
  }
}

class _DetailShell extends StatelessWidget {
  const _DetailShell({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
