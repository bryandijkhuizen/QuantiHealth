import 'package:flutter/material.dart';

import '../../models/sleep_summary.dart';
import '../../theme/quantivita_colors.dart';
import '../../widgets/panel.dart';
import '../../widgets/score_ring.dart';
import '../../widgets/sparkline.dart';

class SleepDetailPage extends StatelessWidget {
  const SleepDetailPage({required this.summary, super.key});

  final SleepSummary summary;

  @override
  Widget build(BuildContext context) {
    final stages = [
      (
        'Core',
        summary.coreMinutes,
        QuantivitaColors.sleep,
        'Commonly the largest block; supports settling, memory, and continuity.',
      ),
      (
        'REM',
        summary.remMinutes,
        QuantivitaColors.stress,
        'Often linked with dreaming, emotional processing, and learning.',
      ),
      (
        'Deep',
        summary.deepMinutes,
        QuantivitaColors.recovery,
        'The most physically restorative stage; tends to decrease with age.',
      ),
      (
        'Awake',
        summary.awakeMinutes,
        QuantivitaColors.strain,
        'Short awakenings are normal; too much awake time lowers efficiency.',
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
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
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
              sliver: SliverList.list(
                children: [
                  Panel(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sleep',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${summary.formatMinutes(summary.totalMinutes)} • ${summary.qualityLabel}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            ScoreRing(
                              score: summary.qualityScore,
                              color: QuantivitaColors.sleep,
                              label: 'Quality',
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 150,
                          child: Sparkline(
                            values: const [
                              0.28,
                              0.42,
                              0.7,
                              0.54,
                              0.88,
                              0.62,
                              0.76,
                            ],
                            color: QuantivitaColors.sleep,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sleep architecture',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 14),
                        for (final stage in stages) ...[
                          _StageRow(
                            label: stage.$1,
                            minutes: stage.$2,
                            total: summary.totalMinutes + summary.awakeMinutes,
                            color: stage.$3,
                            note: stage.$4,
                            formatter: summary.formatMinutes,
                          ),
                          if (stage != stages.last) const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quality factors',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _QualityFactor(
                          label: 'Duration',
                          value: '${summary.durationScore}%',
                          detail: 'Adults generally need at least 7 hours.',
                        ),
                        const Divider(height: 22),
                        _QualityFactor(
                          label: 'Efficiency',
                          value: '${(summary.efficiency * 100).round()}%',
                          detail: 'Sleep time divided by time in bed.',
                        ),
                        const Divider(height: 22),
                        _QualityFactor(
                          label: 'Stage balance',
                          value: summary.qualityLabel,
                          detail:
                              'REM and deep sleep are useful context, but trends matter more than a single night.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.minutes,
    required this.total,
    required this.color,
    required this.note,
    required this.formatter,
  });

  final String label;
  final double minutes;
  final double total;
  final Color color;
  final String note;
  final String Function(double minutes) formatter;

  @override
  Widget build(BuildContext context) {
    final fraction = total > 0 ? (minutes / total).clamp(0.02, 1.0) : 0.02;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              formatter(minutes),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 9,
            value: fraction,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        Text(note, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _QualityFactor extends StatelessWidget {
  const _QualityFactor({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(detail, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
