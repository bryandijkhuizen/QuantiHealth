import 'dart:math' as math;

import '../../models/fitness_summary.dart';
import 'scoring_types.dart';
import 'scoring_utils.dart';

abstract final class BaselineService {
  static HealthBaselines fromToday({
    required double hrvMs,
    required double restingHeartRate,
    required double sleepMinutes,
    required double sleepEfficiency,
    required double strainLoad,
    required double stressScore,
    required double respiratoryRate,
    required double temperatureDeviation,
    List<FitnessEventSummary> workouts = const [],
  }) {
    return HealthBaselines(
      hrvMs: baselineFromValues(
        seedSeries(hrvMs, spread: 0.18, sampleCount: 28),
      ),
      hrvLog: baselineFromValues(
        seedSeries(
          hrvMs,
          spread: 0.18,
          sampleCount: 28,
        ).where((value) => value > 0).map(math.log).toList(),
      ),
      restingHeartRate: baselineFromValues(
        seedSeries(restingHeartRate, spread: 0.08, sampleCount: 28),
      ),
      sleepDurationMinutes: baselineFromValues(
        seedSeries(sleepMinutes, spread: 0.10, sampleCount: 28),
      ),
      sleepEfficiency: baselineFromValues(
        seedSeries(sleepEfficiency, spread: 0.04, sampleCount: 28),
      ),
      strainLoad: baselineFromValues(
        seedSeries(strainLoad, spread: 0.22, sampleCount: 28),
      ),
      stress: baselineFromValues(
        seedSeries(stressScore, spread: 0.20, sampleCount: 28),
      ),
      respiratoryRate: baselineFromValues(
        seedSeries(respiratoryRate, spread: 0.04, sampleCount: 28),
      ),
      temperatureDeviation: baselineFromValues(
        seedSeries(
          temperatureDeviation.abs() + 0.05,
          spread: 0.20,
          sampleCount: 28,
        ),
      ),
    );
  }

  static List<double> seedSeries(
    double value, {
    required double spread,
    required int sampleCount,
  }) {
    if (value <= 0) return const [];
    return List<double>.generate(sampleCount, (index) {
      final phase = math.sin(index * 1.7) * spread;
      return math.max(value * (1 + phase), 0.0001);
    });
  }
}
