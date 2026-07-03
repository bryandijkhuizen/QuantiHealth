class FitnessEventSummary {
  const FitnessEventSummary({
    required this.id,
    required this.sourceUuid,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.startTime,
    required this.durationMinutes,
    required this.energyKcal,
    required this.totalEnergyKcal,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.averageHeartRate,
    required this.maxHeartRate,
    required this.temperatureC,
    required this.humidityPercent,
    required this.weatherCondition,
    required this.airQualityIndex,
    required this.typeCode,
    required this.hasRoute,
    this.source = 'healthkit',
    this.externalWorkoutId = '',
    this.progressaDetails = const {},
  });

  final String id;
  final String sourceUuid;
  final String title;
  final String subtitle;
  final String value;
  final double startTime;
  final double durationMinutes;
  final double energyKcal;
  final double totalEnergyKcal;
  final double distanceMeters;
  final double elevationGainMeters;
  final double averageHeartRate;
  final double maxHeartRate;
  final double temperatureC;
  final double humidityPercent;
  final String weatherCondition;
  final double airQualityIndex;
  final int typeCode;
  final bool hasRoute;
  final String source;
  final String externalWorkoutId;
  final Map<String, Object?> progressaDetails;

  double get endTime => startTime + durationMinutes * 60;
  bool get isProgressa => source == 'progressa';
  int get progressaSetCount =>
      (progressaDetails['totalSets'] as num?)?.round() ?? 0;
  int get progressaExerciseCount =>
      (progressaDetails['exerciseCount'] as num?)?.round() ?? 0;
  double get progressaVolumeKg =>
      (progressaDetails['totalVolumeKg'] as num?)?.toDouble() ?? 0;
  bool get hasProgressaVolumeData {
    if (progressaDetails['hasVolumeData'] == true) return true;
    final exercises = progressaDetails['exercises'];
    if (exercises is! List) return false;
    for (final exercise in exercises.whereType<Map>()) {
      final sets = exercise['sets'];
      if (sets is! List) continue;
      for (final set in sets.whereType<Map>()) {
        final weight = (set['weightKg'] as num?)?.toDouble();
        final reps = (set['reps'] as num?)?.toDouble();
        if (weight != null && weight > 0 && reps != null && reps > 0) {
          return true;
        }
      }
    }
    return false;
  }

  String get progressaVolumeLabel => hasProgressaVolumeData
      ? '${progressaVolumeKg.round()} kg'
      : 'Volume unknown';

  String get displayTitle {
    if (!isProgressa) return title;
    final trimmed = title.trim();
    if (trimmed.isNotEmpty &&
        !RegExp(
          r'^(workout|progressa workout|strength)$',
          caseSensitive: false,
        ).hasMatch(trimmed)) {
      return trimmed;
    }

    final exercises = progressaDetails['exercises'];
    if (exercises is List) {
      final names = exercises
          .whereType<Map>()
          .map((exercise) => exercise['name']?.toString().trim() ?? '')
          .where(
            (name) =>
                name.isNotEmpty &&
                !RegExp(r'^exercise$', caseSensitive: false).hasMatch(name),
          )
          .toList();
      if (names.isNotEmpty) {
        final suffix = names.length > 1
            ? ' + ${names.length - 1} exercises'
            : '';
        return '${names.first}$suffix';
      }
    }

    if (startTime > 0) {
      final date = DateTime.fromMillisecondsSinceEpoch(
        (startTime * 1000).round(),
      );
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return 'Strength workout at $hour:$minute';
    }
    return 'Strength workout';
  }

  double get effectiveDurationMinutes {
    if (!isProgressa || durationMinutes > 0) return durationMinutes;
    final estimated = progressaSetCount * 2.5 + progressaExerciseCount * 4;
    return estimated.clamp(0, 180).toDouble();
  }

  double get effectiveEnergyKcal {
    if (!isProgressa || energyKcal > 0) return energyKcal;
    final durationEnergy = effectiveDurationMinutes * 4.5;
    final volumeEnergy = progressaVolumeKg / 120;
    return (durationEnergy + volumeEnergy).clamp(0, 900).toDouble();
  }
}

class FitnessSummary {
  const FitnessSummary({
    required this.strain,
    required this.cardioLoad,
    required this.cardioFocus,
    required this.hrr,
    required this.events,
    required this.loadSamples,
    required this.focusSamples,
  });

  final double strain;
  final int cardioLoad;
  final String cardioFocus;
  final String hrr;
  final List<FitnessEventSummary> events;
  final List<double> loadSamples;
  final List<double> focusSamples;

  List<FitnessEventSummary> get todayEvents {
    return eventsForDate(DateTime.now());
  }

  List<FitnessEventSummary> eventsForDate(DateTime targetDate) {
    return events.where((event) {
      if (event.startTime <= 0) return false;
      final date = DateTime.fromMillisecondsSinceEpoch(
        (event.startTime * 1000).round(),
      );
      return date.year == targetDate.year &&
          date.month == targetDate.month &&
          date.day == targetDate.day;
    }).toList();
  }

