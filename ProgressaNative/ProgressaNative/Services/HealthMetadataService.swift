import Foundation

final class ProgressaHealthMetadataService {
    private let baseURL: URL
    private let anonKey: String
    private let urlSession: URLSession

    init(bundle: Bundle = .main, baseURL: URL? = nil, anonKey: String? = nil, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
            ?? (bundle.object(forInfoDictionaryKey: "ProgressaSupabaseURL") as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://supabase-progressa.bryandijkh.com")!
        self.anonKey = anonKey ?? (bundle.object(forInfoDictionaryKey: "ProgressaSupabaseAnonKey") as? String ?? "")
        self.urlSession = urlSession
    }

    func metadata(workoutId: String, session: ProgressaSession) async throws -> ProgressaHealthMetadata? {
        let rows = try await request("workout_health_metadata", query: [
            .init(name: "select", value: "workout_id,activity_type,health_start,health_end,duration_secs,calories,avg_heart_rate,max_heart_rate,distance_m,location"),
            .init(name: "workout_id", value: "eq.\(workoutId)"), .init(name: "limit", value: "1"),
        ], session: session)
        return rows.first.flatMap(metadata)
    }

    func link(workoutId: String, health: ProgressaHealthSession, heartRate: (Double?, Double?), session: ProgressaSession) async throws -> ProgressaHealthMetadata {
        let body: [[String: Any]] = [[
            "workout_id": workoutId, "activity_type": health.activityType,
            "health_start": Self.iso.string(from: health.start), "health_end": Self.iso.string(from: health.end),
            "duration_secs": health.durationSeconds, "calories": health.calories as Any,
            "avg_heart_rate": heartRate.0 as Any, "max_heart_rate": heartRate.1 as Any,
            "distance_m": health.distanceMeters as Any,
        ]]
        let rows = try await request(
            "workout_health_metadata", method: "POST",
            query: [.init(name: "on_conflict", value: "workout_id")], body: body,
            prefer: "resolution=merge-duplicates,return=representation", session: session
        )
        guard let value = rows.first.flatMap(metadata) else { throw ProgressaClientError.invalidResponse }
        return value
    }

    func unlink(workoutId: String, session: ProgressaSession) async throws {
        _ = try await request("workout_health_metadata", method: "DELETE", query: [
            .init(name: "workout_id", value: "eq.\(workoutId)"),
        ], prefer: "return=minimal", session: session, returnsRows: false)
    }

    func importWorkout(health: ProgressaHealthSession, heartRate: (Double?, Double?), session: ProgressaSession) async throws -> ProgressaWorkout {
        let workoutRows = try await request("workouts", method: "POST", body: [[
            "user_id": session.userId, "title": health.activityType,
            "created_at": Self.iso.string(from: health.start), "source": "health_import",
        ]], session: session)
        guard let row = workoutRows.first, let id = row["id"] as? String else { throw ProgressaClientError.invalidResponse }
        do {
            _ = try await link(workoutId: id, health: health, heartRate: heartRate, session: session)
            return ProgressaWorkout(id: id, title: health.activityType, createdAt: health.start, source: "health_import", exercises: [])
        } catch {
            _ = try? await request("workouts", method: "DELETE", query: [.init(name: "id", value: "eq.\(id)")], prefer: "return=minimal", session: session, returnsRows: false)
            throw error
        }
    }

    private func request(
        _ table: String, method: String = "GET", query: [URLQueryItem] = [], body: Any? = nil,
        prefer: String = "return=representation", session: ProgressaSession, returnsRows: Bool = true
    ) async throws -> [[String: Any]] {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!); request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey"); request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type"); request.setValue(prefer, forHTTPHeaderField: "Prefer")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: replacingOptionals(body)) }
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProgressaClientError.invalidResponse }
        guard 200..<300 ~= http.statusCode else { throw ProgressaClientError.server(http.statusCode, "Health metadata request failed") }
        if !returnsRows || data.isEmpty { return [] }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ProgressaClientError.invalidResponse }
        return rows
    }

    private func metadata(_ row: [String: Any]) -> ProgressaHealthMetadata? {
        guard let id = row["workout_id"] as? String, let start = Self.date(row["health_start"]), let end = Self.date(row["health_end"]) else { return nil }
        return ProgressaHealthMetadata(
            workoutId: id, activityType: row["activity_type"] as? String ?? "Workout", start: start, end: end,
            durationSeconds: (row["duration_secs"] as? NSNumber)?.intValue ?? Int(end.timeIntervalSince(start)),
            calories: (row["calories"] as? NSNumber)?.doubleValue, averageHeartRate: (row["avg_heart_rate"] as? NSNumber)?.doubleValue,
            maxHeartRate: (row["max_heart_rate"] as? NSNumber)?.doubleValue, distanceMeters: (row["distance_m"] as? NSNumber)?.doubleValue,
            location: row["location"] as? String
        )
    }

    private func replacingOptionals(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional { return mirror.children.first.map { replacingOptionals($0.value) } ?? NSNull() }
        if let values = value as? [String: Any] { return values.mapValues(replacingOptionals) }
        if let values = value as? [Any] { return values.map(replacingOptionals) }
        return value
    }

    private static let iso: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
    private static func date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        return iso.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
