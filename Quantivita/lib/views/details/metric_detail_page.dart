import 'package:flutter/material.dart';

import '../../models/metric_model.dart';
import '../../theme/quantivita_colors.dart';
import '../../widgets/sparkline.dart';

class MetricDetailPage extends StatelessWidget {
  const MetricDetailPage({required this.metric, super.key});

  final MetricModel metric;

  @override
  Widget build(BuildContext context) {
    final displayValue = metric.unit.isEmpty
        ? metric.value
        : '${metric.value} ${metric.unit}';

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Spacer(),
                    IconButton.filledTonal(
                      onPressed: () {},
                      icon: const Icon(Icons.ios_share_rounded),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () {},
                      icon: const Icon(Icons.info_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 110),
              sliver: SliverList.list(
                children: [
                  _Hero(metric: metric, displayValue: displayValue),
                  const SizedBox(height: 16),
                  _StatGrid(metric: metric),
                  const SizedBox(height: 16),
                  _TrendCard(metric: metric),
                  const SizedBox(height: 16),
                  _CoachingCard(metric: metric),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.metric, required this.displayValue});

  final MetricModel metric;
  final String displayValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(metric.icon, color: metric.color, size: 34),
          const SizedBox(height: 12),
          Text(metric.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('Today, 28 May', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          Text(displayValue, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 8),
          Text(metric.caption, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 22),
          SizedBox(
            height: 180,
            child: Sparkline(values: metric.samples, color: metric.color),
          ),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.metric});

  final MetricModel metric;

  @override
  Widget build(BuildContext context) {
    final lowest = metric.samples.reduce((a, b) => a < b ? a : b);
    final highest = metric.samples.reduce((a, b) => a > b ? a : b);
    final average =
        metric.samples.reduce((a, b) => a + b) / metric.samples.length;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Lowest',
            value: '${(lowest * 100).round()}',
            color: QuantivitaColors.sleep,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Average',
            value: '${(average * 100).round()}',
            color: QuantivitaColors.recovery,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Highest',
            value: '${(highest * 100).round()}',
            color: metric.color,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: color),
          ),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.metric});

  final MetricModel metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up_rounded, color: metric.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Trends',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: Sparkline(
              values: metric.samples.reversed.toList(),
              color: metric.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachingCard extends StatelessWidget {
  const _CoachingCard({required this.metric});

  final MetricModel metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Coaching', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Text(
            'Your ${metric.title.toLowerCase()} data is being collected locally. More history will unlock baseline comparisons and stronger coaching.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
