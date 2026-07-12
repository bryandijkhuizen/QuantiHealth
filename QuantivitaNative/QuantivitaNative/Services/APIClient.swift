import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The server returned an invalid response."
        case let .server(code, message): return "Server error \(code): \(message)"
        }
    }

    var statusCode: Int? { if case let .server(code, _) = self { return code }; return nil }
}

final class APIClient {
    static let defaultBaseURL = URL(string: "https://api.quantivita.bryandijkh.com")!
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL = APIClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func register(_ account: QuantivitaAccount) async throws {
        _ = try await request(
            path: "/api/accounts/register", method: "POST",
            body: ["accountId": account.accountId, "syncToken": account.syncToken, "appleLinked": account.isAppleLinked]
        ) as EmptyResponse
    }

    func deleteAccount(_ account: QuantivitaAccount) async throws {
        _ = try await request(
            path: "/api/users/\(escaped(account.accountId))", method: "DELETE", token: account.syncToken
        ) as EmptyResponse
    }

    func progressaStatus(account: QuantivitaAccount) async throws -> Bool {
        let response: ProgressaStatusResponse = try await request(
            path: "/api/users/\(escaped(account.accountId))/integrations/progressa", token: account.syncToken
        )
        return response.connected
    }

    func exchangeProgressaCode(_ code: String, account: QuantivitaAccount) async throws {
        _ = try await request(
            path: "/api/users/\(escaped(account.accountId))/integrations/progressa/exchange",
            method: "POST", token: account.syncToken, body: ["code": code]
        ) as EmptyResponse
    }

    func disconnectProgressa(account: QuantivitaAccount) async throws {
        _ = try await request(
            path: "/api/users/\(escaped(account.accountId))/integrations/progressa",
            method: "DELETE", token: account.syncToken
        ) as EmptyResponse
    }

    func stravaStatus(account: QuantivitaAccount) async throws -> StravaStatusResponse {
        try await request(
            path: "/api/users/\(escaped(account.accountId))/integrations/strava", token: account.syncToken
        )
    }

