import XCTest
@testable import ProgressaNative

final class RoutineSliceTests: XCTestCase {
    private let session = ProgressaSession(
        accessToken: "access", refreshToken: "refresh", userId: "user-1", expiresAt: .distantFuture
    )

    override func tearDown() {
        RoutineURLProtocol.handler = nil
        super.tearDown()
    }

    func testDetailPreservesRepeatedExercisesAndSetOrder() async throws {
        let client = makeClient()
        RoutineURLProtocol.handler = { request in
            switch request.url!.path {
            case "/rest/v1/routine_exercise_entries":
                return Self.response([[
                    "id": "entry-a", "routine_id": "routine", "exercise_id": "bench", "sort_order": 0,
                    "exercises": ["name": "Bench", "weight_type": "standard", "is_builtin": true],
                ], [
                    "id": "entry-b", "routine_id": "routine", "exercise_id": "bench", "sort_order": 1,
                    "exercises": ["name": "Bench", "weight_type": "standard", "is_builtin": true],
                ]])
            case "/rest/v1/routine_set_entries":
                return Self.response([[
                    "id": "set-2", "routine_exercise_entry_id": "entry-a", "routine_id": "routine",
                    "exercise_id": "bench", "reps": 8, "weight_kg": 80, "rir": 2, "side": NSNull(), "sort_order": 1,
                ], [
                    "id": "set-1", "routine_exercise_entry_id": "entry-a", "routine_id": "routine",
                    "exercise_id": "bench", "reps": 10, "weight_kg": 70, "rir": 3, "side": NSNull(), "sort_order": 0,
                ]])
            default: return Self.response([])
            }
        }
        let routine = ProgressaRoutine(id: "routine", userId: session.userId, name: "Push", createdAt: .now)

        let detail = try await client.detail(routine, session: session)

        XCTAssertEqual(detail.exercises.map(\.id), ["entry-a", "entry-b"])
        XCTAssertEqual(detail.workoutExercises(copyWeights: true).count, 2)
        XCTAssertEqual(detail.workoutExercises(copyWeights: true)[0].sets.map(\.reps), [10, 8])
    }

    func testRepsOnlyRoutineCopyDropsWeightButKeepsOtherTemplateValues() {
        let exercise = ProgressaExerciseLibraryItem(id: "squat", name: "Squat", muscleGroup: "Legs", weightType: .standard, isBuiltin: true)
        let routine = ProgressaRoutine(id: "routine", userId: session.userId, name: "Legs", createdAt: .now)
        let entry = ProgressaRoutineExercise(id: "entry", routineId: routine.id, exercise: exercise, sortOrder: 0)
        let set = ProgressaRoutineSet(
            id: "set", routineExerciseId: entry.id, routineId: routine.id, exerciseId: exercise.id,
            reps: 5, weightKg: 120, rir: 1, side: "L", sortOrder: 0
        )

        let input = ProgressaRoutineDetail(routine: routine, exercises: [entry], sets: [set])
            .workoutExercises(copyWeights: false)[0].sets[0]

        XCTAssertEqual(input.reps, 5)
        XCTAssertNil(input.weightKg)
        XCTAssertEqual(input.rir, 1)
        XCTAssertEqual(input.side, "L")
    }

    private func makeClient() -> ProgressaRoutineService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoutineURLProtocol.self]
        return ProgressaRoutineService(
            baseURL: URL(string: "https://supabase.test")!, anonKey: "anon",
            urlSession: URLSession(configuration: configuration)
        )
    }

    private static func response(_ object: Any) -> (Int, Data) {
        (200, try! JSONSerialization.data(withJSONObject: object))
    }
}

private final class RoutineURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler?(request) ?? (500, Data())
            client?.urlProtocol(self, didReceive: HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]
            )!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
