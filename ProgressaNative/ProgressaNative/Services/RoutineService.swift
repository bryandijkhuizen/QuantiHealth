import Foundation

protocol ProgressaRoutineServing {
    func list(session: ProgressaSession) async throws -> [ProgressaRoutine]
    func detail(_ routine: ProgressaRoutine, session: ProgressaSession) async throws -> ProgressaRoutineDetail
    func create(name: String, session: ProgressaSession) async throws -> ProgressaRoutine
    func rename(id: String, name: String, session: ProgressaSession) async throws
    func delete(id: String, session: ProgressaSession) async throws
    func addExercise(routineId: String, exercise: ProgressaExerciseLibraryItem, sortOrder: Int, session: ProgressaSession) async throws -> ProgressaRoutineExercise
    func deleteExercise(id: String, session: ProgressaSession) async throws
    func reorderExercises(_ exercises: [ProgressaRoutineExercise], session: ProgressaSession) async throws
    func addSet(routineId: String, entry: ProgressaRoutineExercise, input: ProgressaSetInput, sortOrder: Int, session: ProgressaSession) async throws -> ProgressaRoutineSet
    func updateSet(id: String, input: ProgressaSetInput, session: ProgressaSession) async throws
    func deleteSet(id: String, session: ProgressaSession) async throws
}

final class ProgressaRoutineService: ProgressaRoutineServing {
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

    func list(session: ProgressaSession) async throws -> [ProgressaRoutine] {
        try await rows("routines", query: [
            .init(name: "select", value: "id,user_id,name,created_at"),
            .init(name: "user_id", value: "eq.\(session.userId)"),
            .init(name: "order", value: "created_at.desc"),
        ], session: session).compactMap(routine)
    }

    func detail(_ routine: ProgressaRoutine, session: ProgressaSession) async throws -> ProgressaRoutineDetail {
        async let exerciseRows = rows("routine_exercise_entries", query: [
            .init(name: "select", value: "id,routine_id,exercise_id,sort_order,exercises(name,weight_type,primary_muscle_name,is_builtin)"),
            .init(name: "routine_id", value: "eq.\(routine.id)"), .init(name: "user_id", value: "eq.\(session.userId)"),
            .init(name: "order", value: "sort_order.asc"),
        ], session: session)
        async let setRows = rows("routine_set_entries", query: [
            .init(name: "select", value: "id,routine_exercise_entry_id,routine_id,exercise_id,reps,weight_kg,rir,side,sort_order"),
            .init(name: "routine_id", value: "eq.\(routine.id)"), .init(name: "user_id", value: "eq.\(session.userId)"),
            .init(name: "order", value: "sort_order.asc"),
        ], session: session)
        return try await ProgressaRoutineDetail(
            routine: routine, exercises: exerciseRows.compactMap(routineExercise), sets: setRows.compactMap(routineSet)
        )
    }

    func create(name: String, session: ProgressaSession) async throws -> ProgressaRoutine {
        let result = try await mutate("routines", method: "POST", body: [["user_id": session.userId, "name": name]], session: session)
        guard let value = result.first.flatMap(routine) else { throw ProgressaClientError.invalidResponse }
        return value
    }

