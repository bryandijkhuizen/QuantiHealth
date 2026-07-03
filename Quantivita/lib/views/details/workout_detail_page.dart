import 'package:flutter/material.dart';

import '../../models/fitness_summary.dart';
import '../../theme/quantivita_colors.dart';
import '../../widgets/panel.dart';

class WorkoutDetailPage extends StatelessWidget {
  const WorkoutDetailPage({required this.event, super.key});

  final FitnessEventSummary event;

  @override
  Widget build(BuildContext context) {
    final color = event.isProgressa
        ? QuantivitaColors.strain
        : QuantivitaColors.sleep;

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
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 110),
              sliver: SliverList.list(
                children: [
                  _WorkoutHero(event: event, color: color),
                  const SizedBox(height: 14),
                  _MetricGrid(event: event, color: color),
                  if (event.isProgressa) ...[
                    const SizedBox(height: 14),
                    _ProgressaExercisesPanel(event: event),
                  ] else ...[
                    const SizedBox(height: 14),
                    _HealthDetailsPanel(event: event),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutHero extends StatelessWidget {
  const _WorkoutHero({required this.event, required this.color});

  final FitnessEventSummary event;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            event.isProgressa
                ? Icons.fitness_center_rounded
                : Icons.directions_run_rounded,
            color: color,
            size: 34,
          ),
          const SizedBox(height: 12),
          Text(
            event.displayTitle,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            event.isProgressa ? 'Progressa workout' : 'Apple Health workout',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          Text(
            _dateTimeLabel(event),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(event.subtitle, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.event, required this.color});

  final FitnessEventSummary event;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            label: 'Duration',
            value: '${event.effectiveDurationMinutes.round()} min',
            color: color,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricTile(
            label: 'Energy',
            value: '${event.effectiveEnergyKcal.round()} kcal',
            color: QuantivitaColors.strain,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricTile(
            label: event.isProgressa ? 'Volume' : 'Distance',
            value: event.isProgressa
                ? event.progressaVolumeLabel
                : _distanceLabel(event.distanceMeters),
            color: QuantivitaColors.activity,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(14),
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

class _ProgressaExercisesPanel extends StatelessWidget {
  const _ProgressaExercisesPanel({required this.event});

  final FitnessEventSummary event;

  @override
  Widget build(BuildContext context) {
    final exercises = _progressaExercises(event.progressaDetails);

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
                  'Exercises',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${event.progressaExerciseCount}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (exercises.isEmpty)
            Text(
              'This cached Progressa workout has no per-exercise rows yet. Sync Progressa again when the server includes set details.',
              style: Theme.of(context).textTheme.bodyMedium,
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
    final sets = (exercise['sets'] as List? ?? const [])
        .whereType<Map>()
        .map((set) => set.cast<String, Object?>())
        .toList();
    final name = exercise['name']?.toString() ?? 'Exercise';
    final muscleGroup = exercise['muscleGroup']?.toString() ?? '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(16),
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
          if (sets.isEmpty)
            Text(
              'No sets recorded.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
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

class _HealthDetailsPanel extends StatelessWidget {
  const _HealthDetailsPanel({required this.event});

  final FitnessEventSummary event;

  @override
  Widget build(BuildContext context) {
    final rows = [
      if (event.averageHeartRate > 0)
        ('Average heart rate', '${event.averageHeartRate.round()} bpm'),
      if (event.maxHeartRate > 0)
        ('Max heart rate', '${event.maxHeartRate.round()} bpm'),
      if (event.elevationGainMeters > 0)
        ('Elevation gain', '${event.elevationGainMeters.round()} m'),
      if (event.hasRoute) ('Route', 'GPS route available'),
      if (event.weatherCondition.isNotEmpty)
        ('Weather', event.weatherCondition),
      if (event.temperatureC > 0)
        ('Temperature', '${event.temperatureC.toStringAsFixed(1)} °C'),
      if (event.humidityPercent > 0)
        ('Humidity', '${event.humidityPercent.round()}%'),
      if (event.airQualityIndex > 0)
        ('Air quality', '${event.airQualityIndex.round()} AQI'),
    ];

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text(
              'No extra Apple Health details were available for this workout.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.$1,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      row.$2,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

String _dateTimeLabel(FitnessEventSummary event) {
  if (event.startTime <= 0) return 'No timestamp';
  final date = DateTime.fromMillisecondsSinceEpoch(
    (event.startTime * 1000).round(),
  );
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day-$month-${date.year} at $hour:$minute';
}

String _distanceLabel(double meters) {
  if (meters <= 0) return '-';
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
  return '${meters.round()} m';
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
  final isWarmup = set['isWarmup'] == true;
  final parts = <String>[
    isWarmup ? 'Warmup $index' : 'Set $index',
    if (reps != null) '$reps reps',
    if (weight != null) '${weight.toStringAsFixed(weight % 1 == 0 ? 0 : 1)} kg',
    if (reps != null && weight != null && reps > 0 && weight > 0)
      '${(reps * weight).round()} kg volume',
    if (rir != null) 'RIR $rir',
    if (side != null && side.isNotEmpty) side,
  ];
  return parts.join(' • ');
}
