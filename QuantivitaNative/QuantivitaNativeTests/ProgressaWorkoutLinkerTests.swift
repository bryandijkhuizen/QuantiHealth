import XCTest
@testable import QuantivitaNative

final class ProgressaWorkoutLinkerTests: XCTestCase {
    private let start = ISO8601DateFormatter().date(from: "2026-06-18T18:00:00Z")!

    func testOnlyExplicitlyLinkedWorkoutAttachesToHealthActivity() {
        let health = healthWorkout(id: "health-1")
        let linked = progressaWorkout(id: "progressa-1", linked: true)
        let unlinked = progressaWorkout(id: "progressa-2", linked: false)

        let result = ProgressaWorkoutLinker.attach([unlinked, linked], to: [health])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "health-1")
        XCTAssertEqual(result[0].externalWorkoutId, "progressa-1")
        XCTAssertEqual(result[0].progressaDetails?.totalSets, 1)
        XCTAssertFalse(result[0].isProgressa)
    }

    func testLinkedWorkoutWithoutMatchingHealthActivityIsNotShown() {
        let linked = progressaWorkout(id: "progressa-1", linked: true)
        let otherHealth = healthWorkout(id: "health-2", start: start.addingTimeInterval(3_600))

        let result = ProgressaWorkoutLinker.attach([linked], to: [otherHealth])

        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].progressaDetails)
        XCTAssertNil(result[0].externalWorkoutId)
    }

    func testRemovedLinkClearsPreviouslyCachedDetails() {
        var health = healthWorkout(id: "health-1")
        health.externalWorkoutId = "deleted-progressa"
        health.progressaDetails = details

        let result = ProgressaWorkoutLinker.attach([], to: [health])

        XCTAssertNil(result[0].externalWorkoutId)
        XCTAssertNil(result[0].progressaDetails)
    }

    func testDuplicateLinksCannotCreateStandaloneOrDuplicateHealthRows() {
        let links = [
            progressaWorkout(id: "z-workout", linked: true),
            progressaWorkout(id: "a-workout", linked: true),
        ]

        let result = ProgressaWorkoutLinker.attach(links, to: [healthWorkout(id: "health-1")])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].externalWorkoutId, "a-workout")
    }

    private func healthWorkout(id: String, start: Date? = nil) -> Workout {
        Workout(id: id, title: "Strength Training", startTime: start ?? self.start, durationMinutes: 60, energyKcal: 300, typeCode: 50)
    }

    private func progressaWorkout(id: String, linked: Bool) -> Workout {
        Workout(
            id: "progressa:\(id)", source: "progressa", externalWorkoutId: id,
            title: "Upper Body", startTime: start, durationMinutes: 60, energyKcal: 0,
            healthActivityLink: linked ? HealthActivityLink(
                healthStart: "2026-06-18T18:00:00Z", healthEnd: "2026-06-18T19:00:00Z",
                activityType: "Traditional Strength Training", durationSeconds: 3_600
            ) : nil,
            progressaDetails: details
        )
    }

    private var details: ProgressaDetails {
        ProgressaDetails(
            exerciseCount: 1, totalSets: 1, totalVolumeKg: 800, hasVolumeData: true,
            exercises: [ProgressaExercise(
                id: "bench", name: "Bench Press", muscleGroup: "Chest",
                sets: [ProgressaSet(weightKg: 80, reps: 10, rir: 2, side: nil, isWarmup: false, createdAt: nil)]
            )]
        )
    }
}
