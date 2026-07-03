import 'package:flutter/material.dart';

import '../../../models/body_battery_factor.dart';
import '../../../models/dashboard_snapshot.dart';
import '../../../theme/quantivita_colors.dart';
import '../../../widgets/panel.dart';
import '../../../widgets/score_ring.dart';
import '../../../widgets/signal_pill.dart';
import '../../../widgets/tiny_label.dart';

class ReadinessHero extends StatelessWidget {
  const ReadinessHero({required this.snapshot, super.key});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () => _showBodyBatteryDetails(context),
      child: Panel(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 380;
                final ring = ScoreRing(
                  score: snapshot.bodyBatteryScore,
                  color: theme.colorScheme.primary,
                  label: 'Body Battery',
                  size: compact ? 118 : 136,
                );
                final copy = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: TinyLabel('BODY BATTERY')),
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.bodyBatteryTitle,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      snapshot.bodyBatterySummary,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15),
                    ),
                  ],
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [ring, const SizedBox(height: 18), copy],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ring,
                    const SizedBox(width: 20),
                    Expanded(child: copy),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final stackSignals = constraints.maxWidth < 380;
                final sleep = SignalPill(
                  icon: Icons.bedtime_rounded,
                  label: 'Sleep',
                  value: snapshot.sleepDuration,
                );
                final recovery = SignalPill(
                  icon: Icons.monitor_heart_rounded,
                  label: 'Recovery',
                  value: '${snapshot.recoveryScore}%',
                );

                if (stackSignals) {
                  return Column(
                    children: [sleep, const SizedBox(height: 10), recovery],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: sleep),
                    const SizedBox(width: 12),
                    Expanded(child: recovery),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBodyBatteryDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BodyBatterySheet(snapshot: snapshot),
    );
  }
}

class _BodyBatterySheet extends StatelessWidget {
  const _BodyBatterySheet({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TinyLabel('BODY BATTERY BREAKDOWN'),
                      const SizedBox(height: 8),
                      Text(
                        '${snapshot.bodyBatteryScore}/100',
                        style: theme.textTheme.displaySmall,
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              snapshot.bodyBatterySummary,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _BreakdownStat(
                    label: 'Recovery confidence',
                    value: '${(snapshot.recoveryConfidence * 100).round()}%',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BreakdownStat(
                    label: 'Sleep need',
                    value: snapshot.sleepNeed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _BreakdownStat(
              label: 'Sleep performance',
              value: '${snapshot.sleepPerformanceScore}%',
              detail: snapshot.sleepNeedSummary,
            ),
            const SizedBox(height: 18),
            for (final factor in snapshot.bodyBatteryFactors) ...[
              _BodyBatteryFactorRow(factor: factor),
              const SizedBox(height: 10),
            ],
            const Divider(height: 22),
            Text('Formula', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Sleep and recovery build the reserve. Active kcal, steps, daily strain, and stress drain it. Low-stress periods can add a small recharge.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownStat extends StatelessWidget {
  const _BreakdownStat({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 5),
          Text(value, style: theme.textTheme.titleLarge),
          if (detail != null) ...[
            const SizedBox(height: 5),
            Text(detail!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _BodyBatteryFactorRow extends StatelessWidget {
  const _BodyBatteryFactorRow({required this.factor});

  final BodyBatteryFactor factor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = factor.points >= 0;
    final color = positive
        ? QuantivitaColors.recovery
        : QuantivitaColors.strain;
    final points = factor.points.abs();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              positive ? Icons.add_rounded : Icons.remove_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(factor.label, style: theme.textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(factor.detail, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          Text(
            '${positive ? '+' : '-'}${points.toStringAsFixed(1)}',
            style: theme.textTheme.titleMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
