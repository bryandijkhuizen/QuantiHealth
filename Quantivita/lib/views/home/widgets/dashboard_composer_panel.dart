import 'package:flutter/material.dart';

import '../../../models/dashboard_snapshot.dart';
import '../../../models/dashboard_widget_id.dart';
import '../../../models/fitness_summary.dart';
import '../../../models/stress_monitor.dart';
import '../../../theme/quantivita_colors.dart';
import '../../../widgets/score_ring.dart';
import '../../../widgets/sparkline.dart';

class DashboardComposerButton extends StatelessWidget {
  const DashboardComposerButton({
    required this.snapshot,
    required this.enabledWidgets,
    required this.fitnessSummary,
    required this.stressMonitor,
    required this.onSave,
    super.key,
  });

  final DashboardSnapshot snapshot;
  final Set<DashboardWidgetId> enabledWidgets;
  final FitnessSummary fitnessSummary;
  final StressMonitor stressMonitor;
  final ValueChanged<Set<DashboardWidgetId>> onSave;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => showDashboardBuilderSheet(
          context: context,
          snapshot: snapshot,
          enabledWidgets: enabledWidgets,
          fitnessSummary: fitnessSummary,
          stressMonitor: stressMonitor,
          onSave: onSave,
        ),
        icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
        label: Text('${enabledWidgets.length} widgets active'),
        style: TextButton.styleFrom(
          foregroundColor: QuantivitaColors.recovery,
          backgroundColor: QuantivitaColors.recovery.withValues(alpha: 0.14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

Future<void> showDashboardBuilderSheet({
  required BuildContext context,
  required DashboardSnapshot snapshot,
  required Set<DashboardWidgetId> enabledWidgets,
  required FitnessSummary fitnessSummary,
  required StressMonitor stressMonitor,
  required ValueChanged<Set<DashboardWidgetId>> onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (context) => _DashboardBuilderSheet(
      snapshot: snapshot,
      initialWidgets: enabledWidgets,
      fitnessSummary: fitnessSummary,
      stressMonitor: stressMonitor,
      onSave: onSave,
    ),
  );
}

class _DashboardBuilderSheet extends StatefulWidget {
  const _DashboardBuilderSheet({
    required this.snapshot,
    required this.initialWidgets,
    required this.fitnessSummary,
    required this.stressMonitor,
    required this.onSave,
  });

  final DashboardSnapshot snapshot;
  final Set<DashboardWidgetId> initialWidgets;
  final FitnessSummary fitnessSummary;
  final StressMonitor stressMonitor;
  final ValueChanged<Set<DashboardWidgetId>> onSave;

  @override
  State<_DashboardBuilderSheet> createState() => _DashboardBuilderSheetState();
}

class _DashboardBuilderSheetState extends State<_DashboardBuilderSheet> {
  late Set<DashboardWidgetId> draftWidgets;

  @override
  void initState() {
    super.initState();
    draftWidgets = Set<DashboardWidgetId>.from(widget.initialWidgets);
  }

  void _toggle(DashboardWidgetId widgetId) {
    setState(() {
      if (!draftWidgets.add(widgetId)) {
        draftWidgets.remove(widgetId);
      }

      if (draftWidgets.isEmpty) {
        draftWidgets.add(DashboardWidgetId.readiness);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleWidgets = DashboardWidgetId.values
        .where(draftWidgets.contains)
        .toList(growable: false);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.96,
      minChildSize: 0.72,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  Text(
                    'Edit Home',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      widget.onSave(draftWidgets);
                      Navigator.pop(context);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final widgetId in DashboardWidgetId.values)
                        FilterChip(
                          selected: draftWidgets.contains(widgetId),
                          onSelected: (_) => _toggle(widgetId),
                          label: Text(widgetId.label),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  for (final widgetId in visibleWidgets) ...[
                    _BuilderPreviewCard(
                      title: widgetId.label,
                      onRemove: () => _toggle(widgetId),
                      child: _BuilderPreviewContent(
                        widgetId: widgetId,
                        snapshot: widget.snapshot,
                        fitnessSummary: widget.fitnessSummary,
                        stressMonitor: widget.stressMonitor,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BuilderPreviewCard extends StatelessWidget {
  const _BuilderPreviewCard({
    required this.title,
    required this.onRemove,
    required this.child,
  });

  final String title;
  final VoidCallback onRemove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
        Positioned(
          left: -8,
          top: -8,
          child: IconButton.filledTonal(
            onPressed: onRemove,
            icon: const Icon(Icons.remove_rounded),
            tooltip: 'Remove $title',
          ),
        ),
      ],
    );
  }
}

class _BuilderPreviewContent extends StatelessWidget {
  const _BuilderPreviewContent({
    required this.widgetId,
    required this.snapshot,
    required this.fitnessSummary,
    required this.stressMonitor,
  });

  final DashboardWidgetId widgetId;
  final DashboardSnapshot snapshot;
  final FitnessSummary fitnessSummary;
  final StressMonitor stressMonitor;

  @override
  Widget build(BuildContext context) {
    return switch (widgetId) {
      DashboardWidgetId.readiness => _DailyOverviewPreview(snapshot: snapshot),
      DashboardWidgetId.metrics => _MetricsPreview(snapshot: snapshot),
      DashboardWidgetId.stress => _StressPreview(monitor: stressMonitor),
    };
  }
}

class _DailyOverviewPreview extends StatelessWidget {
  const _DailyOverviewPreview({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MiniRing(
                label: 'Battery',
                score: snapshot.bodyBatteryScore,
                color: QuantivitaColors.recovery,
              ),
              _MiniRing(
                label: 'Recovery',
                score: snapshot.recoveryScore,
                color: QuantivitaColors.recovery,
              ),
              _MiniRing(
                label: 'Sleep',
                score: 88,
                color: QuantivitaColors.sleep,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'COACHING',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            snapshot.bodyBatterySummary,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _MiniRing extends StatelessWidget {
  const _MiniRing({
    required this.label,
    required this.score,
    required this.color,
  });

  final String label;
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Transform.scale(
          scale: 0.58,
          child: ScoreRing(score: score, color: color, label: ''),
        ),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _MetricsPreview extends StatelessWidget {
  const _MetricsPreview({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final metric in snapshot.metrics.take(3)) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(metric.icon, color: metric.color),
                const SizedBox(height: 8),
                Text(
                  metric.value,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  metric.title,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StressPreview extends StatelessWidget {
  const _StressPreview({required this.monitor});

  final StressMonitor monitor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _PreviewStat(
                label: 'Highest',
                value: '${monitor.highest}',
                color: QuantivitaColors.strain,
              ),
            ),
            Expanded(
              child: _PreviewStat(
                label: 'Lowest',
                value: '${monitor.lowest}',
                color: QuantivitaColors.sleep,
              ),
            ),
            Expanded(
              child: _PreviewStat(
                label: 'Average',
                value: '${monitor.average}',
                color: QuantivitaColors.recovery,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: Sparkline(
            values: monitor.samples,
            color: QuantivitaColors.sleep,
          ),
        ),
      ],
    );
  }
}

class _PreviewStat extends StatelessWidget {
  const _PreviewStat({
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
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
