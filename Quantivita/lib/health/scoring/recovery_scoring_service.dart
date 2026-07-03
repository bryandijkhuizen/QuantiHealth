import 'dart:math' as math;

import 'scoring_constants.dart';
import 'scoring_types.dart';
import 'scoring_utils.dart';

abstract final class RecoveryScoringService {
  static RecoveryScoreResult calculate({
    required RecoveryScoreInput input,
    required HealthBaselines baselines,
  }) {
    final calibrationStatus = calibrationStatusFor(
      baselines.primarySampleCount,
    );
    final hrvAvailable = input.hrvRmssd > 0;
    final rhrAvailable = input.restingHeartRate > 0;

    final hrvScore = hrvAvailable
        ? higherIsBetterScore(
            robustZ(
              math.log(input.hrvRmssd),
              baselines.hrvLog ??
                  (baselines.hrvMs == null
                      ? null
                      : MetricBaseline(
                          median: math.log(baselines.hrvMs!.median),
                          mad: baselines.hrvMs!.mad / baselines.hrvMs!.median,
                          sampleCount: baselines.hrvMs!.sampleCount,
                        )),
            ),
          )
        : null;
    final rhrScore = rhrAvailable
        ? lowerIsBetterScore(
            robustZ(input.restingHeartRate, baselines.restingHeartRate),
          )
        : null;
    final sleepScore = input.sleepScore;
    final strainBalance = strainBalanceScore(
      baselines.strainLoad == null || baselines.strainLoad!.median <= 0
          ? 1
          : input.strainLoadToday / baselines.strainLoad!.median,
    );
    final respiratory = respiratoryScore(input.respiratoryRate, baselines);
    final temperature = temperatureScore(input.temperatureDeviation);

    final contributors = <String, double?>{
      'hrv': hrvScore?.toDouble(),
      'rhr': rhrScore?.toDouble(),
      'sleep': input.sleepAvailable ? sleepScore.toDouble() : null,
      'strainBalance': strainBalance,
      'respiratory': respiratory,
      'temperature': temperature,
    };

    final fallbackPhysiologyScore =
        ((input.sleepAvailable ? sleepScore : 70) * 0.35 +
                strainBalance * 0.20 +
                45)
            .clamp(0, 70);
    var weighted = 0.0;
    var totalWeight = 0.0;
    for (final entry in ScoringConstants.recoveryWeights.entries) {
      final value = contributors[entry.key];
      if (value == null) continue;
      weighted += value * entry.value;
      totalWeight += entry.value;
    }
    var recovery = totalWeight <= 0
        ? fallbackPhysiologyScore.toDouble()
        : weighted / totalWeight;

    if (!hrvAvailable || !rhrAvailable) {
      recovery = math.min(recovery, 58);
    }

    final caps = <String>[];
    if (input.sleepDurationMinutes > 0 && input.sleepDurationMinutes < 300) {
      recovery = math.min(recovery, 45);
      caps.add('sleep_under_5h');
    }
    if (input.sleepDurationMinutes > 0 && input.sleepDurationMinutes < 360) {
      recovery = math.min(recovery, 65);
      caps.add('sleep_under_6h');
    }

    final baselineRhr = baselines.restingHeartRate?.median ?? 0;
    final baselineHrv = baselines.hrvMs?.median ?? 0;
    if (baselineRhr > 0 && input.restingHeartRate > baselineRhr + 3) {
      recovery -= 5;
      caps.add('rhr_plus_3_penalty');
    }
    if (baselineRhr > 0 && input.restingHeartRate > baselineRhr + 5) {
      recovery -= 10;
      caps.add('rhr_plus_5_penalty');
    }
    if (baselineRhr > 0 && input.restingHeartRate > baselineRhr + 8) {
      recovery = math.min(recovery, 55);
      caps.add('rhr_plus_8_cap');
    }
    if (baselineHrv > 0 &&
        baselineRhr > 0 &&
        input.hrvRmssd < baselineHrv * 0.80 &&
        input.restingHeartRate > baselineRhr + 5) {
      recovery = math.min(recovery, 50);
      caps.add('low_hrv_high_rhr_cap');
    }
    if ((input.temperatureDeviation ?? 0) > 0.5) {
      recovery = math.min(recovery, 50);
      caps.add('temperature_deviation_cap');
    }

    if (hrvAvailable &&
        rhrAvailable &&
        input.sleepDurationMinutes >= 360 &&
        input.sleepScore >= 60) {
      recovery = math.max(recovery, 35);
    }

    if (calibrationStatus != CalibrationStatus.ready) {
      recovery = recovery.clamp(20, 82).toDouble();
    }

    final score = clampScore(recovery);
    final label = recoveryLabel(score);
    final availableSignals = [
      hrvAvailable,
      rhrAvailable,
      input.sleepAvailable,
      respiratory != null,
      temperature != null,
    ].where((value) => value).length;

    return RecoveryScoreResult(
      score: score,
      label: label,
      summary: recoverySummary(score, input, baselines, calibrationStatus),
      contributors: contributors,
      capsApplied: caps,
      confidence: confidenceFor(calibrationStatus, availableSignals, 5),
      calibrationStatus: calibrationStatus,
    );
  }

  static double strainBalanceScore(double ratio) {
    if (ratio >= 0.8 && ratio <= 1.2) return 100;
    if (ratio > 1.2 && ratio <= 1.5) return 80 - (ratio - 1.2) * 100;
    if (ratio > 1.5) return clampDouble(50 - (ratio - 1.5) * 80, 0, 50);
    if (ratio < 0.5) return 75;
    return 85;
  }

  static double? respiratoryScore(double? value, HealthBaselines baselines) {
    if (value == null || value <= 0) return null;
    final baseline = baselines.respiratoryRate;
    if (baseline == null || baseline.median <= 0) return 85;
    final z = robustZ(value, baseline);
    return lowerIsBetterScore(z).toDouble();
  }

  static double? temperatureScore(double? deviation) {
    if (deviation == null) return null;
    if (deviation.abs() <= 0.2) return 95;
    if (deviation > 0.5) return 30;
    return clampDouble(90 - deviation.abs() * 90, 25, 95);
  }

  static String recoveryLabel(int score) {
    if (score >= 90) return 'Peak recovery';
    if (score >= 75) return 'Good recovery';
    if (score >= 50) return 'Moderate recovery';
    if (score >= 25) return 'Low recovery';
    return 'Poor recovery';
  }

  static String recoverySummary(
    int score,
    RecoveryScoreInput input,
    HealthBaselines baselines,
    CalibrationStatus calibrationStatus,
  ) {
    final notes = <String>[];
    final baselineHrv = baselines.hrvMs?.median ?? 0;
    final baselineRhr = baselines.restingHeartRate?.median ?? 0;
    if (baselineHrv > 0 && input.hrvRmssd > 0) {
      final change = ((input.hrvRmssd / baselineHrv - 1) * 100).round();
      notes.add('HRV ${change >= 0 ? '+' : ''}$change% vs baseline');
    }
    if (baselineRhr > 0 && input.restingHeartRate > 0) {
      final change = (input.restingHeartRate - baselineRhr).round();
      notes.add('RHR ${change >= 0 ? '+' : ''}$change bpm');
    }
    notes.add(
      input.sleepAvailable
          ? 'sleep score ${input.sleepScore}'
          : 'sleep data unavailable',
    );
    if (calibrationStatus != CalibrationStatus.ready) {
      notes.add('Quantivita is still learning your baseline');
    }
    return '$score% recovery. ${notes.join(' • ')}.';
  }
}
