import XCTest
@testable import QuantivitaNative

final class WorkoutDecodingTests: XCTestCase {
    func testProgressaDetailDecodesWithoutLosingSetMetadata() throws {
        let json = #"""
        {
          "id":"progressa:p-123","source":"progressa","externalWorkoutId":"p-123",
          "title":"Strength","startTime":"2026-06-18T08:30:00Z","durationMinutes":0,"energyKcal":0,
          "progressaDetails":{"exerciseCount":1,"totalSets":2,"totalVolumeKg":540,"hasVolumeData":true,
            "exercises":[{"id":"bench","name":"Bench Press","muscleGroup":"Chest","sets":[
              {"weightKg":20,"reps":10,"rir":null,"side":null,"isWarmup":true,"createdAt":"a"},
              {"weightKg":60,"reps":8,"rir":2,"side":"left","isWarmup":false,"createdAt":"b"}
            ]}]}
        }
        """#.data(using: .utf8)!

        let workout = try JSONDecoder().decode(Workout.self, from: json)

        XCTAssertEqual(workout.progressaDetails?.exercises.first?.sets.count, 2)
        XCTAssertEqual(workout.progressaDetails?.exercises.first?.sets.last?.rir, 2)
        XCTAssertEqual(workout.progressaDetails?.exercises.first?.sets.last?.side, "left")
        XCTAssertEqual(workout.effectiveDurationMinutes, 9, accuracy: 0.01)
        XCTAssertGreaterThan(workout.effectiveEnergyKcal, 0)
    }

    func testEpochDateDecodes() throws {
        let json = #"{"id":"x","title":"Run","startTime":1750235400,"durationMinutes":30,"energyKcal":250}"#.data(using: .utf8)!
        let workout = try JSONDecoder().decode(Workout.self, from: json)
        XCTAssertEqual(workout.startTime.timeIntervalSince1970, 1_750_235_400, accuracy: 0.1)
    }

    func testSwiftReferenceDateDecodesFromCache() throws {
        let start = ISO8601DateFormatter().date(from: "2026-07-04T16:32:00Z")!
        let cached = try JSONEncoder().encode(Workout(id: "x", title: "Swim", startTime: start, durationMinutes: 9, energyKcal: 62))
        let workout = try JSONDecoder().decode(Workout.self, from: cached)
        XCTAssertEqual(workout.startTime.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 0.1)
    }
}
