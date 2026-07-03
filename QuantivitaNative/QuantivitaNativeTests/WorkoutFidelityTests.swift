import CoreLocation
import XCTest
@testable import QuantivitaNative

final class WorkoutFidelityTests: XCTestCase {
    func testOnlyExactHealthKitUUIDsAreSelectedAsSources() {
        let valid = UUID()
        let workouts = [
            workout(id: valid.uuidString),
            workout(id: "not-a-uuid"),
            workout(id: UUID().uuidString, source: "progressa"),
        ]

        XCTAssertEqual(WorkoutFidelity.sourceUUIDs(for: workouts), [valid])
    }

    func testHeartRateAverageIsWeightedByWorkoutDuration() {
        let short = workout(id: UUID().uuidString, duration: 10, averageHeartRate: 100)
        let long = workout(id: UUID().uuidString, duration: 30, averageHeartRate: 140)

        XCTAssertEqual(WorkoutFidelity.weightedAverageHeartRate(for: [short, long]), 130, accuracy: 0.001)
    }

    func testLocationsAreSortedAndExactDuplicatesRemoved() {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = location(latitude: 52, longitude: 4, altitude: 10, date: start)
        let duplicate = location(latitude: 52, longitude: 4, altitude: 99, date: start)
        let second = location(latitude: 52.1, longitude: 4.1, altitude: 15, date: start.addingTimeInterval(1))

        let result = WorkoutFidelity.deduplicatedLocations([second, duplicate, first])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.timestamp), [start, start.addingTimeInterval(1)])
    }

    func testElevationGainIgnoresDescent() {
        let start = Date(timeIntervalSince1970: 1_000)
        let locations = [10.0, 16.0, 13.0, 20.0].enumerated().map {
            location(latitude: 52, longitude: 4 + Double($0.offset) / 100, altitude: $0.element, date: start.addingTimeInterval(Double($0.offset)))
        }
        XCTAssertEqual(WorkoutFidelity.elevationGain(locations), 13, accuracy: 0.001)
    }

    func testMovingDurationCountsActiveTimeNotMultiDaySpan() {
        let day1 = Date(timeIntervalSince1970: 1_000_000)
        let day3 = day1.addingTimeInterval(2 * 86_400) // two days later
        let walk = timedWorkout(start: day1, minutes: 57)
        let run = timedWorkout(start: day3, minutes: 32)

        // The wall-clock span is ~48h; the active time is only 89 minutes.
        XCTAssertEqual(WorkoutFidelity.movingDuration(for: [run, walk]), 89 * 60, accuracy: 0.001)
    }

    func testOverlappingWorkoutsCountSharedTimeOnce() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = timedWorkout(start: start, minutes: 60)
        let overlapping = timedWorkout(start: start.addingTimeInterval(30 * 60), minutes: 60)

        XCTAssertEqual(WorkoutFidelity.activeSegments(for: [first, overlapping]).count, 1)
        XCTAssertEqual(WorkoutFidelity.movingDuration(for: [first, overlapping]), 90 * 60, accuracy: 0.001)
    }

    func testPausedGapsCoverTheIdleTimeBetweenWorkouts() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = timedWorkout(start: start, minutes: 30)
        let second = timedWorkout(start: start.addingTimeInterval(90 * 60), minutes: 30)

        let gaps = WorkoutFidelity.pausedGaps(for: [first, second])
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(try XCTUnwrap(gaps.first).duration, 60 * 60, accuracy: 0.001) // the hour between them
    }

    private func timedWorkout(start: Date, minutes: Double) -> Workout {
        Workout(id: UUID().uuidString, title: "Workout", startTime: start, durationMinutes: minutes, energyKcal: 0)
    }

    private func workout(
        id: String, source: String = "healthkit", duration: Double = 30,
        averageHeartRate: Double = 0
    ) -> Workout {
        Workout(
            id: id, source: source, title: "Workout", startTime: .now,
            durationMinutes: duration, energyKcal: 0, averageHeartRate: averageHeartRate
        )
    }

    private func location(latitude: Double, longitude: Double, altitude: Double, date: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude, horizontalAccuracy: 1, verticalAccuracy: 1,
            timestamp: date
        )
    }
}
