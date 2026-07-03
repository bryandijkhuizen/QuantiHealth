enum CalibrationStatus { insufficientData, calibrating, ready }

extension CalibrationStatusWire on CalibrationStatus {
  String get wireName {
    return switch (this) {
      CalibrationStatus.insufficientData => 'INSUFFICIENT_DATA',
      CalibrationStatus.calibrating => 'CALIBRATING',
      CalibrationStatus.ready => 'READY',
    };
  }
}

class MetricBaseline {
  const MetricBaseline({
    required this.median,
    required this.mad,
    required this.sampleCount,
    this.mean,
    this.p10,
    this.p90,
  });

  final double median;
  final double mad;
  final int sampleCount;
  final double? mean;
  final double? p10;
  final double? p90;
}

class HealthBaselines {
  const HealthBaselines({
    this.hrvLog,
    this.hrvMs,
    this.restingHeartRate,
    this.sleepDurationMinutes,
    this.sleepEfficiency,
    this.strainLoad,
    this.stress,
    this.respiratoryRate,
    this.temperatureDeviation,
  });

  final MetricBaseline? hrvLog;
  final MetricBaseline? hrvMs;
  final MetricBaseline? restingHeartRate;
  final MetricBaseline? sleepDurationMinutes;
  final MetricBaseline? sleepEfficiency;
  final MetricBaseline? strainLoad;
  final MetricBaseline? stress;
  final MetricBaseline? respiratoryRate;
  final MetricBaseline? temperatureDeviation;

  int get primarySampleCount {
    return [
      hrvLog?.sampleCount ?? 0,
      restingHeartRate?.sampleCount ?? 0,
      sleepDurationMinutes?.sampleCount ?? 0,
    ].fold<int>(0, (best, value) => value > best ? value : best);
  }
}

class SleepScoreInput {
  const SleepScoreInput({
    required this.durationMinutes,
    this.efficiency,
    this.awakeMinutes,
    this.remMinutes,
    this.deepMinutes,
    this.latencyMinutes,
    this.midpointDiffMinutes,
    this.baselineDurationMinutes,
  });

  final double durationMinutes;
  final double? efficiency;
  final double? awakeMinutes;
  final double? remMinutes;
  final double? deepMinutes;
  final double? latencyMinutes;
  final double? midpointDiffMinutes;
  final double? baselineDurationMinutes;
}

class SleepScoreResult {
  const SleepScoreResult({
    required this.score,
    required this.contributors,
    required this.penalties,
    required this.confidence,
  });

  final int score;
  final Map<String, double> contributors;
  final List<String> penalties;
  final double confidence;
}

class RecoveryScoreInput {
  const RecoveryScoreInput({
    required this.sleepDurationMinutes,
    required this.sleepScore,
    required this.hrvRmssd,
    required this.restingHeartRate,
    required this.strainLoadToday,
    required this.stressScore,
    this.sleepAvailable = true,
    this.respiratoryRate,
    this.temperatureDeviation,
  });

  final double sleepDurationMinutes;
  final int sleepScore;
  final double hrvRmssd;
  final double restingHeartRate;
  final double strainLoadToday;
  final double stressScore;
  final bool sleepAvailable;
  final double? respiratoryRate;
  final double? temperatureDeviation;
}

class RecoveryScoreResult {
  const RecoveryScoreResult({
    required this.score,
    required this.label,
    required this.summary,
    required this.contributors,
    required this.capsApplied,
    required this.confidence,
    required this.calibrationStatus,
  });

  final int score;
  final String label;
  final String summary;
  final Map<String, double?> contributors;
  final List<String> capsApplied;
  final double confidence;
  final CalibrationStatus calibrationStatus;
}

class StrainScoreInput {
  const StrainScoreInput({required this.workouts, this.userP90DailyLoad});

  final List<StrainWorkoutInput> workouts;
  final double? userP90DailyLoad;
}

class StrainWorkoutInput {
  const StrainWorkoutInput({
    required this.durationMinutes,
    required this.activeEnergyKcal,
    required this.averageHeartRate,
    required this.typeCode,
    this.restingHeartRate,
    this.maxHeartRate,
  });

  final double durationMinutes;
  final double activeEnergyKcal;
  final double averageHeartRate;
  final int typeCode;
  final double? restingHeartRate;
  final double? maxHeartRate;
}

class StrainScoreResult {
  const StrainScoreResult({
    required this.score,
    required this.cardioLoad,
    required this.muscularLoad,
    required this.totalLoad,
    required this.zones,
    required this.label,
  });

  final double score;
  final double cardioLoad;
  final double muscularLoad;
  final double totalLoad;
  final Map<String, double> zones;
  final String label;
}
