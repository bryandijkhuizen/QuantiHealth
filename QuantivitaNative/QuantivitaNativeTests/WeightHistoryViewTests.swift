import XCTest
@testable import QuantivitaNative

final class WeightHistoryViewTests: XCTestCase {
    func testThreeMonthChartUsesOneAveragePointPerWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-03T08:00:00Z"))
        let nextWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: first))
        let points = WeightHistoryView.chartPoints(from: [
            WeightSample(date: first, kg: 60),
            WeightSample(date: first.addingTimeInterval(86_400), kg: 62),
            WeightSample(date: nextWeek, kg: 64),
        ], aggregatesByWeek: true, calendar: calendar)

        XCTAssertEqual(points.map(\.kg), [61, 64])
    }

    func testYAxisFocusesOnMeasuredWeightRange() {
        let domain = WeightHistoryView.yAxisDomain(for: [
            .init(date: .distantPast, kg: 60),
            .init(date: .distantFuture, kg: 70),
        ])

        XCTAssertEqual(domain.lowerBound, 58.5, accuracy: 0.001)
        XCTAssertEqual(domain.upperBound, 71.5, accuracy: 0.001)
    }
}
