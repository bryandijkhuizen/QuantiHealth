import '../config/health_score_policy.dart';
import '../health/scoring/sleep_scoring_service.dart';
import '../health/scoring/scoring_types.dart';

class SleepSummary {
  const SleepSummary({
    required this.totalMinutes,
    required this.remMinutes,
    required this.coreMinutes,
    required this.deepMinutes,
    required this.awakeMinutes,
    required this.inBedMinutes,
  });

  factory SleepSummary.fromSummary(Map<String, double> summary) {
    final total = summary['sleepMinutes'] ?? 0;
    final rem = summary['sleepRemMinutes'] ?? 0;
    final core = summary['sleepCoreMinutes'] ?? 0;
    final deep = summary['sleepDeepMinutes'] ?? 0;
    final awake = summary['sleepAwakeMinutes'] ?? 0;
    final inBed = summary['sleepInBedMinutes'] ?? total + awake;

    return SleepSummary(
      totalMinutes: total,
      remMinutes: rem,
      coreMinutes: core,
      deepMinutes: deep,
      awakeMinutes: awake,
      inBedMinutes: inBed,
    );
  }

  final double totalMinutes;
  final double remMinutes;
  final double coreMinutes;
  final double deepMinutes;
  final double awakeMinutes;
  final double inBedMinutes;

  int get durationScore => HealthScorePolicy.sleepDurationScore(totalMinutes);

  int get qualityScore {
    return scoreResult.score;
  }

  SleepScoreResult get scoreResult {
    return SleepScoringService.calculate(
      SleepScoreInput(
        durationMinutes: totalMinutes,
        efficiency: efficiency > 0 ? efficiency : null,
        awakeMinutes: awakeMinutes,
        remMinutes: remMinutes,
        deepMinutes: deepMinutes,
      ),
    );
  }

  double get efficiency {
    final denominator = inBedMinutes > 0 ? inBedMinutes : totalMinutes;
    if (denominator <= 0) return 0;
    return (totalMinutes / denominator).clamp(0, 1);
  }

  String get qualityLabel {
    return HealthScorePolicy.bandFor(
      qualityScore,
      HealthScorePolicy.sleepQualityBands,
    ).label;
  }

  List<double> get stageFractions {
    if (totalMinutes <= 0) return const [0.25, 0.45, 0.18, 0.12];
    return [
      (coreMinutes / totalMinutes).clamp(0, 1),
      (remMinutes / totalMinutes).clamp(0, 1),
      (deepMinutes / totalMinutes).clamp(0, 1),
      (awakeMinutes / (totalMinutes + awakeMinutes)).clamp(0, 1),
    ];
  }

  String formatMinutes(double minutes) {
    if (minutes <= 0) return '-';
    final hours = minutes ~/ 60;
    final remaining = minutes.round() % 60;
    if (hours <= 0) return '${remaining}m';
    return '${hours}h ${remaining}m';
  }
}
