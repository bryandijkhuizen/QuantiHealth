import Foundation
import XCTest
@testable import QuantivitaNative

final class StravaTCXBuilderTests: XCTestCase {
    func testBuildsWellFormedTCXWithRequiredUploadFields() throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let workouts = [
            Workout(id: "1", title: "Run", startTime: start, durationMinutes: 20, energyKcal: 200, distanceMeters: 3_000, averageHeartRate: 140, maxHeartRate: 165, typeCode: 1),
            Workout(id: "2", title: "Run", startTime: start.addingTimeInterval(1_500), durationMinutes: 30, energyKcal: 300, distanceMeters: 5_000, averageHeartRate: 150, maxHeartRate: 175, typeCode: 1),
        ]
        let data = try XCTUnwrap(StravaTCXBuilder.build(workouts: workouts)?.data(using: .utf8))
        let parser = XMLParser(data: data)
        XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "Invalid XML")
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(xml.contains("Activity Sport=\"Running\""))
        XCTAssertTrue(xml.contains("<DistanceMeters>8000.0</DistanceMeters>"))
        XCTAssertTrue(xml.contains("<AverageHeartRateBpm><Value>146</Value>"))
        XCTAssertTrue(xml.contains("<MaximumHeartRateBpm><Value>175</Value>"))
    }

    func testUniqueStartOffsetShiftsActivityStartSoStravaDoesNotSeeADuplicate() throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let workouts = [
            Workout(id: "1", title: "Run", startTime: start, durationMinutes: 20, energyKcal: 200, distanceMeters: 3_000, typeCode: 1),
            Workout(id: "2", title: "Run", startTime: start.addingTimeInterval(1_500), durationMinutes: 30, energyKcal: 300, distanceMeters: 5_000, typeCode: 1),
        ]
        let original = try XCTUnwrap(StravaTCXBuilder.build(workouts: workouts))
        let shifted = try XCTUnwrap(StravaTCXBuilder.build(workouts: workouts, uniqueStartOffset: 120))

        let originalId = try XCTUnwrap(idValue(original))
        let shiftedId = try XCTUnwrap(idValue(shifted))
        XCTAssertNotEqual(originalId, shiftedId)
        // The source activity's start time must not appear anywhere in the shifted upload.
        XCTAssertFalse(shifted.contains(originalId))
        // Duration is preserved because both start and end shift equally.
        XCTAssertTrue(original.contains("<TotalTimeSeconds>3300</TotalTimeSeconds>"))
        XCTAssertTrue(shifted.contains("<TotalTimeSeconds>3300</TotalTimeSeconds>"))
    }

    func testRouteIsEmittedAsGPSTrackpointsSoStravaCanDrawAMap() throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let workouts = [
            Workout(id: "1", title: "Run", startTime: start, durationMinutes: 20, energyKcal: 200, distanceMeters: 3_000, typeCode: 1),
            Workout(id: "2", title: "Run", startTime: start.addingTimeInterval(1_500), durationMinutes: 30, energyKcal: 300, distanceMeters: 5_000, typeCode: 1),
        ]
        let route = [
            WorkoutRoutePoint(time: start, latitude: 52.1, longitude: 4.3, altitudeMeters: 12, cumulativeDistanceMeters: 0),
            WorkoutRoutePoint(time: start.addingTimeInterval(60), latitude: 52.2, longitude: 4.4, altitudeMeters: 14, cumulativeDistanceMeters: 250),
        ]
        let xml = try XCTUnwrap(StravaTCXBuilder.build(workouts: workouts, uniqueStartOffset: 120, route: route))

        let data = try XCTUnwrap(xml.data(using: .utf8))
        XCTAssertTrue(XMLParser(data: data).parse())
        XCTAssertTrue(xml.contains("<LatitudeDegrees>52.1000000</LatitudeDegrees>"))
        XCTAssertTrue(xml.contains("<LongitudeDegrees>4.4000000</LongitudeDegrees>"))
        XCTAssertTrue(xml.contains("<AltitudeMeters>14.0</AltitudeMeters>"))
        // Trackpoint times are shifted by the same unique offset as the activity start.
        let shifted = ISO8601DateFormatter().string(from: start.addingTimeInterval(120))
        XCTAssertTrue(xml.contains("<Time>\(shifted)</Time>"))
    }

    private func idValue(_ xml: String) -> String? {
        guard let open = xml.range(of: "<Id>"), let close = xml.range(of: "</Id>") else { return nil }
        return String(xml[open.upperBound..<close.lowerBound])
    }
}
