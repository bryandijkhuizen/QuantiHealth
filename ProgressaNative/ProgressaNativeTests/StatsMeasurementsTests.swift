import XCTest
@testable import ProgressaNative

final class StatsMeasurementsTests: XCTestCase {
    private var urlSession: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatsURLProtocol.self]
        urlSession = URLSession(configuration: configuration)
    }

    override func tearDown() {
        StatsURLProtocol.handler = nil
        urlSession.invalidateAndCancel()
        super.tearDown()
    }

    func testSummaryHandlesBodyweightAndAssistedSets() {
        let now = Date.now
        let rows = [
            ProgressaSetStat(id: "1", workoutId: "w1", exerciseId: "bench", exerciseName: "Bench", weightType: .standard, weightKg: 100, reps: 5, createdAt: now, workoutCreatedAt: nil),
            ProgressaSetStat(id: "2", workoutId: "w1", exerciseId: "pullup", exerciseName: "Pull-up", weightType: .bodyweight, weightKg: 80, reps: 10, createdAt: now, workoutCreatedAt: nil),
            ProgressaSetStat(id: "3", workoutId: "w2", exerciseId: "assisted", exerciseName: "Assisted pull-up", weightType: .assisted, weightKg: -15, reps: 8, createdAt: now, workoutCreatedAt: nil),
        ]
        let summary = ProgressaStatsSummary.calculate(rows)
        XCTAssertEqual(summary.workoutCount, 2)
        XCTAssertEqual(summary.setCount, 3)
        XCTAssertEqual(summary.repCount, 23)
        XCTAssertEqual(summary.volumeKg, 380, accuracy: 0.001)
        XCTAssertEqual(summary.personalRecords.first(where: { $0.exerciseId == "pullup" })?.value, 10)
    }

    func testImperialMeasurementConversionsRoundTrip() {
        let pounds = MeasurementUnitSystem.imperial.displayValue(100, type: .weight)
        XCTAssertEqual(pounds, 220.462, accuracy: 0.001)
        XCTAssertEqual(MeasurementUnitSystem.imperial.storageValue(pounds, type: .weight), 100, accuracy: 0.001)
        XCTAssertEqual(MeasurementUnitSystem.imperial.displayValue(2.54, type: .waist), 1, accuracy: 0.001)
    }

    func testSetPaginationLoadsEveryPage() async throws {
        var offsets: [String] = []
        StatsURLProtocol.handler = { request in
            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            let offset = components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? ""
            offsets.append(offset)
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer access")
            if offset == "0" { return (200, Self.setRows(ids: ["1", "2"])) }
            return (200, Self.setRows(ids: ["3"]))
        }
        let values = try await service(pageSize: 2).fetchAllSets(session: session)
        XCTAssertEqual(values.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(offsets, ["0", "2"])
        XCTAssertEqual(values.first?.exerciseName, "Bench Press")
    }

    func testMeasurementListAddNoteAndDeleteContracts() async throws {
        var methods: [String] = []
        StatsURLProtocol.handler = { request in
            methods.append(request.httpMethod ?? "")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon")
            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            if request.httpMethod == "DELETE" {
                XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "user_id" })?.value, "eq.user-1")
                return (204, Data())
            }
            if request.httpMethod == "PATCH" {
                let body = try JSONSerialization.jsonObject(with: try Self.bodyData(request)) as? [String: Any]
                XCTAssertEqual(body?["note"] as? String, "Progress")
            }
            if request.httpMethod == "POST" {
                let body = try JSONSerialization.jsonObject(with: try Self.bodyData(request)) as? [String: Any]
                XCTAssertEqual(body?["type"] as? String, "WEIGHT")
                XCTAssertEqual(body?["user_id"] as? String, "user-1")
            }
            return (request.httpMethod == "POST" ? 201 : 200, Self.measurementJSON)
        }

        let api = service()
        let listed = try await api.fetchMeasurements(session: session)
        XCTAssertEqual(listed.first?.type, .weight)
        _ = try await api.addMeasurement(type: .weight, value: 80, measuredAt: .now, note: nil, session: session)
        _ = try await api.updateMeasurementNote(id: "m1", note: " Progress ", session: session)
        try await api.deleteMeasurement(id: "m1", session: session)
        XCTAssertEqual(methods, ["GET", "POST", "PATCH", "DELETE"])
    }

    private func service(pageSize: Int = 1_000) -> StatsMeasurementsService {
        StatsMeasurementsService(
            baseURL: URL(string: "https://supabase.test")!, anonKey: "anon",
            urlSession: urlSession, pageSize: pageSize
        )
    }

    private var session: ProgressaSession {
        ProgressaSession(accessToken: "access", refreshToken: "refresh", userId: "user-1", expiresAt: .distantFuture)
    }

    private static func setRows(ids: [String]) -> Data {
        let values = ids.map { id in
            [
                "id": id, "user_id": "user-1", "workout_id": "w\(id)", "exercise_id": "bench",
                "weight_kg": 80, "reps": 8, "created_at": "2026-06-18T18:00:00Z",
                "exercises": ["id": "bench", "name": "Bench Press", "weight_type": "standard"],
                "workouts": ["id": "w\(id)", "title": "Push", "created_at": "2026-06-18T17:00:00Z"],
            ] as [String: Any]
        }
        return try! JSONSerialization.data(withJSONObject: values)
    }

    private static let measurementJSON = #"[{"id":"m1","user_id":"user-1","measured_at":"2026-06-18T18:00:00Z","type":"WEIGHT","value":80,"note":"Progress"}]"#.data(using: .utf8)!

    private static func bodyData(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw try XCTUnwrap(stream.streamError) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class StatsURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let callback = try XCTUnwrap(Self.handler)
            let (status, data) = try callback(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["content-type": "application/json"]
            )!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
