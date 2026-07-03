import 'package:flutter/material.dart';

import '../../../models/dashboard_snapshot.dart';
import '../../../models/dashboard_widget_id.dart';
import '../../../models/fitness_summary.dart';
import '../../../models/metric_model.dart';
import '../../../models/stress_monitor.dart';
import '../../../theme/quantivita_colors.dart';
import 'dashboard_composer_panel.dart';
import 'health_monitor_panel.dart';
import 'metrics_grid.dart';
import 'nutrition_panel.dart';
import '../../../widgets/panel.dart';
import 'readiness_hero.dart';
import 'stress_monitor_panel.dart';

class TodayTab extends StatelessWidget {
  const TodayTab({
    required this.snapshot,
    required this.enabledWidgets,
    required this.fitnessSummary,
    required this.stressMonitor,
    required this.stressFilter,
    required this.onMetricTap,
    required this.onDashboardWidgetsChanged,
    required this.onStressFilterChanged,
    required this.onWorkoutTap,
    required this.selectedWorkoutDate,
    required this.onWorkoutDateChanged,
    required this.onWorkoutDateShifted,
    super.key,
  });

  final DashboardSnapshot snapshot;
  final Set<DashboardWidgetId> enabledWidgets;
  final FitnessSummary fitnessSummary;
  final StressMonitor stressMonitor;
  final StressFilter stressFilter;
  final ValueChanged<MetricModel> onMetricTap;
  final ValueChanged<Set<DashboardWidgetId>> onDashboardWidgetsChanged;
  final ValueChanged<StressFilter> onStressFilterChanged;
  final ValueChanged<FitnessEventSummary> onWorkoutTap;
  final DateTime selectedWorkoutDate;
  final ValueChanged<DateTime> onWorkoutDateChanged;
  final ValueChanged<int> onWorkoutDateShifted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DashboardComposerButton(
          snapshot: snapshot,
          enabledWidgets: enabledWidgets,
          fitnessSummary: fitnessSummary,
          stressMonitor: stressMonitor,
          onSave: onDashboardWidgetsChanged,
        ),
        const SizedBox(height: 14),
        if (enabledWidgets.contains(DashboardWidgetId.readiness)) ...[
          ReadinessHero(snapshot: snapshot),
          const SizedBox(height: 14),
        ],
        if (enabledWidgets.contains(DashboardWidgetId.metrics)) ...[
          MetricsGrid(metrics: snapshot.metrics, onMetricTap: onMetricTap),
          const SizedBox(height: 14),
        ],
        DailyWorkoutsPanel(
          summary: fitnessSummary,
          selectedDate: selectedWorkoutDate,
          onDateChanged: onWorkoutDateChanged,
          onDateShifted: onWorkoutDateShifted,
          onWorkoutTap: onWorkoutTap,
        ),
        const SizedBox(height: 14),
        if (enabledWidgets.contains(DashboardWidgetId.stress)) ...[
          StressMonitorPanel(
            monitor: stressMonitor,
            selectedFilter: stressFilter,
            onFilterChanged: onStressFilterChanged,
          ),
          const SizedBox(height: 14),
        ],
        HealthMonitorPanel(snapshot: snapshot),
        const SizedBox(height: 14),
        NutritionPanel(snapshot: snapshot),
        const SizedBox(height: 14),
      ],
    );
  }
}

class DailyWorkoutsPanel extends StatelessWidget {
  const DailyWorkoutsPanel({
    required this.summary,
    required this.selectedDate,
    required this.onDateChanged,
    required this.onDateShifted,
    required this.onWorkoutTap,
    super.key,
  });

  final FitnessSummary summary;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<int> onDateShifted;
  final ValueChanged<FitnessEventSummary> onWorkoutTap;

  @override
  Widget build(BuildContext context) {
    final events = summary.eventsForDate(selectedDate)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final progressaEvents = events.where((event) => event.isProgressa).toList();
    final totalSets = progressaEvents.fold<int>(
      0,
      (sum, event) => sum + event.progressaSetCount,
    );
    final volumeEvents = progressaEvents.where(
      (event) => event.hasProgressaVolumeData,
    );
    final totalVolume = volumeEvents.fold<double>(
      0,
      (sum, event) => sum + event.progressaVolumeKg,
    );

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                color: QuantivitaColors.recovery,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Workouts',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Previous day',
                onPressed: () => onDateShifted(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 730),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) onDateChanged(picked);
                },
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(_dateLabel(selectedDate)),
              ),
              IconButton(
                tooltip: 'Next day',
                onPressed: _isSameDay(selectedDate, DateTime.now())
                    ? null
                    : () => onDateShifted(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            events.isEmpty
                ? 'No workouts for this day yet.'
                : [
                    '${events.length} workouts today',
                    '$totalSets Progressa sets',
                    if (volumeEvents.isNotEmpty)
                      '${totalVolume.round()} kg volume',
                  ].join(' • '),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            _EmptyWorkoutState(selectedDate: selectedDate)
          else
            for (final event in events.take(6))
              _DailyWorkoutRow(event: event, onTap: () => onWorkoutTap(event)),
        ],
      ),
    );
  }
}

