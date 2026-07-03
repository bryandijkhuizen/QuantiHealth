import 'dart:math' as math;

import 'scoring_constants.dart';
import 'scoring_types.dart';
import 'scoring_utils.dart';

abstract final class StrainScoringService {
  static StrainScoreResult calculate(StrainScoreInput input) {
    final zones = <String, double>{'z1': 0, 'z2': 0, 'z3': 0, 'z4': 0, 'z5': 0};
    var cardioLoad = 0.0;
    var muscularLoad = 0.0;

    for (final workout in input.workouts) {
      final duration = workout.durationMinutes.clamp(0, 600).toDouble();
      final resting =
          workout.restingHeartRate ?? ScoringConstants.fallbackRestingHeartRate;
      final maxHr =
          workout.maxHeartRate ?? ScoringConstants.fallbackMaxHeartRate;
      final reserve = math.max(maxHr - resting, 1);
      final hrReservePercent = workout.averageHeartRate > 0
          ? (workout.averageHeartRate - resting) / reserve
          : estimatedReserveFromEnergy(workout.activeEnergyKcal, duration);

      final zone = zoneFor(hrReservePercent);
      zones[zone.name] = (zones[zone.name] ?? 0) + duration;
      cardioLoad += duration * zone.weight;
      muscularLoad += muscularLoadFor(workout);
    }

    final totalLoad = cardioLoad + muscularLoad * 0.35;
    final k = math.max(
      (input.userP90DailyLoad ?? ScoringConstants.fallbackP90DailyLoad) * 1.45,
      110,
    );
    final raw = 21 * (1 - math.exp(-totalLoad / k));
    final score = roundToOneDecimal(clampDouble(raw, 0, 21));

    return StrainScoreResult(
      score: score,
      cardioLoad: roundToOneDecimal(cardioLoad),
      muscularLoad: roundToOneDecimal(muscularLoad),
      totalLoad: roundToOneDecimal(totalLoad),
      zones: zones.map((key, value) => MapEntry(key, roundToOneDecimal(value))),
      label: strainLabel(score),
    );
  }

  static ({String name, double weight}) zoneFor(double reservePercent) {
    if (reservePercent >= 0.90) return (name: 'z5', weight: 9.5);
    if (reservePercent >= 0.80) return (name: 'z4', weight: 6.5);
    if (reservePercent >= 0.70) return (name: 'z3', weight: 3.4);
    if (reservePercent >= 0.60) return (name: 'z2', weight: 1.8);
    if (reservePercent >= 0.50) return (name: 'z1', weight: 0.9);
    return (name: 'z1', weight: 0);
  }

  static double estimatedReserveFromEnergy(
    double activeEnergyKcal,
    double durationMinutes,
  ) {
    if (durationMinutes <= 0 || activeEnergyKcal <= 0) return 0.45;
    final kcalPerMinute = activeEnergyKcal / durationMinutes;
    return clampDouble(0.45 + kcalPerMinute / 32, 0.45, 0.88);
  }

  static double muscularLoadFor(StrainWorkoutInput workout) {
    final duration = workout.durationMinutes.clamp(0, 600).toDouble();
    final typeMultiplier = switch (workout.typeCode) {
      5 => 1.25,
      6 => 1.15,
      7 => 0.45,
      _ => 0.25,
    };
    final kcalMultiplier = workout.activeEnergyKcal <= 0
        ? 1.0
        : clampDouble(
            workout.activeEnergyKcal / math.max(duration * 8, 1),
            0.65,
            1.45,
          );
    return duration * typeMultiplier * kcalMultiplier;
  }

  static String strainLabel(double score) {
    if (score >= 20) return 'Very high';
    if (score >= 17) return 'High';
    if (score >= 11) return 'Moderate';
    if (score >= 5) return 'Light';
    return 'Restorative';
  }
}
