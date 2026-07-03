import 'package:flutter/material.dart';

import '../../../models/fitness_summary.dart';
import '../../../services/strava_service.dart';
import '../../../services/workout_export_service.dart';
import '../../../theme/quantivita_colors.dart';
import '../../../widgets/panel.dart';
import '../../../widgets/sparkline.dart';

class FitnessTab extends StatefulWidget {
  const FitnessTab({
    required this.summary,
    required this.selectedDate,
    required this.lookbackDays,
    required this.isLoadingHistory,
    required this.isSyncingProgressaWorkouts,
    required this.onLookbackChanged,
    required this.onSyncProgressaWorkouts,
    super.key,
  });

  final FitnessSummary summary;
  final DateTime selectedDate;
  final int lookbackDays;
  final bool isLoadingHistory;
  final bool isSyncingProgressaWorkouts;
  final ValueChanged<int> onLookbackChanged;
  final VoidCallback onSyncProgressaWorkouts;

  @override
  State<FitnessTab> createState() => _FitnessTabState();
}

class _FitnessTabState extends State<FitnessTab> {
  FitnessSummary get summary => widget.summary;
  bool _didAutoSyncProgressa = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didAutoSyncProgressa) return;
      if (widget.isSyncingProgressaWorkouts) return;
      if (summary.events.any((event) => event.isProgressa)) return;
      _didAutoSyncProgressa = true;
      widget.onSyncProgressaWorkouts();
    });
  }

  @override
  void didUpdateWidget(covariant FitnessTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (summary.events.any((event) => event.isProgressa)) {
      _didAutoSyncProgressa = true;
    }
  }

  void _openMergePreview() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MergeWorkoutIntroPage(allEvents: summary.events),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedProgressaStrength = summary
        .eventsForDate(widget.selectedDate)
        .where((event) => event.isProgressa && event.progressaSetCount > 0)
        .toList();
    final latestProgressaStrength =
        summary.events
            .where((event) => event.isProgressa && event.progressaSetCount > 0)
            .toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final visibleProgressaStrength = selectedProgressaStrength.isNotEmpty
        ? selectedProgressaStrength
        : latestProgressaStrength.take(8).toList();

    return Column(
      children: [
        _FitnessScorePanel(summary: summary),
        const SizedBox(height: 14),
        _WorkoutHistoryPanel(
          lookbackDays: widget.lookbackDays,
          workoutCount: summary.events
              .where((event) => event.startTime > 0)
              .length,
          progressaWorkoutCount: summary.events
              .where((event) => event.isProgressa)
              .length,
          isLoading: widget.isLoadingHistory,
          isSyncingProgressa: widget.isSyncingProgressaWorkouts,
          onChanged: widget.onLookbackChanged,
          onSyncProgressa: widget.onSyncProgressaWorkouts,
        ),
        const SizedBox(height: 14),
        _ProgressaDetailsPanel(
          workouts: visibleProgressaStrength,
          selectedDate: widget.selectedDate,
          isShowingLatest:
              selectedProgressaStrength.isEmpty &&
              latestProgressaStrength.isNotEmpty,
        ),
        const SizedBox(height: 14),
        _MergeLabPanel(
          availableWorkoutCount: summary.events
              .where((event) => event.startTime > 0)
              .length,
          onOpenPreview: summary.events.length >= 2 ? _openMergePreview : null,
        ),
        const SizedBox(height: 14),
        _CardioLoadPanel(summary: summary),
      ],
    );
  }
}

class _WorkoutHistoryPanel extends StatelessWidget {
  const _WorkoutHistoryPanel({
    required this.lookbackDays,
    required this.workoutCount,
    required this.progressaWorkoutCount,
    required this.isLoading,
    required this.isSyncingProgressa,
    required this.onChanged,
    required this.onSyncProgressa,
  });

