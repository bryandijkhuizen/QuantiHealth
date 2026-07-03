import 'body_battery_factor.dart';
import 'metric_model.dart';

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.bodyBatteryScore,
    required this.bodyBatteryTitle,
    required this.bodyBatterySummary,
    required this.bodyBatteryFactors,
    required this.recoveryScore,
    required this.recoveryLabel,
    required this.recoveryTitle,
    required this.recoverySummary,
    required this.recoveryConfidence,
    required this.sleepDuration,
    required this.sleepNeed,
    required this.sleepPerformanceScore,
    required this.sleepNeedSummary,
    required this.hrvDelta,
    required this.restingHeartRate,
    required this.respiratoryRate,
    required this.oxygenSaturation,
    required this.baseTemperature,
    required this.wristTemperature,
    required this.dietaryEnergyKcal,
    required this.dietaryWaterMl,
    required this.waterTargetMl,
    required this.waterBaseTargetMl,
    required this.waterActivityExtraMl,
    required this.waterWorkoutExtraMl,
    required this.activeEnergyKcal,
    required this.basalEnergyKcal,
    required this.totalBurnedEnergyKcal,
    required this.netEnergyKcal,
    required this.dietaryCarbohydratesG,
    required this.dietaryProteinG,
    required this.dietaryFatG,
    required this.metrics,
    required this.baselineTrend,
    required this.weekValues,
    required this.weekInsight,
  });

  final int bodyBatteryScore;
  final String bodyBatteryTitle;
  final String bodyBatterySummary;
  final List<BodyBatteryFactor> bodyBatteryFactors;
  final int recoveryScore;
  final String recoveryLabel;
  final String recoveryTitle;
  final String recoverySummary;
  final double recoveryConfidence;
  final String sleepDuration;
  final String sleepNeed;
  final int sleepPerformanceScore;
  final String sleepNeedSummary;
  final String hrvDelta;
  final String restingHeartRate;
  final String respiratoryRate;
  final String oxygenSaturation;
  final String baseTemperature;
  final String wristTemperature;
  final double dietaryEnergyKcal;
  final double dietaryWaterMl;
  final double waterTargetMl;
  final double waterBaseTargetMl;
  final double waterActivityExtraMl;
  final double waterWorkoutExtraMl;
  final double activeEnergyKcal;
  final double basalEnergyKcal;
  final double totalBurnedEnergyKcal;
  final double netEnergyKcal;
  final double dietaryCarbohydratesG;
  final double dietaryProteinG;
  final double dietaryFatG;
  final List<MetricModel> metrics;
  final String baselineTrend;
  final List<double> weekValues;
  final String weekInsight;
}
