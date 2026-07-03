import Foundation

protocol ProgressaStatsMeasurementsServing {
    func fetchAllSets(session: ProgressaSession) async throws -> [ProgressaSetStat]
    func fetchCardio(session: ProgressaSession) async throws -> [ProgressaCardioSession]
    func fetchMeasurements(session: ProgressaSession) async throws -> [ProgressaMeasurement]
    func addMeasurement(type: ProgressaMeasurementType, value: Double, measuredAt: Date, note: String?, session: ProgressaSession) async throws -> ProgressaMeasurement
    func updateMeasurementNote(id: String, note: String?, session: ProgressaSession) async throws -> ProgressaMeasurement
    func deleteMeasurement(id: String, session: ProgressaSession) async throws
}

final class StatsMeasurementsService: ProgressaStatsMeasurementsServing {
    private let baseURL: URL
    private let anonKey: String
    private let urlSession: URLSession
    private let pageSize: Int

    init(
        bundle: Bundle = .main,
        baseURL: URL = URL(string: "https://supabase-progressa.bryandijkh.com")!,
        anonKey: String? = nil,
        urlSession: URLSession = .shared,
        pageSize: Int = 1_000
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey ?? (bundle.object(forInfoDictionaryKey: "ProgressaSupabaseAnonKey") as? String ?? "")
        self.urlSession = urlSession
        self.pageSize = pageSize
    }

    func fetchAllSets(session: ProgressaSession) async throws -> [ProgressaSetStat] {
        var rows: [ProgressaSetStat] = []
        var offset = 0
        while true {
            let query = [
                URLQueryItem(name: "select", value: "id,user_id,workout_id,exercise_id,weight_kg,reps,rir,side,is_warmup,created_at,exercises:exercise_id(id,name,weight_type),workouts:workout_id(id,title,created_at)"),
                URLQueryItem(name: "user_id", value: "eq.\(session.userId)"),
                URLQueryItem(name: "order", value: "created_at.asc"),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
            do {
                let data = try await send(table: "sets", query: query, session: session)
                guard let page = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    throw ProgressaClientError.invalidResponse
                }
                rows.append(contentsOf: page.compactMap(Self.setStat))
                if page.count < pageSize { break }
                offset += pageSize
            } catch where !rows.isEmpty {
                break
            }
        }
        return rows
    }