class _DailyWorkoutRow extends StatelessWidget {
  const _DailyWorkoutRow({required this.event, required this.onTap});

  final FitnessEventSummary event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (event.isProgressa) {
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(left: 54, bottom: 10),
          leading: _WorkoutIcon(isProgressa: event.isProgressa),
          title: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                event.displayTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          subtitle: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 4),
              child: Text(
                [
                  '${event.progressaSetCount} sets',
                  '${event.progressaExerciseCount} exercises',
                  if (event.hasProgressaVolumeData)
                    event.progressaVolumeLabel
                  else
                    'Volume unknown',
                ].join(' • '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _timeLabel(event),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open details'),
              ),
            ),
            for (final exercise in _progressaExercises(event.progressaDetails))
              _TodayProgressaExercise(exercise: exercise),
          ],
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WorkoutIcon(isProgressa: event.isProgressa),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.displayTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${event.effectiveDurationMinutes.round()} min • ${event.effectiveEnergyKcal.round()} kcal',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Text(
              _timeLabel(event),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutIcon extends StatelessWidget {
  const _WorkoutIcon({required this.isProgressa});

  final bool isProgressa;

  @override
  Widget build(BuildContext context) {
    final color = isProgressa
        ? QuantivitaColors.strain
        : QuantivitaColors.sleep;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        isProgressa
            ? Icons.fitness_center_rounded
            : Icons.directions_run_rounded,
        color: color,
      ),
    );
  }
}

class _TodayProgressaExercise extends StatelessWidget {
  const _TodayProgressaExercise({required this.exercise});

  final Map<String, Object?> exercise;

  @override
  Widget build(BuildContext context) {
    final sets = (exercise['sets'] as List? ?? const [])
        .whereType<Map>()
        .map((set) => set.cast<String, Object?>())
        .toList();
    final name = exercise['name']?.toString() ?? 'Exercise';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final entry in sets.asMap().entries)
            Text(
              _setLabel(entry.key + 1, entry.value),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}

class _EmptyWorkoutState extends StatelessWidget {
  const _EmptyWorkoutState({required this.selectedDate});

  final DateTime selectedDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        _isSameDay(selectedDate, DateTime.now())
            ? 'When Apple Health or Progressa logs a workout today, it will appear here.'
            : 'No Apple Health or Progressa workout found for ${_dateLabel(selectedDate)}.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

String _dateLabel(DateTime date) {
  final now = DateTime.now();
  if (_isSameDay(date, now)) return 'Today';
  final yesterday = now.subtract(const Duration(days: 1));
  if (_isSameDay(date, yesterday)) return 'Yesterday';
  return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}';
}

String _timeLabel(FitnessEventSummary event) {
  if (event.startTime <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(
    (event.startTime * 1000).round(),
  );
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

List<Map<String, Object?>> _progressaExercises(Map<String, Object?> details) {
  final exercises = details['exercises'];
  if (exercises is! List) return const [];
  return exercises
      .whereType<Map>()
      .map((exercise) => exercise.cast<String, Object?>())
      .toList();
}

String _setLabel(int index, Map<String, Object?> set) {
  final reps = (set['reps'] as num?)?.round();
  final weight = (set['weightKg'] as num?)?.toDouble();
  final rir = (set['rir'] as num?)?.round();
  final side = set['side']?.toString();
  final parts = <String>[
    'Set $index',
    if (reps != null) '$reps reps',
    if (weight != null) '${weight.toStringAsFixed(weight % 1 == 0 ? 0 : 1)} kg',
    if (reps != null && weight != null && reps > 0 && weight > 0)
      '${(reps * weight).round()} kg volume',
    if (rir != null) 'RIR $rir',
    if (side != null && side.isNotEmpty) side,
  ];
  return parts.join(' • ');
}