    func stravaAuthorizeURL(account: QuantivitaAccount, state: String) async throws -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/users/\(account.accountId)/integrations/strava/authorize-url"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "state", value: state)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(account.syncToken)", forHTTPHeaderField: "Authorization")
        let response = try decoder.decode(StravaAuthorizeResponse.self, from: try await data(for: request))
        guard let url = URL(string: response.url) else { throw APIError.invalidResponse }
        return url
    }

    func exchangeStravaCode(_ code: String, scopes: [String], account: QuantivitaAccount) async throws {
        _ = try await request(
            path: "/api/users/\(escaped(account.accountId))/integrations/strava/exchange",
            method: "POST", token: account.syncToken, body: ["code": code, "scope": scopes.joined(separator: ",")]
        ) as EmptyResponse
    }

    func disconnectStrava(account: QuantivitaAccount) async throws {
        _ = try await request(
            path: "/api/users/\(escaped(account.accountId))/integrations/strava",
            method: "DELETE", token: account.syncToken
        ) as EmptyResponse
    }

    func uploadToStrava(account: QuantivitaAccount, name: String, externalId: String, tcx: String) async throws -> String? {
        let response: StravaUploadResponse = try await request(
            path: "/api/users/\(escaped(account.accountId))/integrations/strava/upload",
            method: "POST", token: account.syncToken,
            body: ["name": name, "externalId": externalId, "tcx": tcx]
        )
        return response.uploadId
    }

    func stravaUploadStatus(_ uploadId: String, account: QuantivitaAccount) async throws -> StravaUploadStatusResponse {
        try await request(
            path: "/api/users/\(escaped(account.accountId))/integrations/strava/uploads/\(escaped(uploadId))",
            token: account.syncToken
        )
    }

    func fetchProgressaWorkouts(account: QuantivitaAccount, from: Date?, to: Date) async throws -> [Workout] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/users/\(account.accountId)/integrations/progressa/workouts"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            from.map { URLQueryItem(name: "from", value: $0.ISO8601Format()) },
            URLQueryItem(name: "to", value: to.ISO8601Format()),
        ].compactMap { $0 }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(account.syncToken)", forHTTPHeaderField: "Authorization")
        let data = try await data(for: request)
        return try decoder.decode(WorkoutResponse.self, from: data).workouts
    }

    func ingest(account: QuantivitaAccount, summary: HealthSummary, recovery: RecoveryResult, workouts: [Workout]) async throws {
        let date = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let daily: [String: Any] = [
            "date": date, "recoveryScore": recovery.score,
            "sleepScore": recovery.contributors["sleep"].flatMap { $0 } as Any? ?? NSNull(),
            "sleepMinutes": summary.sleepMinutes, "hrvMs": summary.hrvMs,
            "restingHeartBpm": summary.restingHeartBpm,
            "respiratoryRate": summary.respiratoryRate,
            "oxygenSaturation": summary.oxygenSaturation,
            "activeEnergyKcal": summary.activeEnergyKcal,
            "basalEnergyKcal": summary.basalEnergyKcal,
            "dietaryEnergyKcal": summary.dietaryEnergyKcal,
            "dietaryWaterMl": summary.dietaryWaterMl,
            "dietaryCarbohydratesG": summary.dietaryCarbohydratesG,
            "dietaryProteinG": summary.dietaryProteinG,
            "dietaryFatG": summary.dietaryFatG,
            "bodyTemperatureC": summary.bodyTemperatureC,
            "wristTemperatureC": summary.wristTemperatureC,
            "steps": summary.steps,
        ]
        let profile: [String: Any] = [
            "birthYear": summary.birthYear, "birthMonth": summary.birthMonth,
            "birthDay": summary.birthDay, "biologicalSex": summary.biologicalSex,
            "bodyMassKg": summary.bodyMassKg, "heightCm": summary.heightCm,
            "bodyFatPercent": summary.bodyFatPercent,
        ]
        let payload: [String: Any] = [
            "profile": profile, "daily": [daily],
            "workouts": workouts.map(workoutPayload),
        ]
        _ = try await request(
            path: "/api/users/\(escaped(account.accountId))/ingest", method: "POST",
            token: account.syncToken, body: payload
        ) as EmptyResponse
    }

    private func workoutPayload(_ workout: Workout) -> [String: Any] {
        var payload: [String: Any] = [
            "id": workout.id, "source": workout.source,
            "externalWorkoutId": workout.externalWorkoutId as Any,
            "title": workout.title, "startTime": workout.startTime.ISO8601Format(),
            "durationMinutes": workout.effectiveDurationMinutes,
            "energyKcal": workout.effectiveEnergyKcal,
            "totalEnergyKcal": workout.totalEnergyKcal,
            "distanceMeters": workout.distanceMeters,
            "averageHeartRate": workout.averageHeartRate,
            "maxHeartRate": workout.maxHeartRate, "typeCode": workout.typeCode,
            "hasRoute": workout.hasRoute,
        ]
        if let details = workout.progressaDetails,
           let data = try? JSONEncoder().encode(details),
           let object = try? JSONSerialization.jsonObject(with: data) {
            payload["progressaDetails"] = object
        }
        return payload
    }

    private func request<T: Decodable>(
        path: String, method: String = "GET", token: String? = nil,
        body: [String: Any]? = nil
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data = try await data(for: request)
        if T.self == EmptyResponse.self, data.isEmpty { return EmptyResponse() as! T }
        return try decoder.decode(T.self, from: data)
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard 200..<300 ~= response.statusCode else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "Request failed"
            throw APIError.server(response.statusCode, message)
        }
        return data
    }

    private func escaped(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value }
}

private struct EmptyResponse: Codable {}
private struct ProgressaStatusResponse: Codable { let connected: Bool }
struct StravaStatusResponse: Codable {
    let connected: Bool
    let canUpload: Bool
    let needsReauthorization: Bool
    let scopes: [String]?
}
private struct StravaAuthorizeResponse: Codable { let url: String }
private struct StravaUploadResponse: Codable { let uploadId: String? }
struct StravaUploadStatusResponse: Codable { let state: String; let activityId: String?; let error: String? }
private struct WorkoutResponse: Codable { let workouts: [Workout] }