    func fetchCardio(session: ProgressaSession) async throws -> [ProgressaCardioSession] {
        let query = [
            URLQueryItem(name: "select", value: "workout_id,activity_type,health_start,health_end,duration_secs,distance_m,calories,avg_heart_rate,max_heart_rate,location,workouts!inner(id,title,created_at,user_id,source)"),
            URLQueryItem(name: "workouts.user_id", value: "eq.\(session.userId)"),
            URLQueryItem(name: "order", value: "workouts(created_at).desc"),
        ]
        let data = try await send(table: "workout_health_metadata", query: query, session: session)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ProgressaClientError.invalidResponse
        }
        var indexed: [String: ProgressaCardioSession] = [:]
        for row in raw {
            guard let workout = row["workouts"] as? [String: Any],
                  let id = (row["workout_id"] ?? workout["id"]) as? String,
                  let date = Self.date(workout["created_at"]) else { continue }
            indexed[id] = ProgressaCardioSession(
                workoutId: id, date: date, activityType: row["activity_type"] as? String ?? "",
                title: workout["title"] as? String ?? "Cardio",
                durationSeconds: (row["duration_secs"] as? NSNumber)?.intValue,
                distanceMeters: (row["distance_m"] as? NSNumber)?.doubleValue,
                calories: (row["calories"] as? NSNumber)?.doubleValue,
                averageHeartRate: (row["avg_heart_rate"] as? NSNumber)?.doubleValue,
                maxHeartRate: (row["max_heart_rate"] as? NSNumber)?.doubleValue,
                location: row["location"] as? String
            )
        }
        return indexed.values.sorted { $0.date > $1.date }
    }

    func fetchMeasurements(session: ProgressaSession) async throws -> [ProgressaMeasurement] {
        let data = try await send(table: "measurements", query: [
            URLQueryItem(name: "select", value: "id,user_id,measured_at,type,value,note"),
            URLQueryItem(name: "user_id", value: "eq.\(session.userId)"),
            URLQueryItem(name: "order", value: "measured_at.desc"),
            URLQueryItem(name: "limit", value: "1000"),
        ], session: session)
        return try decoder.decode([ProgressaMeasurement].self, from: data)
    }

    func addMeasurement(
        type: ProgressaMeasurementType, value: Double, measuredAt: Date, note: String?, session: ProgressaSession
    ) async throws -> ProgressaMeasurement {
        try await mutation(table: "measurements", method: "POST", query: [], body: [
            "user_id": session.userId, "type": type.rawValue, "value": value,
            "measured_at": ISO8601DateFormatter().string(from: measuredAt),
            "note": normalizedNote(note) as Any,
        ], session: session)
    }

    func updateMeasurementNote(id: String, note: String?, session: ProgressaSession) async throws -> ProgressaMeasurement {
        try await mutation(table: "measurements", method: "PATCH", query: [
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "user_id", value: "eq.\(session.userId)"),
        ], body: ["note": normalizedNote(note) as Any], session: session)
    }

    func deleteMeasurement(id: String, session: ProgressaSession) async throws {
        _ = try await send(table: "measurements", query: [
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "user_id", value: "eq.\(session.userId)"),
        ], session: session, method: "DELETE")
    }

    private func mutation(
        table: String, method: String, query: [URLQueryItem], body: [String: Any], session: ProgressaSession
    ) async throws -> ProgressaMeasurement {
        let data = try await send(
            table: table, query: query, session: session, method: method,
            body: try JSONSerialization.data(withJSONObject: body), preferRepresentation: true
        )
        guard let value = try decoder.decode([ProgressaMeasurement].self, from: data).first else {
            throw ProgressaClientError.invalidResponse
        }
        return value
    }

    private func send(
        table: String, query: [URLQueryItem], session: ProgressaSession,
        method: String = "GET", body: Data? = nil, preferRepresentation: Bool = false
    ) async throws -> Data {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        guard let url = components.url else { throw ProgressaClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 12
        request.httpBody = body
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "content-type") }
        if preferRepresentation { request.setValue("return=representation", forHTTPHeaderField: "prefer") }
        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProgressaClientError.invalidResponse }
        guard 200..<300 ~= response.statusCode else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw ProgressaClientError.server(response.statusCode, object?["message"] as? String ?? object?["error"] as? String ?? "Request failed")
        }
        return data
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = Self.date(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
            }
            return date
        }
        return decoder
    }

    private func normalizedNote(_ value: String?) -> Any {
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? NSNull() : clean
    }

    private static func setStat(_ row: [String: Any]) -> ProgressaSetStat? {
        guard let id = row["id"] as? String,
              let workoutId = row["workout_id"] as? String,
              let exerciseId = row["exercise_id"] as? String,
              let createdAt = date(row["created_at"]) else { return nil }
        let exercise = row["exercises"] as? [String: Any]
        let workout = row["workouts"] as? [String: Any]
        return ProgressaSetStat(
            id: id, workoutId: workoutId, exerciseId: exerciseId,
            exerciseName: exercise?["name"] as? String ?? "Exercise",
            weightType: ProgressaWeightType(rawValue: exercise?["weight_type"] as? String ?? "standard") ?? .standard,
            weightKg: (row["weight_kg"] as? NSNumber)?.doubleValue,
            reps: (row["reps"] as? NSNumber)?.intValue, createdAt: createdAt,
            workoutCreatedAt: date(workout?["created_at"])
        )
    }

    private static func date(_ value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}
