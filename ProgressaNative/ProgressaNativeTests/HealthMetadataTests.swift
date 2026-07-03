import CoreLocation
import XCTest
@testable import ProgressaNative

final class HealthMetadataTests: XCTestCase {
    func testRecorderDistanceSumsConsecutiveLegs() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let points = [
            CLLocation(latitude: 52.0000, longitude: 4.0000),
            CLLocation(latitude: 52.0100, longitude: 4.0000), // ~1.11 km north
            CLLocation(latitude: 52.0100, longitude: 4.0000),
        ].enumerated().map {
            CLLocation(
                coordinate: $0.element.coordinate, altitude: 0,
                horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: base.addingTimeInterval(Double($0.offset))
            )
        }
        // Single point => no distance; the ~1.11 km leg should dominate.
        XCTAssertEqual(WorkoutLocationRecorder.distance(of: [points[0]]), 0)
        XCTAssertEqual(WorkoutLocationRecorder.distance(of: points), 1_112, accuracy: 30)
    }

    private let session = ProgressaSession(
        accessToken: "access", refreshToken: "refresh", userId: "user-1", expiresAt: .distantFuture
    )

    override func tearDown() { HealthURLProtocol.handler = nil; super.tearDown() }

    func testLinkPersistsHealthWindowAndNullableMetrics() async throws {
        HealthURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/v1/workout_health_metadata")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONSerialization.jsonObject(with: try healthBody(request)) as? [[String: Any]]
            XCTAssertEqual(body?.first?["workout_id"] as? String, "workout-1")
            XCTAssertTrue(body?.first?["calories"] is NSNull)
            return (201, Self.json([[
                "workout_id": "workout-1", "activity_type": "Running",
                "health_start": "2026-06-19T08:00:00.000Z", "health_end": "2026-06-19T09:00:00.000Z",
                "duration_secs": 3600, "calories": NSNull(), "avg_heart_rate": 140,
                "max_heart_rate": 170, "distance_m": 10000, "location": NSNull(),
            ]]))
        }
        let service = makeService()
        let start = ISO8601DateFormatter().date(from: "2026-06-19T08:00:00Z")!
        let health = ProgressaHealthSession(
            workoutUUID: UUID(), start: start, end: start.addingTimeInterval(3600), activityType: "Running",
            calories: nil, distanceMeters: 10000
        )

        let result = try await service.link(workoutId: "workout-1", health: health, heartRate: (140, 170), session: session)

        XCTAssertEqual(result.distanceMeters, 10000)
        XCTAssertEqual(result.averageHeartRate, 140)
    }

    private func makeService() -> ProgressaHealthMetadataService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthURLProtocol.self]
        return ProgressaHealthMetadataService(
            baseURL: URL(string: "https://supabase.test")!, anonKey: "anon",
            urlSession: URLSession(configuration: configuration)
        )
    }
    private static func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
}

private func healthBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { throw ProgressaClientError.invalidResponse }
    stream.open(); defer { stream.close() }
    var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }; data.append(buffer, count: count)
    }
    return data
}

private final class HealthURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["content-type": "application/json"]
            )!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
