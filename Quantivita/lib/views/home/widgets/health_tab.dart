import 'package:flutter/material.dart';

import '../../../models/dashboard_snapshot.dart';
import '../../../models/metric_model.dart';
import '../../../models/stress_monitor.dart';
import '../../../theme/quantivita_colors.dart';
import '../../../widgets/panel.dart';
import 'health_details_panel.dart';
import 'stress_monitor_panel.dart';

class HealthTab extends StatelessWidget {
  const HealthTab({
    required this.snapshot,
    required this.stressMonitor,
    required this.stressFilter,
    required this.onStressFilterChanged,
    required this.onMetricTap,
    super.key,
  });

  final DashboardSnapshot snapshot;
  final StressMonitor stressMonitor;
  final StressFilter stressFilter;
  final ValueChanged<StressFilter> onStressFilterChanged;
  final ValueChanged<MetricModel> onMetricTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HealthSummary(snapshot: snapshot),
        const SizedBox(height: 14),
        StressMonitorPanel(
          monitor: stressMonitor,
          selectedFilter: stressFilter,
          onFilterChanged: onStressFilterChanged,
        ),
        const SizedBox(height: 14),
        HealthDetailsPanel(snapshot: snapshot, onMetricTap: onMetricTap),
      ],
    );
  }
}

class _HealthSummary extends StatelessWidget {
  const _HealthSummary({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.health_and_safety_rounded,
                color: QuantivitaColors.recovery,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Health signals',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${snapshot.recoveryScore}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: QuantivitaColors.recovery,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'These readings are pulled from Apple Health on-device. Quantivita will use them to build your personal baseline over time.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _FactorPill(
                  label: 'Sleep',
                  value: snapshot.sleepDuration,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FactorPill(label: 'HRV', value: snapshot.hrvDelta),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FactorPill extends StatelessWidget {
  const _FactorPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