    func rename(id: String, name: String, session: ProgressaSession) async throws {
        _ = try await mutate("routines", method: "PATCH", filters: [.init(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(session.userId)")], body: ["name": name], session: session, returnsRows: false)
    }

    func delete(id: String, session: ProgressaSession) async throws {
        _ = try await mutate("routines", method: "DELETE", filters: [.init(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(session.userId)")], session: session, returnsRows: false)
    }

    func addExercise(routineId: String, exercise: ProgressaExerciseLibraryItem, sortOrder: Int, session: ProgressaSession) async throws -> ProgressaRoutineExercise {
        let result = try await mutate("routine_exercise_entries", method: "POST", body: [[
            "routine_id": routineId, "exercise_id": exercise.id, "sort_order": sortOrder, "user_id": session.userId,
        ]], session: session)
        guard let row = result.first, let id = row["id"] as? String else { throw ProgressaClientError.invalidResponse }
        return ProgressaRoutineExercise(id: id, routineId: routineId, exercise: exercise, sortOrder: sortOrder)
    }

    func deleteExercise(id: String, session: ProgressaSession) async throws {
        _ = try await mutate("routine_exercise_entries", method: "DELETE", filters: [.init(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(session.userId)")], session: session, returnsRows: false)
    }

    func reorderExercises(_ exercises: [ProgressaRoutineExercise], session: ProgressaSession) async throws {
        for (index, exercise) in exercises.enumerated() {
            _ = try await mutate("routine_exercise_entries", method: "PATCH", filters: [.init(name: "id", value: "eq.\(exercise.id)"), .init(name: "user_id", value: "eq.\(session.userId)")], body: ["sort_order": index], session: session, returnsRows: false)
        }
    }

    func addSet(routineId: String, entry: ProgressaRoutineExercise, input: ProgressaSetInput, sortOrder: Int, session: ProgressaSession) async throws -> ProgressaRoutineSet {
        let result = try await mutate("routine_set_entries", method: "POST", body: [[
            "routine_exercise_entry_id": entry.id, "routine_id": routineId, "exercise_id": entry.exercise.id,
            "reps": input.reps as Any, "weight_kg": input.weightKg as Any, "rir": input.rir.map(Int.init) as Any,
            "side": normalizedSide(input.side), "sort_order": sortOrder, "user_id": session.userId,
        ]], session: session)
        guard let value = result.first.flatMap(routineSet) else { throw ProgressaClientError.invalidResponse }
        return value
    }

    func updateSet(id: String, input: ProgressaSetInput, session: ProgressaSession) async throws {
        _ = try await mutate("routine_set_entries", method: "PATCH", filters: [.init(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(session.userId)")], body: [
            "reps": input.reps as Any, "weight_kg": input.weightKg as Any, "rir": input.rir.map(Int.init) as Any,
            "side": normalizedSide(input.side),
        ], session: session, returnsRows: false)
    }

    func deleteSet(id: String, session: ProgressaSession) async throws {
        _ = try await mutate("routine_set_entries", method: "DELETE", filters: [.init(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(session.userId)")], session: session, returnsRows: false)
    }

    private func rows(_ table: String, query: [URLQueryItem], session: ProgressaSession) async throws -> [[String: Any]] {
        try await request(table, method: "GET", query: query, session: session)
    }

    private func mutate(_ table: String, method: String, filters: [URLQueryItem] = [], body: Any? = nil, session: ProgressaSession, returnsRows: Bool = true) async throws -> [[String: Any]] {
        try await request(table, method: method, query: filters, body: body, session: session, returnsRows: returnsRows)
    }

    private func request(_ table: String, method: String, query: [URLQueryItem], body: Any? = nil, session: ProgressaSession, returnsRows: Bool = true) async throws -> [[String: Any]] {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        guard let url = components.url else { throw ProgressaClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(returnsRows ? "return=representation" : "return=minimal", forHTTPHeaderField: "Prefer")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: replacingOptionals(body)) }
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProgressaClientError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw ProgressaClientError.server(http.statusCode, object?["message"] as? String ?? "Routine request failed")
        }
        if !returnsRows || data.isEmpty { return [] }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ProgressaClientError.invalidResponse }
        return result
    }

    private func routine(_ row: [String: Any]) -> ProgressaRoutine? {
        guard let id = row["id"] as? String, let user = row["user_id"] as? String,
              let created = parsedDate(row["created_at"] as? String) else { return nil }
        return ProgressaRoutine(id: id, userId: user, name: row["name"] as? String ?? "Routine", createdAt: created)
    }

    private func routineExercise(_ row: [String: Any]) -> ProgressaRoutineExercise? {
        guard let id = row["id"] as? String, let routine = row["routine_id"] as? String,
              let exerciseID = row["exercise_id"] as? String else { return nil }
        let exercise = row["exercises"] as? [String: Any]
        return ProgressaRoutineExercise(id: id, routineId: routine, exercise: .init(
            id: exerciseID, name: exercise?["name"] as? String ?? "Exercise",
            muscleGroup: exercise?["primary_muscle_name"] as? String,
            weightType: ProgressaWeightType(rawValue: exercise?["weight_type"] as? String ?? "standard") ?? .standard,
            isBuiltin: exercise?["is_builtin"] as? Bool ?? false
        ), sortOrder: (row["sort_order"] as? NSNumber)?.intValue ?? 0)
    }

    private func routineSet(_ row: [String: Any]) -> ProgressaRoutineSet? {
        guard let id = row["id"] as? String, let entry = row["routine_exercise_entry_id"] as? String,
              let routine = row["routine_id"] as? String, let exercise = row["exercise_id"] as? String else { return nil }
        return ProgressaRoutineSet(
            id: id, routineExerciseId: entry, routineId: routine, exerciseId: exercise,
            reps: (row["reps"] as? NSNumber)?.intValue, weightKg: (row["weight_kg"] as? NSNumber)?.doubleValue,
            rir: (row["rir"] as? NSNumber)?.intValue, side: row["side"] as? String,
            sortOrder: (row["sort_order"] as? NSNumber)?.intValue ?? 0
        )
    }

    private func parsedDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func replacingOptionals(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional { return mirror.children.first.map { replacingOptionals($0.value) } ?? NSNull() }
        if let dictionary = value as? [String: Any] { return dictionary.mapValues(replacingOptionals) }
        if let array = value as? [Any] { return array.map(replacingOptionals) }
        return value
    }

    private func normalizedSide(_ side: String?) -> Any {
        guard let side, !side.isEmpty else { return NSNull() }
        return side
    }
}
