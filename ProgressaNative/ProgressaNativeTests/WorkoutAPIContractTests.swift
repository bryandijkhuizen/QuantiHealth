import XCTest
@testable import ProgressaNative

final class WorkoutAPIContractTests: XCTestCase {
    private var client: ProgressaClient!
    private let session = ProgressaSession(
        accessToken: "access", refreshToken: "refresh", userId: "user-1", expiresAt: .distantFuture
    )

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkoutURLProtocol.self]
        client = ProgressaClient(
            supabaseURL: URL(string: "https://supabase.test")!,
            connectURL: URL(string: "https://connect.test")!,
            urlSession: URLSession(configuration: configuration), anonKey: "anon"
        )
    }

    override func tearDown() {
        WorkoutURLProtocol.handler = nil
        client = nil
        super.tearDown()
    }

    func testEmptyWorkoutResponseDoesNotRequestDetailTables() async throws {
        var paths: [String] = []
        WorkoutURLProtocol.handler = { request in
            paths.append(request.url!.path)
            return (200, Data("[]".utf8))
        }

        let workouts = try await client.fetchWorkouts(session: session)

        XCTAssertTrue(workouts.isEmpty)
        XCTAssertEqual(paths, ["/rest/v1/workouts"])
    }

    func testWorkoutListLoadsHeadersWithoutEagerSetHistory() async throws {
        var paths: [String] = []
        WorkoutURLProtocol.handler = { request in
            paths.append(request.url!.path)
            return (200, Self.json([[
                "id": "workout-1", "title": "Header only",
                "created_at": "2026-06-18T20:10:11.123456Z", "source": "manual",
            ]]))
        }

        let workouts = try await client.fetchWorkouts(session: session)

        XCTAssertEqual(workouts.map(\.id), ["workout-1"])
        XCTAssertTrue(workouts[0].exercises.isEmpty)
        XCTAssertEqual(paths, ["/rest/v1/workouts"])
    }

    func testDetailKeepsRepeatedAndEmptyExerciseBlocksWithServerOrder() async throws {
        WorkoutURLProtocol.handler = { request in
            switch request.url!.path {
            case "/rest/v1/workouts":
                return (200, Self.json([[
                    "id": "workout-1", "title": "Repeated bench",
                    "created_at": "2026-06-18T20:10:11.123456Z", "source": "manual", "location": "Gym"
                ]]))
            case "/rest/v1/workout_exercise_blocks":
                return (200, Self.json([
                    ["id": "block-a", "workout_id": "workout-1", "exercise_id": "bench", "sort_order": 0,
                     "exercises": ["name": "Bench press", "weight_type": "standard"]],
                    ["id": "block-b", "workout_id": "workout-1", "exercise_id": "bench", "sort_order": 1,
                     "exercises": ["name": "Bench press", "weight_type": "standard"]],
                ]))
            case "/rest/v1/sets":
                return (200, Self.json([[
                    "id": "set-b", "workout_id": "workout-1", "exercise_id": "bench",
                    "exercise_block_id": "block-b", "weight_kg": NSNull(), "reps": NSNull(),
                    "rir": NSNull(), "side": NSNull(), "is_warmup": false,
                    "created_at": "2026-06-18T20:11:12.987654Z"
                ]]))
            case "/rest/v1/workout_exercise_block_order":
                return (200, Self.json([
                    ["workout_id": "workout-1", "exercise_block_id": "block-b", "sort_order": 0],
                    ["workout_id": "workout-1", "exercise_block_id": "block-a", "sort_order": 1],
                ]))
            default:
                return (404, Self.json(["message": "Unexpected path \(request.url!.path)"]))
            }
        }

        let fetchedWorkout = try await client.fetchWorkout(id: "workout-1", session: session)
        let workout = try XCTUnwrap(fetchedWorkout)

        XCTAssertEqual(workout.source, "manual")
        XCTAssertEqual(workout.location, "Gym")
        XCTAssertEqual(workout.exercises.map(\.id), ["block-b", "block-a"])
        XCTAssertEqual(workout.exercises.map(\.exerciseId), ["bench", "bench"])
        XCTAssertTrue(workout.exercises[1].sets.isEmpty, "An exercise block remains visible without sets")
        let set = try XCTUnwrap(workout.exercises[0].sets.first)
        XCTAssertNil(set.weightKg)
        XCTAssertNil(set.reps)
        XCTAssertNil(set.rir)
        XCTAssertNil(set.side)
        XCTAssertEqual(set.createdAt.timeIntervalSince1970, 1_781_813_472.987654, accuracy: 0.001)
    }

    func testFetchWorkoutsDoesNotApplyLegacyFiftyWorkoutLimit() async throws {
        let headers: [[String: Any]] = (0..<51).map { index in
            [
                "id": "workout-\(index)", "title": "Workout \(index)",
                "created_at": String(format: "2026-06-18T20:%02d:00Z", index),
                "source": "manual",
            ]
        }
        WorkoutURLProtocol.handler = { request in
            request.url!.path == "/rest/v1/workouts"
                ? (200, Self.json(headers))
                : (200, Data("[]".utf8))
        }

        let workouts = try await client.fetchWorkouts(session: session)

        XCTAssertEqual(workouts.count, 51)
        XCTAssertFalse(workouts.contains { $0.id.isEmpty })
    }

    func testDetailKeepsLegacySetsWithoutExerciseBlock() async throws {
        WorkoutURLProtocol.handler = { request in
            switch request.url!.path {
            case "/rest/v1/workouts":
                return (200, Self.json([[
                    "id": "legacy-workout", "title": "Old workout",
                    "created_at": "2026-06-18T20:10:11.123456Z", "source": "manual",
                ]]))
            case "/rest/v1/sets":
                return (200, Self.json([[
                    "id": "legacy-set", "workout_id": "legacy-workout", "exercise_id": "squat",
                    "exercise_block_id": NSNull(), "weight_kg": 100, "reps": 5, "rir": 2,
                    "side": "L", "is_warmup": false, "created_at": "2026-06-18T20:11:00Z",
                    "exercises": ["name": "Squat", "weight_type": "standard"],
                ]]))
            case "/rest/v1/workout_exercise_blocks", "/rest/v1/workout_exercise_block_order":
                return (200, Data("[]".utf8))
            default:
                return (404, Self.json(["message": "Unexpected request"]))
            }
        }

        let fetchedWorkout = try await client.fetchWorkout(id: "legacy-workout", session: session)
        let workout = try XCTUnwrap(fetchedWorkout)

        XCTAssertEqual(workout.exercises.count, 1)
        XCTAssertEqual(workout.exercises.first?.name, "Squat")
        XCTAssertEqual(workout.exercises.first?.sets.first?.id, "legacy-set")
        XCTAssertEqual(workout.exercises.first?.sets.first?.side, "L")
    }

    func testCreateAcceptsFractionalTimestampFromSupabase() async throws {
        WorkoutURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/rest/v1/workouts")
            return (201, Self.json([[
                "id": "created", "user_id": "user-1", "title": "Leg day",
                "created_at": "2026-06-18T20:10:11.123456Z", "source": "manual", "location": NSNull(),
            ]]))
        }

        let workout = try await client.createWorkout(title: "Leg day", createdAt: .now, session: session)

        XCTAssertEqual(workout.id, "created")
        XCTAssertEqual(workout.title, "Leg day")
        XCTAssertEqual(workout.createdAt.timeIntervalSince1970, 1_781_813_411.123456, accuracy: 0.001)
    }

    func testAddSetSerializesMissingValuesAsJSONNull() async throws {
        WorkoutURLProtocol.handler = { request in
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
            let row = try XCTUnwrap(rows.first)
            XCTAssertTrue(row["weight_kg"] is NSNull)
            XCTAssertTrue(row["reps"] is NSNull)
            XCTAssertTrue(row["rir"] is NSNull)
            XCTAssertTrue(row["side"] is NSNull)
            return (201, Self.json([[
                "id": "set-1", "weight_kg": NSNull(), "reps": NSNull(), "rir": NSNull(),
                "side": NSNull(), "is_warmup": false, "created_at": "2026-06-18T20:10:11.123456Z",
            ]]))
        }
        let block = ProgressaExercise(id: "block-1", exerciseId: "bench", name: "Bench", sets: [])

        let set = try await client.addSet(
            ProgressaSetInput(), workoutId: "workout-1", block: block, session: session
        )

        XCTAssertNil(set.weightKg)
        XCTAssertNil(set.reps)
        XCTAssertNil(set.side)
    }

    private static func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    func testLastWeightForExerciseQueriesMostRecentSetForThisUserAndExercise() async throws {
        var request: URLRequest?
        WorkoutURLProtocol.handler = { req in
            request = req
            return (200, Self.json([["weight_kg": 62.5]]))
        }

        let weight = try await client.lastWeightForExercise("bench", session: session)

        XCTAssertEqual(weight, 62.5)
        let components = URLComponents(url: try XCTUnwrap(request?.url), resolvingAgainstBaseURL: false)
        let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(request?.url?.path, "/rest/v1/sets")
        XCTAssertEqual(items["user_id"], "eq.user-1")
        XCTAssertEqual(items["exercise_id"], "eq.bench")
        XCTAssertEqual(items["order"], "created_at.desc")
        XCTAssertEqual(items["limit"], "1")
    }

    func testLastWeightForExerciseReturnsNilWithNoHistory() async throws {
        WorkoutURLProtocol.handler = { _ in (200, Self.json([])) }

        let weight = try await client.lastWeightForExercise("bench", session: session)

        XCTAssertNil(weight)
    }

    func testPreviousSetStructureLoadsOnlyLatestBlockOfRepeatedExercise() async throws {
        var requests: [URLRequest] = []
        WorkoutURLProtocol.handler = { request in
            requests.append(request)
            let query = request.url?.query ?? ""
            if query.contains("workout_id=eq.") {
                return (200, Self.json([
                    ["weight_kg": 110, "reps": 10, "rir": NSNull(), "side": NSNull(), "is_warmup": false, "created_at": "2026-06-18T20:00:00Z"],
                    ["weight_kg": 115, "reps": 10, "rir": NSNull(), "side": NSNull(), "is_warmup": false, "created_at": "2026-06-18T20:01:00Z"],
                    ["weight_kg": 115, "reps": 8, "rir": NSNull(), "side": NSNull(), "is_warmup": false, "created_at": "2026-06-18T20:02:00Z"],
                ]))
            }
            return (200, Self.json([["workout_id": "workout-7", "exercise_block_id": "block-3"]]))
        }

        let structure = try await client.previousSetStructure("bench", session: session)

        XCTAssertEqual(structure.map(\.weightKg), [110, 115, 115])
        XCTAssertEqual(structure.map(\.reps), [10, 10, 8])
        XCTAssertEqual(requests.count, 2)
        let firstItems = Dictionary(uniqueKeysWithValues: (URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(firstItems["order"], "created_at.desc")
        XCTAssertEqual(firstItems["limit"], "1")
        let secondItems = Dictionary(uniqueKeysWithValues: (URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(secondItems["workout_id"], "eq.workout-7")
        XCTAssertEqual(secondItems["exercise_block_id"], "eq.block-3")
        XCTAssertEqual(secondItems["order"], "created_at.asc")
    }

    func testPreviousSetStructureReturnsEmptyWithNoHistory() async throws {
        WorkoutURLProtocol.handler = { _ in (200, Self.json([])) }

        let structure = try await client.previousSetStructure("bench", session: session)

        XCTAssertTrue(structure.isEmpty)
    }

    func testFinishWorkoutPersistsTimesAndReturnsCompletedState() async throws {
        let start = Date(timeIntervalSince1970: 100)
        let end = Date(timeIntervalSince1970: 200)
        WorkoutURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let row = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(row["start_time"] as? String, "1970-01-01T00:01:40Z")
            XCTAssertEqual(row["end_time"] as? String, "1970-01-01T00:03:20Z")
            return (200, Self.json([["id": "workout-1", "title": "Workout", "created_at": "1970-01-01T00:01:40Z",
                                      "start_time": row["start_time"]!, "end_time": row["end_time"]!]]))
        }
        let workout = try await client.updateWorkoutTiming(id: "workout-1", startedAt: start, endedAt: end, session: session)
        XCTAssertFalse(workout.isInProgress)
        XCTAssertEqual(workout.startedAt, start)
        XCTAssertEqual(workout.endedAt, end)
    }

    func testReopeningWorkoutSendsExplicitNullEnd() async throws {
        WorkoutURLProtocol.handler = { request in
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let row = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertTrue(row["end_time"] is NSNull)
            return (200, Self.json([["id": "workout-1", "title": "Workout", "created_at": "1970-01-01T00:01:40Z",
                                      "start_time": row["start_time"]!, "end_time": NSNull()]]))
        }
        let workout = try await client.updateWorkoutTiming(id: "workout-1", startedAt: Date(timeIntervalSince1970: 100), endedAt: nil, session: session)
        XCTAssertTrue(workout.isInProgress)
    }

    func testSequenceUsesSingleAtomicRequestAndPreservesExerciseOrder() async throws {
        var calls = 0
        WorkoutURLProtocol.handler = { request in
            calls += 1
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/add_workout_sequence")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let row = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(row["p_exercise_ids"] as? [String], ["squat", "bench", "row"])
            XCTAssertEqual(row["p_rounds"] as? Int, 3)
            return (204, Data())
        }
        try await client.addSequence(workoutId: "workout-1", exerciseIDs: ["squat", "bench", "row"], rounds: 3, session: session)
        XCTAssertEqual(calls, 1)
    }

    func testLegacyHistoryDoesNotIncludeOtherExerciseBlocks() async throws {
        var calls = 0
        WorkoutURLProtocol.handler = { request in
            calls += 1
            if calls == 1 { return (200, Self.json([["workout_id": "legacy"]])) }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "exercise_block_id" }?.value, "is.null")
            return (200, Self.json([]))
        }
        _ = try await client.previousSetStructure("bench", session: session)
        XCTAssertEqual(calls, 2)
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

}

private final class WorkoutURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (status, data) = try Self.handler?(request) ?? (500, Data())
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
