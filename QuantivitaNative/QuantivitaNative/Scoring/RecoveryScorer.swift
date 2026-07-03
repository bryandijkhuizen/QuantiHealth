import Foundation

enum RecoveryScorer {
    static func calculate(
        summary: HealthSummary, workouts: [Workout] = [],
        strainBalance: Double = 85, baselineHRV: Double? = nil, baselineRHR: Double? = nil
    ) -> RecoveryResult {
        if let baselineHRV, let baselineRHR {
            let sleep = SleepScorer.calculate(duration: summary.sleepMinutes, efficiency: nil, awake: summary.sleepAwakeMinutes, rem: summary.sleepREMMinutes, deep: summary.sleepDeepMinutes)
            let baselines = HealthBaselines(
                hrvLog: MetricBaseline(median: log(baselineHRV), mad: 0.08, sampleCount: 60),
                hrvMs: MetricBaseline(median: baselineHRV, mad: 5, sampleCount: 60),
                restingHeartRate: MetricBaseline(median: baselineRHR, mad: 2, sampleCount: 60),
                sleepDurationMinutes: nil, sleepEfficiency: nil,
                strainLoad: MetricBaseline(median: strainBalance, mad: 20, sampleCount: 60),
                stress: nil, respiratoryRate: nil, temperatureDeviation: nil
            )
            return RecoveryDomainScorer.calculate(summary: summary, sleepScore: sleep.score, strainLoad: strainBalance, stress: 14, baselines: baselines)
        }
        return DailyScoringEngine.calculate(summary: summary, workouts: workouts).recovery
    }
}
