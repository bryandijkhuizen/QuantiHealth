import XCTest
@testable import QuantivitaNative

final class ScoringParityTests: XCTestCase {
    func testSleepGoldenMatchesDartWeightsAndDefaults() {
        let result = SleepScorer.calculate(
            duration: 480, efficiency: 0.90, awake: 30, rem: 90, deep: 90
        )
        XCTAssertEqual(result.score, 93)
        XCTAssertEqual(result.contributors["duration"], 100)
        XCTAssertEqual(result.contributors["restfulness"], 76)
        XCTAssertEqual(result.confidence, 0.7)
        XCTAssertTrue(result.penalties.isEmpty)
    }

    func testSleepUnderFiveHoursUsesExactDartCap() {
        let result = SleepScorer.calculate(duration: 299, efficiency: 1, awake: 0, rem: 90, deep: 90)
        XCTAssertEqual(result.score, 45)
        XCTAssertEqual(result.penalties, ["sleep_under_5h_cap"])
    }

    func testBaselineUsesDartSeedSeriesAndCalibrationWindow() {
        let values = BaselineScorer.seed(60, spread: 0.18)
        let baseline = ScoringMath.baseline(values)
        XCTAssertEqual(values.count, 28)
        XCTAssertEqual(baseline.sampleCount, 28)
        XCTAssertEqual(ScoringMath.calibration(baseline.sampleCount), .calibrating)
        XCTAssertEqual(ScoringMath.confidence(.calibrating, available: 5, expected: 5), 0.7)
    }

    func testStrainGoldenMatchesDartNonlinearLoad() {
        let workout = Workout(
            id: "run", title: "Run", startTime: .now, durationMinutes: 45,
            energyKcal: 420, averageHeartRate: 145, typeCode: 1
        )
        let result = StrainScorer.calculate(workouts: [workout], restingHeartRate: 60, userP90Load: 120)
        XCTAssertEqual(result.zones["z2"], 45)
        XCTAssertEqual(result.cardioLoad, 81)
        XCTAssertEqual(result.muscularLoad, 13.1)
        XCTAssertEqual(result.totalLoad, 85.6)
        XCTAssertEqual(result.score, 8.2)
    }

    func testMissingSleepIsExcludedFromRecoveryContributors() {
        var summary = HealthSummary()
        summary.hrvMs = 62
        summary.restingHeartBpm = 59
        let baselines = readyBaselines()
        let result = RecoveryDomainScorer.calculate(summary: summary, sleepScore: 0, strainLoad: 90, stress: 20, baselines: baselines)
        XCTAssertNil(result.contributors["sleep"]!)
        XCTAssertTrue(result.summary.contains("sleep data unavailable"))
        XCTAssertGreaterThanOrEqual(result.score, 65)
    }

    func testSuppressedHRVAndElevatedRHRApplyDartCaps() {
        var summary = HealthSummary()
        summary.sleepMinutes = 449
        summary.hrvMs = 48
        summary.restingHeartBpm = 66
        let result = RecoveryDomainScorer.calculate(summary: summary, sleepScore: 68, strainLoad: 170, stress: 35, baselines: readyBaselines())
        XCTAssertTrue(result.capsApplied.contains("rhr_plus_5_penalty"))
        XCTAssertLessThanOrEqual(result.score, 50)
    }

    func testSleepNeedAndBodyBatteryGoldens() {
        let need = DailyScoringEngine.sleepNeed(actual: 420, strainPercent: 50)
        XCTAssertEqual(need.needMinutes, 532.5, accuracy: 0.001)
        XCTAssertEqual(need.performanceScore, 79)
        XCTAssertEqual(need.strainNeedMinutes, 22.5)
        XCTAssertEqual(need.debtMinutes, 30)

        let battery = DailyScoringEngine.bodyBattery(recovery: 80, sleep: 85, strain: 50, stress: 14, activeEnergy: 360, steps: 6000)
        XCTAssertEqual(battery.score, 41)
        XCTAssertEqual(battery.title, "Low energy reserve")
    }

    private func readyBaselines() -> HealthBaselines {
        HealthBaselines(
            hrvLog: MetricBaseline(median: 4.094, mad: 0.08, sampleCount: 60),
            hrvMs: MetricBaseline(median: 60, mad: 5, sampleCount: 60),
            restingHeartRate: MetricBaseline(median: 60, mad: 2, sampleCount: 60),
            sleepDurationMinutes: MetricBaseline(median: 450, mad: 30, sampleCount: 60),
            sleepEfficiency: nil,
            strainLoad: MetricBaseline(median: 90, mad: 20, sampleCount: 60),
            stress: nil, respiratoryRate: nil, temperatureDeviation: nil
        )
    }
}