  double get todayEnergyKcal {
    return todayEvents.fold<double>(
      0,
      (total, event) => total + event.effectiveEnergyKcal,
    );
  }

  double get todayDistanceMeters {
    return todayEvents.fold<double>(
      0,
      (total, event) => total + event.distanceMeters,
    );
  }
}

class MergedWorkoutPreview {
  const MergedWorkoutPreview({required this.events});

  final List<FitnessEventSummary> events;

  bool get canMerge => events.length >= 2;

  double get startTime => events.isEmpty
      ? 0
      : events.map((event) => event.startTime).reduce((a, b) => a < b ? a : b);

  double get endTime => events.isEmpty
      ? 0
      : events.map((event) => event.endTime).reduce((a, b) => a > b ? a : b);

  double get movingMinutes {
    return events.fold<double>(
      0,
      (total, event) => total + event.durationMinutes,
    );
  }

  double get elapsedMinutes => events.isEmpty ? 0 : (endTime - startTime) / 60;

  double get transitionMinutes =>
      (elapsedMinutes - movingMinutes).clamp(0, double.infinity);

  double get energyKcal {
    return events.fold<double>(0, (total, event) => total + event.energyKcal);
  }

  double get totalEnergyKcal {
    return events.fold<double>(
      0,
      (total, event) => total + event.totalEnergyKcal,
    );
  }

  double get distanceMeters {
    return events.fold<double>(
      0,
      (total, event) => total + event.distanceMeters,
    );
  }

  double get elevationGainMeters {
    return events.fold<double>(
      0,
      (total, event) => total + event.elevationGainMeters,
    );
  }

  double get averageSpeedKmh {
    if (movingMinutes <= 0 || distanceMeters <= 0) return 0;
    return distanceMeters / 1000 / (movingMinutes / 60);
  }

  double get averageHeartRate {
    final heartEvents = events.where((event) => event.averageHeartRate > 0);
    if (heartEvents.isEmpty) return 0;

    final weightedHeartRate = heartEvents.fold<double>(
      0,
      (total, event) => total + event.averageHeartRate * event.durationMinutes,
    );
    final totalMinutes = heartEvents.fold<double>(
      0,
      (total, event) => total + event.durationMinutes,
    );
    return totalMinutes > 0 ? weightedHeartRate / totalMinutes : 0;
  }

  double get maxHeartRate {
    final maxValues = events.map((event) => event.maxHeartRate);
    return maxValues.isEmpty ? 0 : maxValues.reduce((a, b) => a > b ? a : b);
  }

  double get averageTemperatureC {
    final values = events.where((event) => event.temperatureC > 0);
    if (values.isEmpty) return 0;
    return values.fold<double>(
          0,
          (total, event) => total + event.temperatureC,
        ) /
        values.length;
  }

  double get averageHumidityPercent {
    final values = events.where((event) => event.humidityPercent > 0);
    if (values.isEmpty) return 0;
    return values.fold<double>(
          0,
          (total, event) => total + event.humidityPercent,
        ) /
        values.length;
  }

  String get weatherConditions {
    final conditions = events
        .map((event) => event.weatherCondition)
        .where((condition) => condition.isNotEmpty && condition != 'Unknown')
        .toSet()
        .toList();
    if (conditions.isEmpty) return '';
    return conditions.join(' + ');
  }

  double get averageAirQualityIndex {
    final values = events.where((event) => event.airQualityIndex > 0);
    if (values.isEmpty) return 0;
    return values.fold<double>(
          0,
          (total, event) => total + event.airQualityIndex,
        ) /
        values.length;
  }

  int get routeSegments => events.where((event) => event.hasRoute).length;
  int get progressaSetCount {
    return events.fold<int>(
      0,
      (total, event) => total + event.progressaSetCount,
    );
  }

  int get progressaExerciseCount {
    return events.fold<int>(
      0,
      (total, event) => total + event.progressaExerciseCount,
    );
  }

  double get progressaVolumeKg {
    return events.fold<double>(
      0,
      (total, event) => total + event.progressaVolumeKg,
    );
  }

  String get title {
    if (events.isEmpty) return 'No merge selected';

    final ordered = [...events]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final names = ordered.map((event) => event.title).toList();
    final compact = <String>[];
    for (final name in names) {
      if (compact.isEmpty || compact.last != name) {
        compact.add(name);
      }
    }
    return compact.join(' + ');
  }

  String get exportTypeLabel {
    final types = events.map((event) => event.typeCode).toSet();
    if (types.length == 1) {
      return events.first.title;
    }
    if (types.contains(3) && types.contains(4)) {
      return 'swimBikeRun';
    }
    return 'mixedCardio';
  }
}