  final int lookbackDays;
  final int workoutCount;
  final int progressaWorkoutCount;
  final bool isLoading;
  final bool isSyncingProgressa;
  final ValueChanged<int> onChanged;
  final VoidCallback onSyncProgressa;

  @override
  Widget build(BuildContext context) {
    final options = [7, 30, 90, 365];

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                color: QuantivitaColors.recovery,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Workout history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$workoutCount workouts loaded for merging. $progressaWorkoutCount from Progressa.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isSyncingProgressa ? null : onSyncProgressa,
              icon: isSyncingProgressa
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(
                isSyncingProgressa
                    ? 'Syncing Progressa...'
                    : 'Sync Progressa workouts',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final days in options)
                ChoiceChip(
                  label: Text(days == 365 ? '1 year' : '$days days'),
                  selected: lookbackDays == days,
                  onSelected: isLoading ? null : (_) => onChanged(days),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressaDetailsPanel extends StatelessWidget {
  const _ProgressaDetailsPanel({
    required this.workouts,
    required this.selectedDate,
    required this.isShowingLatest,
  });

  final List<FitnessEventSummary> workouts;
  final DateTime selectedDate;
  final bool isShowingLatest;

  @override
  Widget build(BuildContext context) {
    final totalSets = workouts.fold<int>(
      0,
      (sum, workout) => sum + workout.progressaSetCount,
    );
    final totalExercises = workouts.fold<int>(
      0,
      (sum, workout) => sum + workout.progressaExerciseCount,
    );
    final volumeWorkouts = workouts.where(
      (workout) => workout.hasProgressaVolumeData,
    );
    final totalVolume = volumeWorkouts.fold<double>(
      0,
      (sum, workout) => sum + workout.progressaVolumeKg,
    );

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fitness_center_rounded,
                color: QuantivitaColors.strain,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Progressa strength details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${workouts.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            workouts.isEmpty
                ? 'No Progressa strength workouts for ${_fitnessDateLabel(selectedDate)}.'
                : isShowingLatest
                ? [
                    '$totalSets sets',
                    '$totalExercises exercises',
                    if (volumeWorkouts.isNotEmpty)
                      '${totalVolume.round()} kg total volume',
                    'from your latest Progressa strength workouts.',
                  ].join(', ')
                : [
                    '$totalSets sets',
                    '$totalExercises exercises',
                    if (volumeWorkouts.isNotEmpty)
                      '${totalVolume.round()} kg total volume',
                    'for ${_fitnessDateLabel(selectedDate)} are included in strain and training load.',
                  ].join(', '),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (workouts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MergeStat(label: 'Sets', value: '$totalSets'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MergeStat(
                    label: 'Exercises',
                    value: '$totalExercises',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MergeStat(
                    label: 'Volume',
                    value: volumeWorkouts.isNotEmpty
                        ? '${totalVolume.round()} kg'
                        : 'Unknown',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final workout in workouts.take(8))
              _ProgressaWorkoutTile(workout: workout),
          ],
        ],
      ),
    );
  }
}

class _ProgressaWorkoutTile extends StatelessWidget {
  const _ProgressaWorkoutTile({required this.workout});

  final FitnessEventSummary workout;

  @override
  Widget build(BuildContext context) {
    final exercises = _progressaExercises(workout.progressaDetails);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 10),
        leading: const Icon(
          Icons.expand_circle_down_rounded,
          color: QuantivitaColors.strain,
        ),
        title: Text(
          workout.displayTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          [
            '${workout.progressaSetCount} sets',
            '${workout.progressaExerciseCount} exercises',
            workout.hasProgressaVolumeData
                ? workout.progressaVolumeLabel
                : 'Volume unknown',
          ].join(' • '),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        children: [
          if (exercises.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Progressa returned this workout without per-exercise set rows.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            for (final exercise in exercises)
              _ProgressaExerciseBlock(exercise: exercise),
        ],
      ),
    );
  }
}

class _ProgressaExerciseBlock extends StatelessWidget {
  const _ProgressaExerciseBlock({required this.exercise});

  final Map<String, Object?> exercise;

  @override
  Widget build(BuildContext context) {
    final sets = (exercise['sets'] as List? ?? const []).whereType<Map>();
    final name = exercise['name']?.toString() ?? 'Exercise';
    final muscleGroup = exercise['muscleGroup']?.toString() ?? '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          if (muscleGroup.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(muscleGroup, style: Theme.of(context).textTheme.labelMedium),
          ],
          const SizedBox(height: 8),
          for (final entry in sets.toList().asMap().entries)
            Text(
              _setLabel(entry.key + 1, entry.value.cast<String, Object?>()),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}

class _MergeLabPanel extends StatelessWidget {
  const _MergeLabPanel({
    required this.availableWorkoutCount,
    required this.onOpenPreview,
  });

  final int availableWorkoutCount;
  final VoidCallback? onOpenPreview;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.merge_rounded, color: QuantivitaColors.recovery),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Workout Merge Lab',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: onOpenPreview,
                icon: const Icon(Icons.merge_rounded, size: 18),
                label: const Text('Open Lab'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Want to merge several workouts into one? Start here, then select matching workouts with search, type filters, and expanded history.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MergeStat(
                  label: 'Loaded',
                  value: '$availableWorkoutCount',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MergeStat(label: 'Find', value: 'Search'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MergeStat(label: 'Narrow', value: 'Filter'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'The fitness page stays clean; workout selection now happens inside the merge flow.',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
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

String _fitnessDateLabel(DateTime date) {
  final now = DateTime.now();
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return 'today';
  }
  return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}';
}

class _FitnessScorePanel extends StatelessWidget {
  const _FitnessScorePanel({required this.summary});

  final FitnessSummary summary;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: _FitnessMetric(
              icon: Icons.bolt_rounded,
              label: 'Strain',
              value: '${summary.strain.round()}%',
              color: QuantivitaColors.strain,
            ),
          ),
          Expanded(
            child: _FitnessMetric(
              icon: Icons.monitor_heart_rounded,
              label: 'HR reserve',
              value: summary.hrr,
              color: QuantivitaColors.sleep,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardioLoadPanel extends StatelessWidget {
  const _CardioLoadPanel({required this.summary});

  final FitnessSummary summary;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.directions_run_rounded,
                color: QuantivitaColors.activity,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Training load',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${summary.cardioLoad}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 96,
            child: Sparkline(
              values: summary.loadSamples,
              color: QuantivitaColors.activity,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Current focus: ${summary.cardioFocus}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({
    required this.event,
    required this.isSelected,
    required this.onTap,
  });

  final FitnessEventSummary event;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: event.startTime > 0 ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isSelected
                  ? QuantivitaColors.recovery
                  : QuantivitaColors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          event.displayTitle,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (event.hasRoute) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.route_rounded,
                          color: QuantivitaColors.sleep,
                          size: 17,
                        ),
                      ],
                      if (event.isProgressa) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.fitness_center_rounded,
                          color: QuantivitaColors.strain,
                          size: 17,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.isProgressa
                        ? '${event.subtitle} • ${event.progressaSetCount} sets • ${event.progressaExerciseCount} exercises'
                        : event.subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (event.isProgressa && event.hasProgressaVolumeData) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${event.progressaVolumeLabel} total volume from Progressa',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ],
              ),
            ),
            Text(event.value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _FitnessMetric extends StatelessWidget {
  const _FitnessMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 10),
        Text(value, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _MergeStat extends StatelessWidget {
  const _MergeStat({required this.label, required this.value});

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
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _WizardStepPill extends StatelessWidget {
  const _WizardStepPill({required this.label, required this.isActive});

  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isActive
            ? QuantivitaColors.recovery
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: isActive ? QuantivitaColors.onAccent : QuantivitaColors.muted,
        ),
      ),
    );
  }
}

class _WizardSelectStep extends StatelessWidget {
  const _WizardSelectStep({
    required this.events,
    required this.totalMatches,
    required this.visibleLimit,
    required this.selectedIds,
    required this.searchQuery,
    required this.typeFilter,
    required this.typeOptions,
    required this.onSearchChanged,
    required this.onTypeChanged,
    required this.onMore,
    required this.onToggle,
  });

  final List<FitnessEventSummary> events;
  final int totalMatches;
  final int visibleLimit;
  final Set<String> selectedIds;
  final String searchQuery;
  final String typeFilter;
  final List<String> typeOptions;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback? onMore;
  final ValueChanged<FitnessEventSummary> onToggle;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select workouts',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Search, filter, then pick the segments that belong together. For bike + swim + bike, select all three in chronological order.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search workouts, dates, energy, GPS...',
              helperText: searchQuery.isEmpty
                  ? null
                  : 'Filtering: $searchQuery',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in typeOptions)
                ChoiceChip(
                  label: Text(type),
                  selected: typeFilter == type,
                  onSelected: (_) => onTypeChanged(type),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${selectedIds.length} selected • showing ${events.length} of $totalMatches',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 12),
          for (final event in events) ...[
            _WorkoutRow(
              event: event,
              isSelected: selectedIds.contains(event.id),
              onTap: () => onToggle(event),
            ),
            if (event != events.last) const Divider(height: 22),
          ],
          if (events.isEmpty)
            Text(
              'No workouts match this filter.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (onMore != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onMore,
                icon: const Icon(Icons.expand_more_rounded),
                label: const Text('More'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExportPreparation extends StatelessWidget {
  const _ExportPreparation({
    required this.preview,
    required this.isExporting,
    required this.message,
  });

  final MergedWorkoutPreview preview;
  final bool isExporting;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_upload_rounded,
                color: QuantivitaColors.sleep,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Apple Health export',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Ready to export as a new HealthKit workout. Original workouts stay untouched. Proposed type: ${preview.exportTypeLabel}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          _MergeStat(
            label: 'Export payload',
            value:
                '${preview.events.length} segments • ${preview.routeSegments} routes',
          ),
          if (isExporting || message != null) ...[
            const SizedBox(height: 12),
            Text(
              isExporting
                  ? 'Writing merged workout to Apple Health...'
                  : message!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _MergedWorkoutReview extends StatelessWidget {
  const _MergedWorkoutReview({required this.preview});

  final MergedWorkoutPreview preview;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RouteMapPlaceholder(preview: preview),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Workout data',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _DataChip(
                    label: 'Active',
                    value: '${preview.energyKcal.round()} kcal',
                  ),
                  _DataChip(
                    label: 'Total',
                    value: '${preview.totalEnergyKcal.round()} kcal',
                  ),
                  _DataChip(
                    label: 'Distance',
                    value: _formatDistance(preview.distanceMeters),
                  ),
                  _DataChip(
                    label: 'Avg speed',
                    value: preview.averageSpeedKmh > 0
                        ? '${preview.averageSpeedKmh.toStringAsFixed(1)} km/h'
                        : '-',
                  ),
                  _DataChip(
                    label: 'Elevation',
                    value: preview.elevationGainMeters > 0
                        ? '${preview.elevationGainMeters.round()} m'
                        : '-',
                  ),
                  _DataChip(
                    label: 'Avg HR',
                    value: preview.averageHeartRate > 0
                        ? '${preview.averageHeartRate.round()} bpm'
                        : '-',
                  ),
                  _DataChip(
                    label: 'Max HR',
                    value: preview.maxHeartRate > 0
                        ? '${preview.maxHeartRate.round()} bpm'
                        : '-',
                  ),
                  _DataChip(
                    label: 'Temp',
                    value: preview.averageTemperatureC > 0
                        ? '${preview.averageTemperatureC.toStringAsFixed(1)} °C'
                        : '-',
                  ),
                  _DataChip(
                    label: 'Humidity',
                    value: preview.averageHumidityPercent > 0
                        ? '${preview.averageHumidityPercent.round()}%'
                        : '-',
                  ),
                  _DataChip(
                    label: 'Weather',
                    value: preview.weatherConditions.isNotEmpty
                        ? preview.weatherConditions
                        : '-',
                  ),
                  _DataChip(
                    label: 'Air quality',
                    value: preview.averageAirQualityIndex > 0
                        ? '${preview.averageAirQualityIndex.round()} AQI'
                        : '-',
                  ),
                  if (preview.progressaSetCount > 0)
                    _DataChip(
                      label: 'Progressa sets',
                      value: '${preview.progressaSetCount}',
                    ),
                  if (preview.progressaExerciseCount > 0)
                    _DataChip(
                      label: 'Progressa exercises',
                      value: '${preview.progressaExerciseCount}',
                    ),
                  if (preview.progressaVolumeKg > 0)
                    _DataChip(
                      label: 'Progressa volume',
                      value: '${preview.progressaVolumeKg.round()} kg',
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Row(
            children: [
              Expanded(
                child: _MergeStat(
                  label: 'Moving',
                  value: _formatMinutes(preview.movingMinutes),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MergeStat(
                  label: 'Transition',
                  value: _formatMinutes(preview.transitionMinutes),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MergeStat(
                  label: 'Routes',
                  value: '${preview.routeSegments}',
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
                'Heart rate verloop',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 120,
                child: Sparkline(
                  values: preview.events.isEmpty
                      ? const [0.2, 0.24, 0.22]
                      : preview.events
                            .map(
                              (event) => event.averageHeartRate > 0
                                  ? (event.averageHeartRate / 190)
                                        .clamp(0.2, 1.0)
                                        .toDouble()
                                  : (event.durationMinutes / 90)
                                        .clamp(0.2, 1.0)
                                        .toDouble(),
                            )
                            .toList(),
                  color: QuantivitaColors.activity,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteMapPlaceholder extends StatelessWidget {
  const _RouteMapPlaceholder({required this.preview});

  final MergedWorkoutPreview preview;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: EdgeInsets.zero,
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF172B2D), Color(0xFF10151A), Color(0xFF241E2A)],
          ),
        ),
        child: Stack(
          children: [
            CustomPaint(
              size: Size.infinite,
              painter: _RoutePreviewPainter(
                color: preview.routeSegments > 0
                    ? QuantivitaColors.recovery
                    : QuantivitaColors.muted,
              ),
            ),
            Positioned(
              left: 16,
              top: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Route map',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview.routeSegments > 0
                        ? '${preview.routeSegments} route segments available'
                        : 'No GPS route found yet',
                    style: Theme.of(context).textTheme.bodyMedium,
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

class _RoutePreviewPainter extends CustomPainter {
  const _RoutePreviewPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.68)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.28,
        size.width * 0.42,
        size.height * 0.78,
        size.width * 0.58,
        size.height * 0.42,
      )
      ..cubicTo(
        size.width * 0.7,
        size.height * 0.16,
        size.width * 0.82,
        size.height * 0.58,
        size.width * 0.9,
        size.height * 0.3,
      );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _DataChip extends StatelessWidget {
  const _DataChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class MergeWorkoutWizardPage extends StatefulWidget {
  const MergeWorkoutWizardPage({
    required this.allEvents,
    required this.initialSelectedIds,
    required this.onSelectionChanged,
    super.key,
  });

  final List<FitnessEventSummary> allEvents;
  final Set<String> initialSelectedIds;
  final ValueChanged<Set<String>> onSelectionChanged;

  @override
  State<MergeWorkoutWizardPage> createState() => _MergeWorkoutWizardPageState();
}

class MergeWorkoutIntroPage extends StatelessWidget {
  const MergeWorkoutIntroPage({required this.allEvents, super.key});

  final List<FitnessEventSummary> allEvents;

  @override
  Widget build(BuildContext context) {
    final available = allEvents.where((event) => event.startTime > 0).length;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const Spacer(),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: QuantivitaColors.recovery.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.merge_rounded,
                  color: QuantivitaColors.recovery,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Want to merge several workouts into one?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                'Use this when Apple Health or Strava split one real session into multiple chunks. Quantivita keeps the originals untouched and builds one reviewable merged workout.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MergeStat(label: 'Available', value: '$available'),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: _MergeStat(label: 'Tools', value: 'Search'),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: _MergeStat(label: 'Export', value: 'Strava'),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: available >= 2
                      ? () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => MergeWorkoutWizardPage(
                                allEvents: allEvents,
                                initialSelectedIds: const {},
                                onSelectionChanged: (_) {},
                              ),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Choose workouts'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MergeWorkoutWizardPageState extends State<MergeWorkoutWizardPage> {
  late Set<String> selectedIds;
  final WorkoutExportService exportService = WorkoutExportService();
  late final StravaService stravaService = StravaService(
    exportService: exportService,
  );
  int step = 0;
  String searchQuery = '';
  String typeFilter = 'All';
  int visibleLimit = 12;
  bool isExporting = false;
  bool isSharingStrava = false;
  bool isUploadingStrava = false;
  bool isSharingCsv = false;
  String? exportMessage;

  @override
  void initState() {
    super.initState();
    selectedIds = Set<String>.from(widget.initialSelectedIds);
  }

  List<FitnessEventSummary> get selectedEvents {
    final events = widget.allEvents
        .where((event) => selectedIds.contains(event.id) && event.startTime > 0)
        .toList();
    events.sort((a, b) => a.startTime.compareTo(b.startTime));
    return events;
  }

  List<FitnessEventSummary> get filteredEvents {
    final query = searchQuery.trim().toLowerCase();
    final events = widget.allEvents.where((event) {
      if (event.startTime <= 0) return false;
      final matchesType = typeFilter == 'All' || event.title == typeFilter;
      final matchesQuery =
          query.isEmpty ||
          event.title.toLowerCase().contains(query) ||
          event.subtitle.toLowerCase().contains(query);
      return matchesType && matchesQuery;
    }).toList();
    events.sort((a, b) => b.startTime.compareTo(a.startTime));
    return events;
  }

  List<String> get typeOptions {
    final values =
        widget.allEvents
            .where((event) => event.startTime > 0)
            .map((event) => event.title)
            .toSet()
            .toList()
          ..sort();
    return ['All', ...values];
  }

  void _toggle(FitnessEventSummary event) {
    if (event.startTime <= 0) return;
    setState(() {
      if (!selectedIds.add(event.id)) {
        selectedIds.remove(event.id);
      }
    });
    widget.onSelectionChanged(selectedIds);
  }

  Future<void> _export(MergedWorkoutPreview preview) async {
    if (isExporting || !preview.canMerge) return;

    setState(() {
      isExporting = true;
      exportMessage = null;
    });

    final result = await exportService.exportMergedWorkout(preview);
    if (!mounted) return;

    setState(() {
      isExporting = false;
      exportMessage = result.message;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _shareStrava(MergedWorkoutPreview preview) async {
    if (isSharingStrava || !preview.canMerge) return;

    setState(() {
      isSharingStrava = true;
      exportMessage = null;
    });

    final result = await exportService.shareStravaTcx(preview);
    if (!mounted) return;

    setState(() {
      isSharingStrava = false;
      exportMessage = result.message;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _uploadStrava(MergedWorkoutPreview preview) async {
    if (isUploadingStrava || !preview.canMerge) return;

    setState(() {
      isUploadingStrava = true;
      exportMessage = null;
    });

    final result = await stravaService.uploadMergedWorkout(preview);
    if (!mounted) return;

    setState(() {
      isUploadingStrava = false;
      exportMessage = result.message;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _shareCsv(MergedWorkoutPreview preview) async {
    if (isSharingCsv || !preview.canMerge) return;

    setState(() {
      isSharingCsv = true;
      exportMessage = null;
    });

    final result = await stravaService.shareCsv(preview);
    if (!mounted) return;

    setState(() {
      isSharingCsv = false;
      exportMessage = result.message;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final preview = MergedWorkoutPreview(events: selectedEvents);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Merge Workouts',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _WizardStepPill(
                      label: 'Select',
                      isActive: step == 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _WizardStepPill(
                      label: 'Review',
                      isActive: step == 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _WizardStepPill(
                      label: 'Export',
                      isActive: step == 2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                children: [
                  if (step == 0)
                    _WizardSelectStep(
                      events: filteredEvents.take(visibleLimit).toList(),
                      totalMatches: filteredEvents.length,
                      visibleLimit: visibleLimit,
                      selectedIds: selectedIds,
                      searchQuery: searchQuery,
                      typeFilter: typeFilter,
                      typeOptions: typeOptions,
                      onSearchChanged: (value) => setState(() {
                        searchQuery = value;
                        visibleLimit = 12;
                      }),
                      onTypeChanged: (value) => setState(() {
                        typeFilter = value;
                        visibleLimit = 12;
                      }),
                      onMore: filteredEvents.length > visibleLimit
                          ? () => setState(() => visibleLimit += 12)
                          : null,
                      onToggle: _toggle,
                    )
                  else if (step == 1)
                    _MergedWorkoutReview(preview: preview)
                  else
                    _ExportPreparation(
                      preview: preview,
                      isExporting: isExporting,
                      message: exportMessage,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (step == 2) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: preview.canMerge
                            ? () => _uploadStrava(preview)
                            : null,
                        icon: const Icon(Icons.directions_run_rounded),
                        label: Text(
                          isUploadingStrava
                              ? 'Uploading to Strava...'
                              : 'Upload directly to Strava',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: preview.canMerge
                                ? () => _shareCsv(preview)
                                : null,
                            icon: const Icon(Icons.table_chart_rounded),
                            label: Text(
                              isSharingCsv ? 'Preparing CSV...' : 'Export CSV',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: preview.canMerge
                            ? () => _shareStrava(preview)
                            : null,
                        icon: const Icon(Icons.ios_share_rounded),
                        label: Text(
                          isSharingStrava
                              ? 'Preparing Strava TCX...'
                              : 'Share TCX for Strava',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: step == 0
                              ? null
                              : () => setState(() => step -= 1),
                          child: const Text('Back'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: preview.canMerge
                              ? () {
                                  if (step < 2) {
                                    setState(() => step += 1);
                                  } else {
                                    _export(preview);
                                  }
                                }
                              : null,
                          child: Text(
                            step < 2
                                ? 'Continue'
                                : isExporting
                                ? 'Exporting...'
                                : 'Export to Apple Health',
                          ),
                        ),
                      ),
                    ],
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

class MergedWorkoutPreviewPage extends StatefulWidget {
  const MergedWorkoutPreviewPage({required this.preview, super.key});

  final MergedWorkoutPreview preview;

  @override
  State<MergedWorkoutPreviewPage> createState() =>
      _MergedWorkoutPreviewPageState();
}

class _MergedWorkoutPreviewPageState extends State<MergedWorkoutPreviewPage> {
  final WorkoutExportService exportService = WorkoutExportService();
  late final StravaService stravaService = StravaService(
    exportService: exportService,
  );
  bool isExporting = false;
  bool isSharingStrava = false;
  bool isUploadingStrava = false;
  bool isSharingCsv = false;

  Future<void> _export() async {
    if (isExporting || !widget.preview.canMerge) return;

    setState(() => isExporting = true);
    final result = await exportService.exportMergedWorkout(widget.preview);
    if (!mounted) return;

    setState(() => isExporting = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _shareStrava() async {
    if (isSharingStrava || !widget.preview.canMerge) return;

    setState(() => isSharingStrava = true);
    final result = await exportService.shareStravaTcx(widget.preview);
    if (!mounted) return;

    setState(() => isSharingStrava = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _uploadStrava() async {
    if (isUploadingStrava || !widget.preview.canMerge) return;

    setState(() => isUploadingStrava = true);
    final result = await stravaService.uploadMergedWorkout(widget.preview);
    if (!mounted) return;

    setState(() => isUploadingStrava = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _shareCsv() async {
    if (isSharingCsv || !widget.preview.canMerge) return;

    setState(() => isSharingCsv = true);
    final result = await stravaService.shareCsv(widget.preview);
    if (!mounted) return;

    setState(() => isSharingCsv = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final samples = preview.events.isEmpty
        ? const [0.2, 0.22, 0.2, 0.24]
        : preview.events
              .map((event) => (event.durationMinutes / 90).clamp(0.12, 1.0))
              .toList();

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
                      onPressed: preview.canMerge ? _shareStrava : null,
                      icon: const Icon(Icons.ios_share_rounded),
                      tooltip: 'Share TCX for Strava',
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: preview.canMerge ? _shareCsv : null,
                      icon: const Icon(Icons.table_chart_rounded),
                      tooltip: 'Export CSV',
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: preview.canMerge ? _uploadStrava : null,
                      icon: const Icon(Icons.directions_run_rounded),
                      tooltip: 'Upload directly to Strava',
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: preview.canMerge ? _export : null,
                      icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                      label: Text(isExporting ? 'Exporting...' : 'Export'),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preview.title,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Local merged session • proposed HealthKit type ${preview.exportTypeLabel}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 190,
                          child: Sparkline(
                            values: samples,
                            color: QuantivitaColors.recovery,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _MergedWorkoutReview(preview: preview),
                  const SizedBox(height: 14),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Segments',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        for (var i = 0; i < preview.events.length; i++) ...[
                          _SegmentRow(
                            index: i + 1,
                            event: preview.events[i],
                            nextEvent: i + 1 < preview.events.length
                                ? preview.events[i + 1]
                                : null,
                          ),
                          if (i != preview.events.length - 1)
                            const Divider(height: 24),
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
                          'What happens here',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Quantivita keeps the original Apple workouts untouched and builds a local session from their timestamps, energy, duration, type, and route availability. The next step can read route coordinates and write a new HealthKit workout only when you explicitly export.',
                          style: Theme.of(context).textTheme.bodyMedium,
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

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.index,
    required this.event,
    required this.nextEvent,
  });

  final int index;
  final FitnessEventSummary event;
  final FitnessEventSummary? nextEvent;

  @override
  Widget build(BuildContext context) {
    final gapMinutes = nextEvent == null
        ? 0.0
        : ((nextEvent!.startTime - event.endTime) / 60)
              .clamp(0, double.infinity)
              .toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: QuantivitaColors.recovery,
              foregroundColor: QuantivitaColors.onAccent,
              child: Text('$index'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                event.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(event.value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${event.subtitle}${event.hasRoute ? ' • route ready' : ' • no route found'}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (gapMinutes > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Transition gap ${_formatMinutes(gapMinutes)}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ],
    );
  }
}

String _formatMinutes(double minutes) {
  if (minutes <= 0) return '-';
  final hours = minutes ~/ 60;
  final remaining = minutes.round() % 60;
  if (hours <= 0) return '${remaining}m';
  return '${hours}h ${remaining}m';
}

String _formatDistance(double meters) {
  if (meters <= 0) return '-';
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(2)} km';
  return '${meters.round()} m';
}
