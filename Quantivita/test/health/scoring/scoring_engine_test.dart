import 'package:flutter_test/flutter_test.dart';
import 'package:quantivita/health/scoring/recovery_scoring_service.dart';
import 'package:quantivita/health/scoring/scoring_types.dart';
import 'package:quantivita/health/scoring/strain_scoring_service.dart';

void main() {
  group('RecoveryScoringService', () {
    test('caps recovery when HRV is suppressed and RHR is elevated', () {
      final result = RecoveryScoringService.calculate(
        input: const RecoveryScoreInput(
          sleepDurationMinutes: 449,
          sleepScore: 68,
          hrvRmssd: 48,
          restingHeartRate: 66,
          strainLoadToday: 170,
          stressScore: 35,
        ),
        baselines: const HealthBaselines(
          hrvMs: MetricBaseline(median: 60, mad: 5, sampleCount: 60),
          hrvLog: MetricBaseline(median: 4.094, mad: 0.08, sampleCount: 60),
          restingHeartRate: MetricBaseline(median: 60, mad: 2, sampleCount: 60),
          sleepDurationMinutes: MetricBaseline(
            median: 450,
            mad: 30,
            sampleCount: 60,
          ),
          strainLoad: MetricBaseline(median: 90, mad: 20, sampleCount: 60),
        ),
      );

      expect(result.score, inInclusiveRange(35, 55));
      expect(result.score, lessThanOrEqualTo(60));
      expect(result.capsApplied, contains('rhr_plus_5_penalty'));
    });

    test('allows high recovery when physiology aligns', () {
      final result = RecoveryScoringService.calculate(
        input: const RecoveryScoreInput(
          sleepDurationMinutes: 480,
          sleepScore: 85,
          hrvRmssd: 66,
          restingHeartRate: 58,
          strainLoadToday: 95,
          stressScore: 12,
        ),
        baselines: const HealthBaselines(
          hrvMs: MetricBaseline(median: 60, mad: 5, sampleCount: 60),
          hrvLog: MetricBaseline(median: 4.094, mad: 0.08, sampleCount: 60),
          restingHeartRate: MetricBaseline(median: 60, mad: 2, sampleCount: 60),
          sleepDurationMinutes: MetricBaseline(
            median: 465,
            mad: 25,
            sampleCount: 60,
          ),
          strainLoad: MetricBaseline(median: 90, mad: 20, sampleCount: 60),
        ),
      );

      expect(result.score, inInclusiveRange(75, 90));
    });

    test('sleep score alone cannot create high recovery', () {
      final result = RecoveryScoringService.calculate(
        input: const RecoveryScoreInput(
          sleepDurationMinutes: 500,
          sleepScore: 82,
          hrvRmssd: 45,
          restingHeartRate: 68,
          strainLoadToday: 90,
          stressScore: 20,
        ),
        baselines: const HealthBaselines(
          hrvMs: MetricBaseline(median: 60, mad: 5, sampleCount: 60),
          hrvLog: MetricBaseline(median: 4.094, mad: 0.08, sampleCount: 60),
          restingHeartRate: MetricBaseline(median: 60, mad: 2, sampleCount: 60),
          sleepDurationMinutes: MetricBaseline(
            median: 465,
            mad: 25,
            sampleCount: 60,
          ),
          strainLoad: MetricBaseline(median: 90, mad: 20, sampleCount: 60),
        ),
      );

      expect(result.score, lessThan(55));
    });

    test('missing sleep is unknown and does not tank recovery', () {
      final result = RecoveryScoringService.calculate(
        input: const RecoveryScoreInput(
          sleepDurationMinutes: 0,
          sleepScore: 0,
          sleepAvailable: false,
          hrvRmssd: 62,
          restingHeartRate: 59,
          strainLoadToday: 90,
          stressScore: 20,
        ),
        baselines: const HealthBaselines(
          hrvMs: MetricBaseline(median: 60, mad: 5, sampleCount: 60),
          hrvLog: MetricBaseline(median: 4.094, mad: 0.08, sampleCount: 60),
          restingHeartRate: MetricBaseline(median: 60, mad: 2, sampleCount: 60),
          sleepDurationMinutes: MetricBaseline(
            median: 465,
            mad: 25,
            sampleCount: 60,
          ),
          strainLoad: MetricBaseline(median: 90, mad: 20, sampleCount: 60),
        ),
      );

      expect(result.score, greaterThanOrEqualTo(65));
      expect(result.contributors['sleep'], isNull);
      expect(result.summary, contains('sleep data unavailable'));
    });
  });

  group('StrainScoringService', () {
    test('maps load nonlinearly to 0-21', () {
      final low = StrainScoringService.calculate(
        const StrainScoreInput(
          userP90DailyLoad: 120,
          workouts: [
            StrainWorkoutInput(
              durationMinutes: 20,
              activeEnergyKcal: 80,
              averageHeartRate: 105,
              typeCode: 2,
            ),
          ],
        ),
      );
      final moderate = StrainScoringService.calculate(
        const StrainScoreInput(
          userP90DailyLoad: 120,
          workouts: [
            StrainWorkoutInput(
              durationMinutes: 45,
              activeEnergyKcal: 420,
              averageHeartRate: 145,
              typeCode: 1,
            ),
          ],
        ),
      );
      final high = StrainScoringService.calculate(
        const StrainScoreInput(
          userP90DailyLoad: 120,
          workouts: [
            StrainWorkoutInput(
              durationMinutes: 90,
              activeEnergyKcal: 1100,
              averageHeartRate: 168,
              typeCode: 1,
            ),
          ],
        ),
      );

      expect(low.score, lessThan(moderate.score));
      expect(moderate.score, lessThan(high.score));
      expect(high.score, lessThanOrEqualTo(21));
    });
  });
}
