import XCTest
import HealthKit
@testable import QuantivitaNative

final class SleepSummaryTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testReportsOnlyMostRecentNightWhenTwoNightsAreInWindow() {
        // Tail of the night before (after yesterday midnight) plus last night.
        let previousNight: [(Date, Date)] = [
            (date("2026-06-19T00:00:00Z"), date("2026-06-19T07:00:00Z")), // 7h
        ]
        let lastNight: [(Date, Date)] = [
            (date("2026-06-19T23:00:00Z"), date("2026-06-20T07:00:00Z")), // 8h
        ]
        let session = HealthKitService.mostRecentSleepSession(
            asleep: previousNight + lastNight, inBed: []
        )

        XCTAssertEqual(session?.0, date("2026-06-19T23:00:00Z"))
        XCTAssertEqual(session?.1, date("2026-06-20T07:00:00Z"))
    }

    func testBriefWakeDoesNotSplitTheSession() {
        // 20-minute awake gap in the middle of the night stays one session.
        let intervals: [(Date, Date)] = [
            (date("2026-06-19T23:00:00Z"), date("2026-06-20T02:00:00Z")),
            (date("2026-06-20T02:20:00Z"), date("2026-06-20T07:00:00Z")),
        ]
        let session = HealthKitService.mostRecentSleepSession(asleep: intervals, inBed: [])

        XCTAssertEqual(session?.0, date("2026-06-19T23:00:00Z"))
        XCTAssertEqual(session?.1, date("2026-06-20T07:00:00Z"))
    }

    func testUnionMinutesDeduplicatesOverlappingSamples() {
        // Two sources reporting the same hour must not be summed twice.
        let intervals: [(Date, Date)] = [
            (date("2026-06-20T01:00:00Z"), date("2026-06-20T02:00:00Z")),
            (date("2026-06-20T01:30:00Z"), date("2026-06-20T02:30:00Z")),
        ]
        XCTAssertEqual(HealthKitService.unionMinutes(intervals), 90, accuracy: 0.01)
    }

    func testSummarizeSleepReportsRealisticDurationAcrossTwoNights() {
        func sample(_ start: String, _ end: String, _ value: HKCategoryValueSleepAnalysis) -> HKCategorySample {
            HKCategorySample(
                type: HKCategoryType(.sleepAnalysis), value: value.rawValue,
                start: date(start), end: date(end)
            )
        }
        let samples = [
            sample("2026-06-19T00:00:00Z", "2026-06-19T07:00:00Z", .asleepCore), // previous night tail
            sample("2026-06-19T23:00:00Z", "2026-06-20T05:30:00Z", .asleepCore),
            sample("2026-06-20T05:30:00Z", "2026-06-20T07:00:00Z", .asleepREM),
        ]
        let result = HealthKitService.summarizeSleep(samples)

        XCTAssertEqual(result.total, 8 * 60, accuracy: 1) // last night only, not 15h
        XCTAssertEqual(result.rem, 90, accuracy: 1)
    }
}
