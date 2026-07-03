import 'dart:math' as math;

import 'scoring_types.dart';

double clampDouble(double value, double min, double max) {
  return math.max(min, math.min(max, value));
}

int clampScore(num value) {
  return value.round().clamp(0, 100);
}

double roundToOneDecimal(double value) {
  return (value * 10).round() / 10;
}

double robustZ(double value, MetricBaseline? baseline) {
  final mad = baseline?.mad ?? 0;
  if (mad < 0.0001) return 0;
  return (value - baseline!.median) / (1.4826 * mad);
}

int sigmoidScore(double z) {
  return clampScore(100 / (1 + math.exp(-1.15 * z)));
}

int higherIsBetterScore(double z) {
  return sigmoidScore(z);
}

int lowerIsBetterScore(double z) {
  return sigmoidScore(-z);
}

CalibrationStatus calibrationStatusFor(int sampleCount) {
  if (sampleCount < 14) return CalibrationStatus.insufficientData;
  if (sampleCount < 42) return CalibrationStatus.calibrating;
  return CalibrationStatus.ready;
}

double confidenceFor(
  CalibrationStatus status,
  int availableSignals,
  int expectedSignals,
) {
  final calibrationConfidence = switch (status) {
    CalibrationStatus.insufficientData => 0.35,
    CalibrationStatus.calibrating => 0.65,
    CalibrationStatus.ready => 1.0,
  };
  final signalConfidence = expectedSignals <= 0
      ? 1.0
      : clampDouble(availableSignals / expectedSignals, 0, 1);
  return roundToOneDecimal(calibrationConfidence * signalConfidence);
}

MetricBaseline baselineFromValues(List<double> values) {
  final clean = values.where((value) => value.isFinite && value > 0).toList()
    ..sort();
  if (clean.isEmpty) {
    return const MetricBaseline(median: 0, mad: 0, sampleCount: 0);
  }

  final median = percentile(clean, 0.5);
  final deviations = clean.map((value) => (value - median).abs()).toList()
    ..sort();
  final mean = clean.reduce((a, b) => a + b) / clean.length;
  return MetricBaseline(
    median: median,
    mad: percentile(deviations, 0.5),
    mean: mean,
    p10: percentile(clean, 0.1),
    p90: percentile(clean, 0.9),
    sampleCount: clean.length,
  );
}

double percentile(List<double> sortedValues, double p) {
  if (sortedValues.isEmpty) return 0;
  if (sortedValues.length == 1) return sortedValues.first;
  final index = (sortedValues.length - 1) * p;
  final lower = index.floor();
  final upper = index.ceil();
  if (lower == upper) return sortedValues[lower];
  final weight = index - lower;
  return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight;
}
