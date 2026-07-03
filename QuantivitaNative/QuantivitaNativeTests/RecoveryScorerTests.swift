import XCTest
@testable import QuantivitaNative

final class RecoveryScorerTests: XCTestCase {
    func testMissingSleepIsUnknownInsteadOfPoor() {
        var summary = HealthSummary()
        summary.hrvMs = 62
        summary.restingHeartBpm = 59

        let result = RecoveryScorer.calculate(summary: summary, baselineHRV: 60, baselineRHR: 60)

        XCTAssertGreaterThanOrEqual(result.score, 65)
        XCTAssertNil(result.contributors["sleep"]!)
        XCTAssertTrue(result.notes.contains(where: { $0.contains("sleep data unavailable") }))
        XCTAssertLessThan(result.confidence, 1)
    }

    func testActualShortSleepStillCapsRecovery() {
        var summary = HealthSummary()
        summary.sleepMinutes = 240
        summary.hrvMs = 70
        summary.restingHeartBpm = 55

        let result = RecoveryScorer.calculate(summary: summary, baselineHRV: 60, baselineRHR: 60)

        XCTAssertLessThanOrEqual(result.score, 45)
        XCTAssertNotNil(result.contributors["sleep"]!)
    }
}
