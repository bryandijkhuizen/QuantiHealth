import Foundation

protocol NutritionServing {
    func searchFoods(_ query: String, session: ProgressaSession) async throws -> [FoodItem]
    func fetchSupplements(session: ProgressaSession) async throws -> SupplementSnapshot
    func createSupplement(name: String, session: ProgressaSession) async throws -> Supplement
    func deleteSupplement(id: String, session: ProgressaSession) async throws
    func addIntake(supplementId: String, amountGrams: Double, takenAt: Date, session: ProgressaSession) async throws
    func deleteIntake(id: String, session: ProgressaSession) async throws
    func savePreferences(_ preferences: SupplementPreferences, session: ProgressaSession) async throws
}

final class NutritionClient: NutritionServing {
    private let baseURL: URL
    private let anonKey: String
    private let urlSession: URLSession

    init(
        bundle: Bundle = .main,
        baseURL: URL = URL(string: "https://supabase-progressa.bryandijkh.com")!,
        urlSession: URLSession = .shared
    ) {
        anonKey = bundle.object(forInfoDictionaryKey: "ProgressaSupabaseAnonKey") as? String ?? ""
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func searchFoods(_ query: String, session: ProgressaSession) async throws -> [FoodItem] {
        let clean = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !clean.isEmpty else { return [] }
        let rows = try await rpcRows("search_progressa_foods", body: ["q": clean, "lim": 30], session: session)
        return rows.compactMap { row in
            guard let id = string(row["id"]), let title = string(row["title"]) else { return nil }
            return FoodItem(
                id: id, title: title, brand: string(row["brand"]) ?? "",
                servingGrams: number(row["serving_grams"], fallback: 100),
                macrosPerServing: FoodMacros(
                    calories: number(row["calories"]), protein: number(row["protein"]),
                    carbs: number(row["carbs"]), fat: number(row["fat"])
                )
            )
        }
    }

    func fetchSupplements(session: ProgressaSession) async throws -> SupplementSnapshot {
        async let supplementRows = getRows("supplements", query: [
            .init(name: "select", value: "id,user_id,name,unit_kind,count_unit,per_count_g,mass_input_unit,created_at"),
            .init(name: "user_id", value: "eq.\(session.userId)"), .init(name: "order", value: "created_at.desc"),
        ], session: session)
        async let intakeRows = getRows("supplement_intakes", query: [
            .init(name: "select", value: "id,supplement_id,amount_g,taken_at"),
            .init(name: "user_id", value: "eq.\(session.userId)"), .init(name: "order", value: "taken_at.desc"), .init(name: "limit", value: "1000"),
        ], session: session)
        async let streakRows = getRows("supplement_prefs", query: [
            .init(name: "select", value: "supplement_id,keep_streak"), .init(name: "user_id", value: "eq.\(session.userId)"),
        ], session: session)
        async let reminderRows = getRows("supplement_reminder_prefs", query: [
            .init(name: "select", value: "supplement_id,enabled,frequency,hour,minute,weekday,weekdays_mask"),
            .init(name: "user_id", value: "eq.\(session.userId)"),
        ], session: session)
        let (rawSupplements, rawIntakes, rawStreaks, rawReminders) = try await (supplementRows, intakeRows, streakRows, reminderRows)

        let supplements = rawSupplements.compactMap { row -> Supplement? in
            guard let id = string(row["id"]), let userId = string(row["user_id"]) else { return nil }
            return Supplement(
                id: id, userId: userId, name: string(row["name"]) ?? "Supplement",
                unitKind: string(row["unit_kind"]) == "count" ? .count : .mass,
                countUnit: string(row["count_unit"]) ?? "tablet", perCountGrams: optionalNumber(row["per_count_g"]),
                massInputUnit: string(row["mass_input_unit"]) ?? "g", createdAt: date(row["created_at"]) ?? .now
            )
        }
        var intakes: [String: [SupplementIntake]] = [:]
        for row in rawIntakes {
            guard let id = string(row["id"]), let supplementId = string(row["supplement_id"]) else { continue }
            intakes[supplementId, default: []].append(SupplementIntake(
                id: id, supplementId: supplementId, amountGrams: number(row["amount_g"]), takenAt: date(row["taken_at"]) ?? .now
            ))
        }
        var preferences = Dictionary(uniqueKeysWithValues: supplements.map { ($0.id, SupplementPreferences.defaults(for: $0.id)) })
        for row in rawStreaks {
            guard let id = string(row["supplement_id"]), var value = preferences[id] else { continue }
            value.keepStreak = row["keep_streak"] as? Bool ?? false; preferences[id] = value
        }
        for row in rawReminders {
            guard let id = string(row["supplement_id"]), var value = preferences[id] else { continue }
            value.reminderEnabled = row["enabled"] as? Bool ?? false
            value.frequency = SupplementReminderFrequency(rawValue: string(row["frequency"]) ?? "daily") ?? .daily
            value.hour = integer(row["hour"], fallback: 9); value.minute = integer(row["minute"])
            value.weekday = integer(row["weekday"], fallback: 1); value.weekdaysMask = integer(row["weekdays_mask"])
            preferences[id] = value
        }
        return SupplementSnapshot(supplements: supplements, intakes: intakes, preferences: preferences, savedAt: .now)
    }

    func createSupplement(name: String, session: ProgressaSession) async throws -> Supplement {
        var request = try request(table: "supplements", method: "POST", query: [
            .init(name: "select", value: "id,user_id,name,unit_kind,count_unit,per_count_g,mass_input_unit,created_at"),
        ], session: session)
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": session.userId, "name": name, "unit_kind": "mass", "count_unit": "tablet", "mass_input_unit": "g",
        ])
        let rows = try await rows(for: request)
        guard let row = rows.first, let id = string(row["id"]) else { throw ProgressaClientError.invalidResponse }
        let supplement = Supplement(
            id: id, userId: session.userId, name: string(row["name"]) ?? name, unitKind: .mass,
            countUnit: "tablet", massInputUnit: "g", createdAt: date(row["created_at"]) ?? .now
        )
        try await savePreferences(.defaults(for: id), session: session)
        return supplement
    }

    func deleteSupplement(id: String, session: ProgressaSession) async throws {
        try await perform(try request(table: "supplements", method: "DELETE", query: filters(id: id, userId: session.userId), session: session))
    }

    func addIntake(supplementId: String, amountGrams: Double, takenAt: Date, session: ProgressaSession) async throws {
        var request = try request(table: "supplement_intakes", method: "POST", session: session)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": session.userId, "supplement_id": supplementId, "amount_g": amountGrams,
            "taken_at": ISO8601DateFormatter().string(from: takenAt),
        ])
        try await perform(request)
    }

    func deleteIntake(id: String, session: ProgressaSession) async throws {
        try await perform(try request(table: "supplement_intakes", method: "DELETE", query: filters(id: id, userId: session.userId), session: session))
    }

    func savePreferences(_ preferences: SupplementPreferences, session: ProgressaSession) async throws {
        try await upsert(table: "supplement_prefs", value: [
            "supplement_id": preferences.supplementId, "user_id": session.userId, "keep_streak": preferences.keepStreak,
        ], session: session)
        try await upsert(table: "supplement_reminder_prefs", value: [
            "supplement_id": preferences.supplementId, "user_id": session.userId,
            "enabled": preferences.reminderEnabled, "frequency": preferences.frequency.rawValue,
            "hour": preferences.hour, "minute": preferences.minute, "weekday": preferences.weekday,
            "weekdays_mask": preferences.weekdaysMask,
        ], session: session)
    }

    private func upsert(table: String, value: [String: Any], session: ProgressaSession) async throws {
        var request = try request(table: table, method: "POST", query: [.init(name: "on_conflict", value: "supplement_id")], session: session)
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: value)
        try await perform(request)
    }

    private func rpcRows(_ name: String, body: [String: Any], session: ProgressaSession) async throws -> [[String: Any]] {
        var request = try request(table: "rpc/\(name)", method: "POST", session: session)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await rows(for: request)
    }
    private func getRows(_ table: String, query: [URLQueryItem], session: ProgressaSession) async throws -> [[String: Any]] {
        try await rows(for: request(table: table, method: "GET", query: query, session: session))
    }
    private func rows(for request: URLRequest) async throws -> [[String: Any]] {
        let (data, response) = try await urlSession.data(for: request); try validate(response, data: data)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ProgressaClientError.invalidResponse }
        return value
    }
    private func perform(_ request: URLRequest) async throws {
        let (data, response) = try await urlSession.data(for: request); try validate(response, data: data)
    }
    private func request(table: String, method: String, query: [URLQueryItem] = [], session: ProgressaSession) throws -> URLRequest {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        guard let url = components.url else { throw ProgressaClientError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey"); request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }
    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ProgressaClientError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw ProgressaClientError.server(http.statusCode, string(value?["message"] ?? value?["error"]) ?? "Request failed")
        }
    }
    private func filters(id: String, userId: String) -> [URLQueryItem] {
        [.init(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(userId)")]
    }
    private func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }; let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    private func number(_ value: Any?, fallback: Double = 0) -> Double { (value as? NSNumber)?.doubleValue ?? Double(string(value) ?? "") ?? fallback }
    private func optionalNumber(_ value: Any?) -> Double? { guard !(value is NSNull) else { return nil }; return (value as? NSNumber)?.doubleValue ?? Double(string(value) ?? "") }
    private func integer(_ value: Any?, fallback: Int = 0) -> Int { (value as? NSNumber)?.intValue ?? Int(string(value) ?? "") ?? fallback }
    private func date(_ value: Any?) -> Date? {
        guard let text = string(value) else { return nil }; let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
