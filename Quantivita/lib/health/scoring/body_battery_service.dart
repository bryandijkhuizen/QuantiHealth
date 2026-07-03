import '../../config/health_score_policy.dart';
import '../../models/body_battery_factor.dart';
import 'scoring_utils.dart';

class BodyBatteryResult {
  const BodyBatteryResult({
    required this.score,
    required this.title,
    required this.summary,
    required this.factors,
  });

  final int score;
  final String title;
  final String summary;
  final List<BodyBatteryFactor> factors;
}

abstract final class BodyBatteryService {
  static BodyBatteryResult calculate({
    required int recoveryScore,
    required int sleepScore,
    required double strainPercent,
    required int stressScore,
    required double activeEnergyKcal,
    required double steps,
  }) {
    final morningEnergy = recoveryScore * 0.7 + sleepScore * 0.3;
    final activityDrain = clampDouble(activeEnergyKcal / 18, 0, 28);
    final stepDrain = clampDouble(steps / 12000 * 8, 0, 10);
    final strainDrain = clampDouble(strainPercent * 0.32, 0, 34);
    final stressDrain = clampDouble(stressScore * 0.22, 0, 24);
    final restCharge = stressScore <= 12
        ? 8
        : stressScore <= 20
        ? 3
        : 0;

    final score = clampScore(
      morningEnergy -
          activityDrain -
          stepDrain -
          strainDrain -
          stressDrain +
          restCharge,
    );

    final band = HealthScorePolicy.bandFor(
      score,
      HealthScorePolicy.bodyBatteryBands,
    );

    return BodyBatteryResult(
      score: score,
      title: band.title,
      summary: '$score/100 energy reserve. ${band.summary}',
      factors: [
        BodyBatteryFactor(
          label: 'Recovery charge',
          points: recoveryScore * 0.7,
          detail: '$recoveryScore% recovery × 0.70',
        ),
        BodyBatteryFactor(
          label: 'Sleep charge',
          points: sleepScore * 0.3,
          detail: '$sleepScore sleep score × 0.30',
        ),
        BodyBatteryFactor(
          label: 'Active burn drain',
          points: -activityDrain,
          detail: '${activeEnergyKcal.round()} active kcal',
        ),
        BodyBatteryFactor(
          label: 'Movement drain',
          points: -stepDrain,
          detail: '${steps.round()} steps today',
        ),
        BodyBatteryFactor(
          label: 'Strain drain',
          points: -strainDrain,
          detail: '${strainPercent.round()}% daily strain',
        ),
        BodyBatteryFactor(
          label: 'Stress drain',
          points: -stressDrain,
          detail: '$stressScore stress score',
        ),
        if (restCharge > 0)
          BodyBatteryFactor(
            label: 'Low-stress recharge',
            points: restCharge.toDouble(),
            detail: 'Quiet periods add reserve back',
          ),
      ],
    );
  }
}
