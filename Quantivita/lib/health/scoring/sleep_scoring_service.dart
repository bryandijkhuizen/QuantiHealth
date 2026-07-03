import 'scoring_constants.dart';
import 'scoring_types.dart';
import 'scoring_utils.dart';

abstract final class SleepScoringService {
  static SleepScoreResult calculate(SleepScoreInput input) {
    final contributors = <String, double>{
      'duration': durationScore(
        input.durationMinutes,
        baselineMinutes: input.baselineDurationMinutes,
      ),
      'efficiency': efficiencyScore(input.efficiency),
      'restfulness': restfulnessScore(input.awakeMinutes),
      'deep': stageScore(
        minutes: input.deepMinutes,
        totalMinutes: input.durationMinutes,
        minTarget: 60,
        maxTarget: 110,
      ),
      'rem': stageScore(
        minutes: input.remMinutes,
        totalMinutes: input.durationMinutes,
        minTarget: 75,
        maxTarget: 120,
      ),
      'latency': latencyScore(input.latencyMinutes),
      'timing': timingConsistencyScore(input.midpointDiffMinutes),
    };

    var weighted = 0.0;
    for (final entry in ScoringConstants.sleepWeights.entries) {
      weighted += (contributors[entry.key] ?? 0) * entry.value;
    }

    final penalties = <String>[];
    if (input.durationMinutes > 0 && input.durationMinutes < 300) {
      weighted = weighted.clamp(0, 45).toDouble();
      penalties.add('sleep_under_5h_cap');
    } else if (input.durationMinutes > 0 && input.durationMinutes < 360) {
      weighted = weighted.clamp(0, 65).toDouble();
      penalties.add('sleep_under_6h_cap');
    } else if (input.durationMinutes > 600) {
      weighted = weighted.clamp(0, 85).toDouble();
      penalties.add('sleep_over_10h_cap');
    }

    final availableSignals = [
      input.durationMinutes > 0,
      input.efficiency != null && input.efficiency! > 0,
      input.awakeMinutes != null,
      input.remMinutes != null && input.remMinutes! > 0,
      input.deepMinutes != null && input.deepMinutes! > 0,
      input.latencyMinutes != null,
      input.midpointDiffMinutes != null,
    ].where((value) => value).length;

    return SleepScoreResult(
      score: clampScore(weighted),
      contributors: contributors,
      penalties: penalties,
      confidence: roundToOneDecimal(clampDouble(availableSignals / 7, 0.35, 1)),
    );
  }

  static double durationScore(double minutes, {double? baselineMinutes}) {
    if (minutes <= 0) return 0;
    final baselineTarget = baselineMinutes == null || baselineMinutes <= 0
        ? ScoringConstants.adultSleepTargetMinutes
        : baselineMinutes;
    final target = clampDouble(baselineTarget, 420, 540);
    final diff = (minutes - target).abs();
    return clampDouble(100 - diff * 0.35, 0, 100);
  }

  static double efficiencyScore(double? efficiency) {
    if (efficiency == null || efficiency <= 0) return 70;
    if (efficiency >= 0.90) return 100;
    if (efficiency >= 0.85) return 85 + (efficiency - 0.85) * 300;
    if (efficiency >= 0.75) return 50 + (efficiency - 0.75) * 350;
    return clampDouble(efficiency * 65, 0, 50);
  }

  static double restfulnessScore(double? awakeMinutes, {int wakeEvents = 0}) {
    if (awakeMinutes == null) return 75;
    return clampDouble(100 - awakeMinutes * 0.8 - wakeEvents * 3, 0, 100);
  }

  static double stageScore({
    required double? minutes,
    required double totalMinutes,
    required double minTarget,
    required double maxTarget,
  }) {
    if (minutes == null || minutes <= 0 || totalMinutes <= 0) return 70;
    if (minutes >= minTarget && minutes <= maxTarget) return 100;
    final target = minutes < minTarget ? minTarget : maxTarget;
    final diff = (minutes - target).abs();
    return clampDouble(100 - diff * 0.55, 45, 100);
  }

  static double latencyScore(double? latencyMinutes) {
    if (latencyMinutes == null) return 80;
    if (latencyMinutes <= 20) return 100;
    if (latencyMinutes <= 45) {
      return clampDouble(100 - (latencyMinutes - 20) * 1.4, 65, 100);
    }
    return clampDouble(65 - (latencyMinutes - 45) * 1.2, 0, 65);
  }

  static double timingConsistencyScore(double? midpointDiffMinutes) {
    if (midpointDiffMinutes == null) return 80;
    return clampDouble(100 - midpointDiffMinutes.abs() * 0.5, 0, 100);
  }
}
