import XCTest
@testable import ProgressaNative

@MainActor
final class WorkoutSliceTests: XCTestCase {
    private let session = ProgressaSession(
        accessToken: "access", refreshToken: "refresh", userId: "user-a", expiresAt: .distantFuture
    )

    func testCacheIsIsolatedByUser() throws {
        let directory = temporaryDirectory()
        let cache = WorkoutCache(directory: directory)
        let workout = sampleWorkout(id: "one")

        try cache.save([workout], userId: "user-a", at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(cache.load(userId: "user-a")?.workouts, [workout])
        XCTAssertNil(cache.load(userId: "user-b"))
    }

    func testFailedRefreshRestoresCachedWorkoutsAndMarksStale() async throws {
        let cache = WorkoutCache(directory: temporaryDirectory())
        let workout = sampleWorkout(id: "cached")
        let savedAt = Date(timeIntervalSince1970: 100)
        try cache.save([workout], userId: session.userId, at: savedAt)
        let service = FakeWorkoutService()
        service.error = ProgressaClientError.invalidResponse
        let model = ProgressaModel(workoutService: service, workoutCache: cache)
        model.session = session

        await model.refreshWorkouts()

        XCTAssertEqual(model.workouts, [workout])
        XCTAssertEqual(model.workoutSyncState, .cached(savedAt))
    }

    func testDetailRefreshAndMutationsUpdateCachedList() async throws {
        let cache = WorkoutCache(directory: temporaryDirectory())
        let service = FakeWorkoutService()
        let original = sampleWorkout(id: "one")
        service.workouts = [original]
        service.detail = ProgressaWorkout(
            id: "one", title: "Detailed", createdAt: original.createdAt,
            exercises: [ProgressaExercise(id: "exercise", name: "Squat", sets: [])]
        )
        let model = ProgressaModel(workoutService: service, workoutCache: cache)
        model.session = session

        await model.refreshWorkouts()
        await model.refreshWorkout(id: "one")
        XCTAssertEqual(model.workouts.first?.exercises.first?.name, "Squat")

        let updated = await model.updateWorkout(id: "one", title: "Renamed", createdAt: original.createdAt)
        XCTAssertTrue(updated)
        XCTAssertEqual(model.workouts.first?.title, "Renamed")
        XCTAssertEqual(model.workouts.first?.exercises.first?.name, "Squat")

        let deleted = await model.deleteWorkout(id: "one")
        XCTAssertTrue(deleted)
        XCTAssertTrue(model.workouts.isEmpty)
        XCTAssertTrue(cache.load(userId: session.userId)?.workouts.isEmpty == true)
    }

    func testCreateExerciseSetAndDetailRefreshFlow() async throws {
        let cache = WorkoutCache(directory: temporaryDirectory())
        let service = FakeWorkoutService()
        let model = ProgressaModel(workoutService: service, workoutCache: cache)
        model.session = session
        let bench = ProgressaExerciseLibraryItem(
            id: "bench", name: "Bench press", muscleGroup: "Chest",
            weightType: .standard, isBuiltin: true
        )
        let setInput = ProgressaSetInput(weightKg: 82.5, reps: 8, rir: 1.5, side: nil, isWarmup: false)

        let workoutId = await model.createWorkout(
            title: "Push", createdAt: Date(timeIntervalSince1970: 100),
            exercises: [ProgressaExerciseInput(exercise: bench, sets: [setInput])]
        )

        XCTAssertEqual(workoutId, "new")
        XCTAssertEqual(service.addedExerciseIds, ["bench"])
        XCTAssertEqual(service.addedSetInputs, [setInput])
        XCTAssertEqual(model.workouts.first?.exercises.first?.sets.first?.weightKg, 82.5)
        XCTAssertEqual(cache.load(userId: session.userId)?.workouts.first?.totalSets, 1)

        service.detail = model.workouts.first
        await model.refreshWorkout(id: "new")

        XCTAssertEqual(service.fetchedDetailIds, ["new"])
        XCTAssertEqual(model.workouts.first?.exercises.first?.name, "Bench press")
        XCTAssertEqual(model.workouts.first?.totalSets, 1)
    }

    func testCreateEmptyWorkoutRemainsSupported() async throws {
        let model = ProgressaModel(
            workoutService: FakeWorkoutService(), workoutCache: WorkoutCache(directory: temporaryDirectory())
        )
        model.session = session

        let id = await model.createWorkout(title: "Workout", createdAt: .now, exercises: [])

        XCTAssertEqual(id, "new")
        XCTAssertEqual(model.workouts.first?.title, "Workout")
        XCTAssertTrue(model.workouts.first?.exercises.isEmpty == true)
    }

    private func sampleWorkout(id: String) -> ProgressaWorkout {
        ProgressaWorkout(id: id, title: "Workout", createdAt: Date(timeIntervalSince1970: 50), exercises: [])
    }

    func testCustomExerciseRenameAndDeleteCallService() async {
        let service = FakeWorkoutService()
        let model = ProgressaModel(workoutService: service, workoutCache: WorkoutCache(directory: temporaryDirectory()))
        model.session = session

        let renamed = await model.renameCustomExercise(id: "ex-1", name: "Incline Press")
        let deleted = await model.deleteCustomExercise(id: "ex-2")

        XCTAssertTrue(renamed)
        XCTAssertTrue(deleted)
        XCTAssertEqual(service.renamedExercises.map(\.0), ["ex-1"])
        XCTAssertEqual(service.renamedExercises.map(\.1), ["Incline Press"])
        XCTAssertEqual(service.deletedExerciseIds, ["ex-2"])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private final class FakeWorkoutService: ProgressaWorkoutServing {
    var workouts: [ProgressaWorkout] = []
    var detail: ProgressaWorkout?
    var error: Error?
    var addedExerciseIds: [String] = []
    var addedSetInputs: [ProgressaSetInput] = []
    var fetchedDetailIds: [String] = []
    var renamedExercises: [(String, String)] = []
    var deletedExerciseIds: [String] = []

    func renameCustomExercise(id: String, name: String, session: ProgressaSession) async throws {
        if let error { throw error }
        renamedExercises.append((id, name))
    }

    func deleteCustomExercise(id: String, session: ProgressaSession) async throws {
        if let error { throw error }
        deletedExerciseIds.append(id)
    }

    func fetchWorkouts(session: ProgressaSession) async throws -> [ProgressaWorkout] {
        if let error { throw error }
        return workouts
    }

    func fetchWorkout(id: String, session: ProgressaSession) async throws -> ProgressaWorkout? {
        if let error { throw error }
        fetchedDetailIds.append(id)
        return detail
    }

    func createWorkout(title: String, createdAt: Date, session: ProgressaSession) async throws -> ProgressaWorkout {
        if let error { throw error }
        return ProgressaWorkout(id: "new", title: title, createdAt: createdAt, exercises: [])
    }

    func updateWorkout(id: String, title: String, createdAt: Date, session: ProgressaSession) async throws -> ProgressaWorkout {
        if let error { throw error }
        return ProgressaWorkout(id: id, title: title, createdAt: createdAt, exercises: [])
    }

    func deleteWorkout(id: String, session: ProgressaSession) async throws {
        if let error { throw error }
    }

    func fetchExercises(query: String, session: ProgressaSession) async throws -> [ProgressaExerciseLibraryItem] {
        if let error { throw error }
        return []
    }

    func addExercise(
        _ input: ProgressaExerciseInput, workoutId: String, sortOrder: Int, session: ProgressaSession
    ) async throws -> ProgressaExercise {
        if let error { throw error }
        addedExerciseIds.append(input.exercise.id)
        var exercise = ProgressaExercise(
            id: "block-new", exerciseId: input.exercise.id, name: input.exercise.name,
            muscleGroup: input.exercise.muscleGroup, weightType: input.exercise.weightType,
            sortOrder: sortOrder, sets: []
        )
        for set in input.sets {
            exercise.sets.append(try await addSet(set, workoutId: workoutId, block: exercise, session: session))
        }
        return exercise
    }

    func addSet(
        _ input: ProgressaSetInput, workoutId: String, block: ProgressaExercise, session: ProgressaSession
    ) async throws -> ProgressaWorkoutSet {
        if let error { throw error }
        addedSetInputs.append(input)
        return ProgressaWorkoutSet(
            id: "set-new", weightKg: input.weightKg, reps: input.reps, rir: input.rir,
            side: input.side, isWarmup: input.isWarmup
        )
    }

    func updateSet(
        _ input: ProgressaSetInput, setId: String, session: ProgressaSession
    ) async throws -> ProgressaWorkoutSet {
        if let error { throw error }
        return ProgressaWorkoutSet(
            id: setId, weightKg: input.weightKg, reps: input.reps, rir: input.rir,
            side: input.side, isWarmup: input.isWarmup
        )
    }

    func deleteSet(id: String, session: ProgressaSession) async throws {
        if let error { throw error }
    }

    func deleteExerciseBlock(id: String, workoutId: String, session: ProgressaSession) async throws {
        if let error { throw error }
    }

    func reorderExerciseBlocks(
        workoutId: String, orderedBlockIds: [String], session: ProgressaSession
    ) async throws {
        if let error { throw error }
    }
}
