import 'scoring_utils.dart';

class SleepNeedResult {
  const SleepNeedResult({
    required this.needMinutes,
    required this.performanceScore,
    required this.strainNeedMinutes,
    required this.debtMinutes,
    required this.summary,
  });

  final double needMinutes;
  final int performanceScore;
  final double strainNeedMinutes;
  final double debtMinutes;
  final String summary;
}

abstract final class SleepNeedService {
  static SleepNeedResult calculate({
    required double actualSleepMinutes,
    required double strainPercent,
    double baselineNeedMinutes = 480,
  }) {
    final strainRatio = clampDouble(strainPercent / 100, 0, 1);
    final strainNeedMinutes = 90 * strainRatio * strainRatio;
    final previousShortfall = baselineNeedMinutes - actualSleepMinutes;
    final debtMinutes = previousShortfall > 0
        ? clampDouble(previousShortfall * 0.50, 0, 120)
        : 0.0;
    final needMinutes = clampDouble(
      baselineNeedMinutes + strainNeedMinutes + debtMinutes,
      390,
      660,
    );
    final performanceScore = needMinutes <= 0
        ? 0
        : clampScore(actualSleepMinutes / needMinutes * 100);

    return SleepNeedResult(
      needMinutes: needMinutes,
      performanceScore: performanceScore,
      strainNeedMinutes: strainNeedMinutes,
      debtMinutes: debtMinutes,
      summary: _summary(performanceScore, strainNeedMinutes, debtMinutes),
    );
  }

  static String _summary(
    int performanceScore,
    double strainNeedMinutes,
    double debtMinutes,
  ) {
    final parts = <String>[];
    if (strainNeedMinutes >= 10) {
      parts.add('${strainNeedMinutes.round()}m extra from strain');
    }
    if (debtMinutes >= 10) {
      parts.add('${debtMinutes.round()}m sleep debt carried into target');
    }
    if (parts.isEmpty) {
      parts.add('baseline sleep need only');
    }
    return '$performanceScore% sleep performance: ${parts.join(' • ')}.';
  }
}
