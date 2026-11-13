import Foundation
import Security

enum ProgressaClientError: LocalizedError {
    case configuration
    case invalidResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .configuration: return "Progressa is not configured."
        case .invalidResponse: return "The server returned an invalid response."
        case let .server(code, message):
            let normalized = message.lowercased()
            if normalized.contains("invalid login credentials") { return "The email address or password is incorrect." }
            if normalized.contains("email not confirmed") { return "Confirm your email address before signing in." }
            if code == 429 { return "Too many attempts. Wait a moment and try again." }
            return message.isEmpty ? "Progressa could not complete the request (\(code))." : message
        }
    }
}

protocol ProgressaWorkoutServing {
    func fetchWorkouts(session: ProgressaSession) async throws -> [ProgressaWorkout]
    func fetchWorkout(id: String, session: ProgressaSession) async throws -> ProgressaWorkout?
    func createWorkout(title: String, createdAt: Date, session: ProgressaSession) async throws -> ProgressaWorkout
    func updateWorkout(id: String, title: String, createdAt: Date, session: ProgressaSession) async throws -> ProgressaWorkout
    func updateWorkoutTiming(id: String, startedAt: Date, endedAt: Date?, session: ProgressaSession) async throws -> ProgressaWorkout
    func addSequence(workoutId: String, exerciseIDs: [String], rounds: Int, session: ProgressaSession) async throws
    func deleteWorkout(id: String, session: ProgressaSession) async throws
    func fetchExercises(query: String, session: ProgressaSession) async throws -> [ProgressaExerciseLibraryItem]
    func lastWeightForExercise(_ exerciseId: String, session: ProgressaSession) async throws -> Double?
    func previousSetStructure(_ exerciseId: String, session: ProgressaSession) async throws -> [ProgressaSetInput]
    func createCustomExercise(name: String, weightType: ProgressaWeightType, session: ProgressaSession) async throws -> ProgressaExerciseLibraryItem
    func renameCustomExercise(id: String, name: String, session: ProgressaSession) async throws
    func updateCustomExerciseWeightType(id: String, weightType: ProgressaWeightType, session: ProgressaSession) async throws
    func deleteCustomExercise(id: String, session: ProgressaSession) async throws
    func addExercise(_ input: ProgressaExerciseInput, workoutId: String, sortOrder: Int, session: ProgressaSession) async throws -> ProgressaExercise
    func addSet(_ input: ProgressaSetInput, workoutId: String, block: ProgressaExercise, session: ProgressaSession) async throws -> ProgressaWorkoutSet
    func updateSet(_ input: ProgressaSetInput, setId: String, session: ProgressaSession) async throws -> ProgressaWorkoutSet
    func deleteSet(id: String, session: ProgressaSession) async throws
    func deleteExerciseBlock(id: String, workoutId: String, session: ProgressaSession) async throws
    func reorderExerciseBlocks(workoutId: String, orderedBlockIds: [String], session: ProgressaSession) async throws
}

extension ProgressaWorkoutServing {
    func updateWorkoutTiming(id: String, startedAt: Date, endedAt: Date?, session: ProgressaSession) async throws -> ProgressaWorkout { throw ProgressaClientError.configuration }
    func addSequence(workoutId: String, exerciseIDs: [String], rounds: Int, session: ProgressaSession) async throws { throw ProgressaClientError.configuration }

    func fetchExercises(query: String, session: ProgressaSession) async throws -> [ProgressaExerciseLibraryItem] { throw ProgressaClientError.configuration }
    func lastWeightForExercise(_ exerciseId: String, session: ProgressaSession) async throws -> Double? { nil }
    func previousSetStructure(_ exerciseId: String, session: ProgressaSession) async throws -> [ProgressaSetInput] { [] }
    func createCustomExercise(name: String, weightType: ProgressaWeightType, session: ProgressaSession) async throws -> ProgressaExerciseLibraryItem { throw ProgressaClientError.configuration }
    func renameCustomExercise(id: String, name: String, session: ProgressaSession) async throws { throw ProgressaClientError.configuration }
    func updateCustomExerciseWeightType(id: String, weightType: ProgressaWeightType, session: ProgressaSession) async throws { throw ProgressaClientError.configuration }
    func deleteCustomExercise(id: String, session: ProgressaSession) async throws { throw ProgressaClientError.configuration }
    func addExercise(_ input: ProgressaExerciseInput, workoutId: String, sortOrder: Int, session: ProgressaSession) async throws -> ProgressaExercise { throw ProgressaClientError.configuration }
    func addSet(_ input: ProgressaSetInput, workoutId: String, block: ProgressaExercise, session: ProgressaSession) async throws -> ProgressaWorkoutSet { throw ProgressaClientError.configuration }
    func updateSet(_ input: ProgressaSetInput, setId: String, session: ProgressaSession) async throws -> ProgressaWorkoutSet { throw ProgressaClientError.configuration }
    func deleteSet(id: String, session: ProgressaSession) async throws { throw ProgressaClientError.configuration }
    func deleteExerciseBlock(id: String, workoutId: String, session: ProgressaSession) async throws { throw ProgressaClientError.configuration }
    func reorderExerciseBlocks(workoutId: String, orderedBlockIds: [String], session: ProgressaSession) async throws { throw ProgressaClientError.configuration }
}

final class ProgressaClient: ProgressaWorkoutServing {
    private let supabaseURL: URL
    private let connectURL: URL
    private let anonKey: String
    private let urlSession: URLSession

    init(
        bundle: Bundle = .main,
        supabaseURL: URL? = nil,
        connectURL: URL? = nil,
        urlSession: URLSession = .shared,
        anonKey: String? = nil
    ) {
        self.anonKey = anonKey ?? (bundle.object(forInfoDictionaryKey: "ProgressaSupabaseAnonKey") as? String ?? "")
        self.supabaseURL = supabaseURL
            ?? (bundle.object(forInfoDictionaryKey: "ProgressaSupabaseURL") as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://supabase-progressa.bryandijkh.com")!
        self.connectURL = connectURL
            ?? (bundle.object(forInfoDictionaryKey: "ProgressaConnectURL") as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://api.progressa.bryandijkh.com")!
        self.urlSession = urlSession
    }

    func signIn(email: String, password: String) async throws -> ProgressaSession {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: supabaseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        return try await session(from: request)
    }

    func signUp(email: String, password: String) async throws -> ProgressaSession? {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: supabaseURL.appendingPathComponent("auth/v1/signup"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "redirect_to", value: "https://progressa-app.com/auth/callback")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let object = try await json(for: request)
        guard object["access_token"] != nil else { return nil }
        return try session(from: object)
    }

    func requestPasswordReset(email: String) async throws {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: supabaseURL.appendingPathComponent("auth/v1/recover"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "redirect_to", value: "progressa://reset-callback")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
    }

    func recoverySession(accessToken: String, refreshToken: String) async throws -> ProgressaSession {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var request = URLRequest(url: supabaseURL.appendingPathComponent("auth/v1/user"))
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        let user = try await json(for: request)
        guard let userId = user["id"] as? String else { throw ProgressaClientError.invalidResponse }
        return ProgressaSession(
            accessToken: accessToken, refreshToken: refreshToken, userId: userId,
            expiresAt: .now.addingTimeInterval(3_600), email: user["email"] as? String,
            provider: "email"
        )
    }

    func updatePassword(_ password: String, session: ProgressaSession) async throws {
        var request = URLRequest(url: supabaseURL.appendingPathComponent("auth/v1/user"))
        request.httpMethod = "PUT"
        authorize(&request, session: session)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["password": password])
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> ProgressaSession {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: supabaseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": "apple", "id_token": idToken, "nonce": nonce,
        ])
        return try await session(from: request)
    }

    func refresh(_ session: ProgressaSession) async throws -> ProgressaSession {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: supabaseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])
        return try await self.session(from: request)
    }

    func fetchProfile(session: ProgressaSession) async throws -> ProgressaProfile? {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "user_id,full_name,country,birthdate,height_cm,unit_system,sex,profile_visibility,handle,avatar_path"),
            URLQueryItem(name: "user_id", value: "eq.\(session.userId)"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        authorize(&request, session: session)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
        return try profileDecoder.decode([ProgressaProfile].self, from: data).first
    }

    func upsertProfile(_ profile: ProgressaProfile, session: ProgressaSession) async throws -> ProgressaProfile {
        guard !anonKey.isEmpty, profile.userId == session.userId else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        authorize(&request, session: session)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "prefer")
        var body: [String: Any] = ["user_id": profile.userId]
        body["full_name"] = profile.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? NSNull()
        body["country"] = profile.country?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? NSNull()
        body["birthdate"] = profile.birthdate.map(Self.profileDateString) ?? NSNull()
        body["height_cm"] = profile.heightCm.map { $0 as Any } ?? NSNull()
        body["unit_system"] = profile.unitSystem ?? "metric"
        body["sex"] = profile.sex ?? NSNull()
        body["profile_visibility"] = profile.profileVisibility == "private" ? "private" : "public"
        body["handle"] = profile.handle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
        return try profileDecoder.decode([ProgressaProfile].self, from: data).first ?? profile
    }

    func deleteAccount(session: ProgressaSession) async throws {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var request = URLRequest(url: supabaseURL.appendingPathComponent("functions/v1/delete-account"))
        request.httpMethod = "POST"
        authorize(&request, session: session)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
    }

    func createQuantivitaCode(_ requestValue: QuantivitaConnectRequest, session: ProgressaSession) async throws -> String {
        var request = URLRequest(url: connectURL.appendingPathComponent("api/quantivita/mobile-code"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "scope": requestValue.scope, "refreshToken": session.refreshToken,
        ])
        let object = try await json(for: request)
        guard let code = object["code"] as? String, !code.isEmpty else { throw ProgressaClientError.invalidResponse }
        return code
    }

    func fetchWorkouts(session: ProgressaSession) async throws -> [ProgressaWorkout] {
        let headers = try await restRows(
            table: "workouts",
            query: [
                .init(name: "select", value: "id,title,created_at,source,location,start_time,end_time"),
                .init(name: "user_id", value: "eq.\(session.userId)"),
                .init(name: "order", value: "created_at.desc"),
            ], session: session
        )
        guard !headers.isEmpty else { return [] }
        return workoutHeaders(headers)
    }

    func fetchWorkout(id: String, session: ProgressaSession) async throws -> ProgressaWorkout? {
        let headers = try await restRows(
            table: "workouts",
            query: [
                .init(name: "select", value: "id,title,created_at,source,location,start_time,end_time"),
                .init(name: "id", value: "eq.\(id)"),
                .init(name: "user_id", value: "eq.\(session.userId)"),
                .init(name: "limit", value: "1"),
            ], session: session
        )
        return try await workoutSnapshots(headers: headers, session: session).first
    }

    func createWorkout(title: String, createdAt: Date, session: ProgressaSession) async throws -> ProgressaWorkout {
        try await mutateWorkout(method: "POST", id: nil, body: [
            "user_id": session.userId,
            "start_time": ISO8601DateFormatter().string(from: createdAt),
            "title": title,
            "created_at": ISO8601DateFormatter().string(from: createdAt),
        ], session: session)
    }

    func updateWorkout(id: String, title: String, createdAt: Date, session: ProgressaSession) async throws -> ProgressaWorkout {
        try await mutateWorkout(method: "PATCH", id: id, body: [
            "title": title,
            "created_at": ISO8601DateFormatter().string(from: createdAt),
        ], session: session)
    }

    func updateWorkoutTiming(id: String, startedAt: Date, endedAt: Date?, session: ProgressaSession) async throws -> ProgressaWorkout {
        guard endedAt == nil || endedAt! >= startedAt else { throw ProgressaClientError.invalidResponse }
        return try await mutateWorkout(method: "PATCH", id: id, body: [
            "start_time": ISO8601DateFormatter().string(from: startedAt),
            "end_time": endedAt.map { ISO8601DateFormatter().string(from: $0) } as Any,
        ], session: session)
    }

    func addSequence(workoutId: String, exerciseIDs: [String], rounds: Int, session: ProgressaSession) async throws {
        guard (2...12).contains(exerciseIDs.count), (1...20).contains(rounds) else { throw ProgressaClientError.invalidResponse }
        _ = try await restMutation(table: "rpc/add_workout_sequence", method: "POST", query: [], body: [
            "p_workout_id": workoutId, "p_exercise_ids": exerciseIDs, "p_rounds": rounds,
        ], session: session, returnRepresentation: false)
    }

    func deleteWorkout(id: String, session: ProgressaSession) async throws {
        var request = try workoutRESTRequest(method: "DELETE", id: id, session: session)
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
    }

    func fetchExercises(query: String, session: ProgressaSession) async throws -> [ProgressaExerciseLibraryItem] {
        var filters = [
            URLQueryItem(name: "select", value: "id,name,is_builtin,primary_muscle_name,weight_type"),
            URLQueryItem(name: "is_active", value: "eq.true"),
            URLQueryItem(name: "or", value: "(user_id.is.null,user_id.eq.\(session.userId))"),
            URLQueryItem(name: "order", value: "is_builtin.desc,name.asc"),
            URLQueryItem(name: "limit", value: "240"),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { filters.append(.init(name: "name", value: "ilike.*\(trimmed)*")) }
        let rows = try await restRows(table: "exercises_visible_for_me", query: filters, session: session)
        return rows.compactMap { row in
            guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
            return ProgressaExerciseLibraryItem(
                id: id, name: name, muscleGroup: row["primary_muscle_name"] as? String,
                weightType: ProgressaWeightType(rawValue: row["weight_type"] as? String ?? "standard") ?? .standard,
                isBuiltin: row["is_builtin"] as? Bool ?? false
            )
        }
    }

    /// Most recent logged weight for this exercise, mirroring `SetsRepo.lastWeightForExercise`
    /// in the Flutter app: latest `sets` row for this user/exercise, newest first.
    func lastWeightForExercise(_ exerciseId: String, session: ProgressaSession) async throws -> Double? {
        let rows = try await restRows(table: "sets", query: [
            .init(name: "select", value: "weight_kg,added_weight_kg"),
            .init(name: "user_id", value: "eq.\(session.userId)"),
            .init(name: "exercise_id", value: "eq.\(exerciseId)"),
            .init(name: "order", value: "created_at.desc"),
            .init(name: "limit", value: "1"),
        ], session: session)
        return ((rows.first?["added_weight_kg"] ?? rows.first?["weight_kg"]) as? NSNumber)?.doubleValue
    }

    /// Suggest only the latest occurrence, never combine repeated blocks in a workout.
    func previousSetStructure(_ exerciseId: String, session: ProgressaSession) async throws -> [ProgressaSetInput] {
        let latest = try await restRows(table: "sets", query: [
            .init(name: "select", value: "workout_id,exercise_block_id"),
            .init(name: "user_id", value: "eq.\(session.userId)"),
            .init(name: "exercise_id", value: "eq.\(exerciseId)"),
            .init(name: "order", value: "created_at.desc"),
            .init(name: "limit", value: "1"),
        ], session: session)
        guard let workoutId = latest.first?["workout_id"] as? String else { return [] }
        let blockID = latest.first?["exercise_block_id"] as? String
        let rows = try await restRows(table: "sets", query: [
            .init(name: "exercise_block_id", value: blockID.map { "eq.\($0)" } ?? "is.null"),
            .init(name: "select", value: "added_weight_kg,weight_kg,reps,rir,side,is_warmup,created_at"),
            .init(name: "user_id", value: "eq.\(session.userId)"),
            .init(name: "exercise_id", value: "eq.\(exerciseId)"),
            .init(name: "workout_id", value: "eq.\(workoutId)"),
            .init(name: "order", value: "created_at.asc"),
        ], session: session)
        return rows.map { row in
            ProgressaSetInput(
                weightKg: ((row["added_weight_kg"] ?? row["weight_kg"]) as? NSNumber)?.doubleValue, reps: (row["reps"] as? NSNumber)?.intValue,
                rir: (row["rir"] as? NSNumber)?.doubleValue, side: row["side"] as? String,
                isWarmup: (row["is_warmup"] as? Bool) ?? false
            )
        }
    }

    func createCustomExercise(
        name: String, weightType: ProgressaWeightType, session: ProgressaSession
    ) async throws -> ProgressaExerciseLibraryItem {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw ProgressaClientError.invalidResponse }
        let rows = try await restMutation(
            table: "exercises", method: "POST",
            query: [.init(name: "select", value: "id,name,is_builtin,weight_type")],
            body: [[
                "name": cleanName, "user_id": session.userId, "is_builtin": false,
                "is_active": true, "weight_type": weightType.rawValue,
            ]], session: session, returnRepresentation: true
        )
        guard let row = rows.first, let id = row["id"] as? String, let name = row["name"] as? String else {
            throw ProgressaClientError.invalidResponse
        }
        return ProgressaExerciseLibraryItem(
            id: id, name: name, muscleGroup: nil, weightType: weightType, isBuiltin: false
        )
    }

    func renameCustomExercise(id: String, name: String, session: ProgressaSession) async throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ProgressaClientError.invalidResponse }
        _ = try await restMutation(table: "exercises", method: "PATCH", query: [
            .init(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(session.userId)"),
        ], body: ["name": clean], session: session, returnRepresentation: false)
    }

    func updateCustomExerciseWeightType(id: String, weightType: ProgressaWeightType, session: ProgressaSession) async throws {
        _ = try await restMutation(table: "exercises", method: "PATCH", query: [
            .init(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(session.userId)"),
        ], body: ["weight_type": weightType.rawValue], session: session, returnRepresentation: false)
    }

    func deleteCustomExercise(id: String, session: ProgressaSession) async throws {
        _ = try await restMutation(table: "exercises", method: "DELETE", query: [
            .init(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(session.userId)"),
        ], body: nil, session: session, returnRepresentation: false)
    }

    func addExercise(
        _ input: ProgressaExerciseInput, workoutId: String, sortOrder: Int, session: ProgressaSession
        ) async throws -> ProgressaExercise {
        let blockId = UUID().uuidString.lowercased()
        _ = try await restMutation(
            table: "workout_exercise_blocks", method: "POST", query: [], body: [[
                "id": blockId, "workout_id": workoutId, "exercise_id": input.exercise.id, "sort_order": sortOrder,
            ]], session: session, returnRepresentation: true
        )
        do {
            _ = try await restMutation(
                table: "workout_exercise_block_order", method: "POST",
                query: [.init(name: "on_conflict", value: "workout_id,exercise_block_id")],
                body: [["workout_id": workoutId, "exercise_block_id": blockId, "sort_order": sortOrder]],
                session: session, returnRepresentation: false,
                prefer: "resolution=merge-duplicates,return=minimal"
            )
            var result = ProgressaExercise(
                id: blockId, exerciseId: input.exercise.id, name: input.exercise.name,
                muscleGroup: input.exercise.muscleGroup, weightType: input.exercise.weightType,
                sortOrder: sortOrder, sets: []
            )
            for set in input.sets {
                result.sets.append(try await addSet(set, workoutId: workoutId, block: result, session: session))
            }
            return result
        } catch {
            _ = try? await restMutation(
                table: "workout_exercise_blocks", method: "DELETE",
                query: [.init(name: "id", value: "eq.\(blockId)")], body: nil,
                session: session, returnRepresentation: false
            )
            throw error
        }
    }

    func addSet(
        _ input: ProgressaSetInput, workoutId: String, block: ProgressaExercise, session: ProgressaSession
    ) async throws -> ProgressaWorkoutSet {
        let rows = try await restMutation(
            table: "sets", method: "POST", query: [.init(name: "select", value: "id,base_weight_kg,weight_kg,reps,rir,side,is_warmup,created_at")],
            body: [[
                "user_id": session.userId, "workout_id": workoutId, "exercise_id": block.exerciseId,
                "exercise_block_id": block.id, "base_weight_kg": NSNull(), "weight_kg": input.weightKg as Any,
                "reps": input.reps as Any, "rir": input.rir as Any, "side": normalizedSide(input.side) as Any,
                "is_warmup": input.isWarmup,
            ]], session: session, returnRepresentation: true
        )
        guard let row = rows.first, let value = workoutSet(row) else { throw ProgressaClientError.invalidResponse }
        return value
    }

    func updateSet(_ input: ProgressaSetInput, setId: String, session: ProgressaSession) async throws -> ProgressaWorkoutSet {
        let rows = try await restMutation(
            table: "sets", method: "PATCH",
            query: [.init(name: "id", value: "eq.\(setId)"), .init(name: "user_id", value: "eq.\(session.userId)"),
                    .init(name: "select", value: "id,base_weight_kg,weight_kg,reps,rir,side,is_warmup,created_at")],
            body: [
                "weight_kg": input.weightKg as Any, "reps": input.reps as Any, "rir": input.rir as Any,
                "side": normalizedSide(input.side) as Any, "is_warmup": input.isWarmup,
            ], session: session, returnRepresentation: true
        )
        guard let row = rows.first, let value = workoutSet(row) else { throw ProgressaClientError.invalidResponse }
        return value
    }

    func deleteSet(id: String, session: ProgressaSession) async throws {
        _ = try await restMutation(
            table: "sets", method: "DELETE",
            query: [.init(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(session.userId)")],
            body: nil, session: session, returnRepresentation: false
        )
    }

    func deleteExerciseBlock(id: String, workoutId: String, session: ProgressaSession) async throws {
        _ = try await restMutation(
            table: "sets", method: "DELETE",
            query: [.init(name: "exercise_block_id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(session.userId)")],
            body: nil, session: session, returnRepresentation: false
        )
        _ = try await restMutation(
            table: "workout_exercise_block_order", method: "DELETE",
            query: [.init(name: "workout_id", value: "eq.\(workoutId)"), .init(name: "exercise_block_id", value: "eq.\(id)")],
            body: nil, session: session, returnRepresentation: false
        )
        _ = try await restMutation(
            table: "workout_exercise_blocks", method: "DELETE",
            query: [.init(name: "workout_id", value: "eq.\(workoutId)"), .init(name: "id", value: "eq.\(id)")],
            body: nil, session: session, returnRepresentation: false
        )
    }

    func reorderExerciseBlocks(workoutId: String, orderedBlockIds: [String], session: ProgressaSession) async throws {
        guard !orderedBlockIds.isEmpty else { return }
        let orderRows: [[String: Any]] = orderedBlockIds.enumerated().map { index, id in
            ["workout_id": workoutId, "exercise_block_id": id, "sort_order": index]
        }
        _ = try await restMutation(
            table: "workout_exercise_block_order", method: "POST",
            query: [.init(name: "on_conflict", value: "workout_id,exercise_block_id")], body: orderRows,
            session: session, returnRepresentation: false, prefer: "resolution=merge-duplicates,return=minimal"
        )
        for (index, id) in orderedBlockIds.enumerated() {
            _ = try await restMutation(
                table: "workout_exercise_blocks", method: "PATCH",
                query: [.init(name: "id", value: "eq.\(id)"), .init(name: "workout_id", value: "eq.\(workoutId)")],
                body: ["sort_order": index], session: session, returnRepresentation: false
            )
        }
    }

    private func workoutSnapshots(headers: [[String: Any]], session: ProgressaSession) async throws -> [ProgressaWorkout] {
        if headers.count > 100 {
            var snapshots: [ProgressaWorkout] = []
            for start in stride(from: 0, to: headers.count, by: 100) {
                snapshots.append(contentsOf: try await workoutSnapshots(
                    headers: Array(headers[start..<min(start + 100, headers.count)]), session: session
                ))
            }
            return snapshots.sorted { $0.createdAt > $1.createdAt }
        }
        let ids = headers.compactMap { $0["id"] as? String }
        guard !ids.isEmpty else { return [] }
        let filter = "in.(\(ids.joined(separator: ",")))"
        async let blockRows = restRows(
            table: "workout_exercise_blocks",
            query: [
                .init(name: "select", value: "id,workout_id,exercise_id,sort_order,sequence_id,sequence_round,exercises(name,weight_type)"),
                .init(name: "workout_id", value: filter), .init(name: "order", value: "sort_order.asc"),
            ], session: session
        )
        async let setRows = restRows(
            table: "sets",
            query: [
                .init(name: "select", value: "id,workout_id,exercise_id,exercise_block_id,base_weight_kg,weight_kg,reps,rir,side,is_warmup,created_at,exercises(name,weight_type)"),
                .init(name: "workout_id", value: filter), .init(name: "user_id", value: "eq.\(session.userId)"),
                .init(name: "order", value: "created_at.asc"),
            ], session: session
        )
        async let orderRows = restRows(
            table: "workout_exercise_block_order",
            query: [
                .init(name: "select", value: "workout_id,exercise_block_id,sort_order"),
                .init(name: "workout_id", value: filter), .init(name: "order", value: "sort_order.asc"),
            ], session: session
        )
        let (blocks, sets, orders) = try await (blockRows, setRows, orderRows)
        let orderByBlock = Dictionary(uniqueKeysWithValues: orders.compactMap { row -> (String, Int)? in
            guard let block = row["exercise_block_id"] as? String,
                  let order = (row["sort_order"] as? NSNumber)?.intValue else { return nil }
            return (block, order)
        })

        return headers.compactMap { header in
            guard let id = header["id"] as? String,
                  let createdAt = parsedDate(header["created_at"] as? String) else { return nil }
            var exercises = blocks.compactMap { row -> ProgressaExercise? in
                guard row["workout_id"] as? String == id,
                      let blockId = row["id"] as? String,
                      let exerciseId = row["exercise_id"] as? String else { return nil }
                let exercise = row["exercises"] as? [String: Any]
                let blockSets = sets.filter { $0["exercise_block_id"] as? String == blockId }.compactMap(workoutSet)
                var block = ProgressaExercise(
                    id: blockId, exerciseId: exerciseId,
                    name: exercise?["name"] as? String ?? "Exercise",
                    weightType: ProgressaWeightType(rawValue: exercise?["weight_type"] as? String ?? "standard") ?? .standard,
                    sortOrder: orderByBlock[blockId] ?? (row["sort_order"] as? NSNumber)?.intValue ?? 0,
                    sets: blockSets
                )
                block.sequenceID = row["sequence_id"] as? String
                block.sequenceRound = (row["sequence_round"] as? NSNumber)?.intValue
                return block
            }
            let knownBlockIDs = Set(exercises.map(\.id))
            let legacyRows = sets.filter { row in
                guard row["workout_id"] as? String == id else { return false }
                guard let blockID = row["exercise_block_id"] as? String else { return true }
                return !knownBlockIDs.contains(blockID)
            }
            let legacyGroups = Dictionary(grouping: legacyRows) { $0["exercise_id"] as? String ?? "unknown" }
            for (offset, group) in legacyGroups.sorted(by: { $0.key < $1.key }).enumerated() {
                guard let first = group.value.first else { continue }
                let joinedExercise = first["exercises"] as? [String: Any]
                exercises.append(ProgressaExercise(
                    id: "legacy-\(id)-\(group.key)", exerciseId: group.key,
                    name: joinedExercise?["name"] as? String ?? "Exercise",
                    weightType: ProgressaWeightType(
                        rawValue: joinedExercise?["weight_type"] as? String ?? "standard"
                    ) ?? .standard,
                    sortOrder: (exercises.map(\.sortOrder).max() ?? -1) + offset + 1,
                    sets: group.value.compactMap(workoutSet).sorted { $0.createdAt < $1.createdAt }
                ))
            }
            exercises.sort { lhs, rhs in lhs.sortOrder == rhs.sortOrder ? lhs.id < rhs.id : lhs.sortOrder < rhs.sortOrder }
            return ProgressaWorkout(
                id: id, title: header["title"] as? String ?? "Workout", createdAt: createdAt,
                source: header["source"] as? String ?? "manual", location: header["location"] as? String,
                exercises: exercises, startedAt: parsedDate(header["start_time"] as? String),
                endedAt: parsedDate(header["end_time"] as? String)
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private func workoutHeaders(_ headers: [[String: Any]]) -> [ProgressaWorkout] {
        headers.compactMap { header in
            guard let id = header["id"] as? String,
                  let createdAt = parsedDate(header["created_at"] as? String) else { return nil }
            return ProgressaWorkout(
                id: id, title: header["title"] as? String ?? "Workout", createdAt: createdAt,
                source: header["source"] as? String ?? "manual", location: header["location"] as? String,
                exercises: [], startedAt: parsedDate(header["start_time"] as? String),
                endedAt: parsedDate(header["end_time"] as? String)
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func correctLoggedBase(_ kg: Double, workout: String, exercise: ProgressaExercise, keepTotal: Bool, session: ProgressaSession) async throws {
        _ = try await restMutation(table: "rpc/correct_logged_base", method: "POST", query: [],
            body: ["p_base": kg, "p_workout": workout, "p_exercise": exercise.exerciseId,
                   "p_sets": exercise.sets.map(\.id), "p_keep_total": keepTotal],
            session: session, returnRepresentation: false)
    }

    func exerciseBase(_ id: String, session: ProgressaSession) async throws -> Double {
        let rows = try await restRows(table: "exercise_load_preferences", query: [
            .init(name: "exercise_id", value: "eq.\(id)"),
            .init(name: "user_id", value: "eq.\(session.userId)"),
            .init(name: "select", value: "base_weight_kg")
        ], session: session)
        return (rows.first?["base_weight_kg"] as? NSNumber)?.doubleValue ?? 0
    }

    func setExerciseBase(_ kg: Double, id: String, session: ProgressaSession) async throws {
        _ = try await restMutation(table: "exercise_load_preferences", method: "POST",
            query: [.init(name: "on_conflict", value: "user_id,exercise_id")],
            body: ["exercise_id": id, "user_id": session.userId, "base_weight_kg": kg],
            session: session, returnRepresentation: false, prefer: "resolution=merge-duplicates,return=minimal")
    }

    private func restRows(table: String, query: [URLQueryItem], session: ProgressaSession) async throws -> [[String: Any]] {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var all: [[String: Any]] = []
        var offset = 0
        while true {
            var components = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
            components.queryItems = query
            guard let url = components.url else { throw ProgressaClientError.invalidResponse }
            var request = URLRequest(url: url)
            authorize(&request, session: session)
            request.setValue("\(offset)-\(offset + 999)", forHTTPHeaderField: "Range")
            let (data, response) = try await urlSession.data(for: request)
            try validate(response: response, data: data)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw ProgressaClientError.invalidResponse
            }
            all.append(contentsOf: rows)
            if rows.count < 1000 { return all }
            offset += rows.count
        }
    }

    private func restMutation(
        table: String, method: String, query: [URLQueryItem], body: Any?, session: ProgressaSession,
        returnRepresentation: Bool, prefer: String? = nil
    ) async throws -> [[String: Any]] {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        guard let url = components.url else { throw ProgressaClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        authorize(&request, session: session)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(prefer ?? (returnRepresentation ? "return=representation" : "return=minimal"), forHTTPHeaderField: "Prefer")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: replacingOptionals(body)) }
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
        guard returnRepresentation else { return [] }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ProgressaClientError.invalidResponse
        }
        return rows
    }

    private func replacingOptionals(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first else { return NSNull() }
            return replacingOptionals(child.value)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues(replacingOptionals)
        }
        if let array = value as? [Any] { return array.map(replacingOptionals) }
        return value
    }

    private func normalizedSide(_ value: String?) -> Any {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return NSNull() }
        return value
    }

    private func workoutSet(_ row: [String: Any]) -> ProgressaWorkoutSet? {
        guard let id = row["id"] as? String else { return nil }
        return ProgressaWorkoutSet(
            id: id, baseWeightKg: (row["base_weight_kg"] as? NSNumber)?.doubleValue, weightKg: (row["weight_kg"] as? NSNumber)?.doubleValue,
            reps: (row["reps"] as? NSNumber)?.intValue, rir: (row["rir"] as? NSNumber)?.doubleValue,
            side: row["side"] as? String, isWarmup: row["is_warmup"] as? Bool ?? false,
            createdAt: parsedDate(row["created_at"] as? String) ?? .now
        )
    }

    private func parsedDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return Self.isoWithFractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func session(from request: URLRequest) async throws -> ProgressaSession {
        let object = try await json(for: request)
        return try session(from: object)
    }

    private func session(from object: [String: Any]) throws -> ProgressaSession {
        guard let access = object["access_token"] as? String,
              let refresh = object["refresh_token"] as? String,
              let user = object["user"] as? [String: Any],
              let userId = user["id"] as? String else { throw ProgressaClientError.invalidResponse }
        let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let metadata = user["app_metadata"] as? [String: Any]
        let identities = user["identities"] as? [[String: Any]]
        let provider = identities?.first?["provider"] as? String ?? metadata?["provider"] as? String
        return ProgressaSession(
            accessToken: access, refreshToken: refresh, userId: userId,
            expiresAt: .now.addingTimeInterval(expiresIn), email: user["email"] as? String, provider: provider
        )
    }

    private func json(for request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProgressaClientError.invalidResponse }
        return value
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else { throw ProgressaClientError.invalidResponse }
        guard 200..<300 ~= response.statusCode else {
            let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = value?["msg"] as? String
                ?? value?["message"] as? String
                ?? value?["error_description"] as? String
                ?? value?["error"] as? String
                ?? "Request failed"
            throw ProgressaClientError.server(response.statusCode, message)
        }
    }

    private func authorize(_ request: inout URLRequest, session: ProgressaSession) {
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
    }

    private var profileDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(Self.profileDateFormatter)
        return decoder
    }

    private static let profileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func profileDateString(_ date: Date) -> String {
        let values = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }

    private func mutateWorkout(method: String, id: String?, body: [String: Any], session: ProgressaSession) async throws -> ProgressaWorkout {
        var request = try workoutRESTRequest(method: method, id: id, session: session)
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
        guard let row = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first,
              let workoutId = row["id"] as? String,
              let title = row["title"] as? String,
              let createdText = row["created_at"] as? String,
              let createdAt = parsedDate(createdText) else { throw ProgressaClientError.invalidResponse }
        return ProgressaWorkout(
            id: workoutId, title: title, createdAt: createdAt,
            source: row["source"] as? String ?? "manual", location: row["location"] as? String, exercises: [],
            startedAt: parsedDate(row["start_time"] as? String), endedAt: parsedDate(row["end_time"] as? String)
        )
    }

    private func workoutRESTRequest(method: String, id: String?, session: ProgressaSession) throws -> URLRequest {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/workouts"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "select", value: "id,user_id,title,created_at,source,location,start_time,end_time")]
        if let id {
            components.queryItems?.append(URLQueryItem(name: "id", value: "eq.\(id)"))
            components.queryItems?.append(URLQueryItem(name: "user_id", value: "eq.\(session.userId)"))
        }
        guard let url = components.url else { throw ProgressaClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
        return request
    }

    private func group(rows: [[String: Any]]) -> [ProgressaWorkout] {
        var workouts: [String: ProgressaWorkout] = [:]
        for row in rows {
            let workoutObject = row["workouts"] as? [String: Any] ?? [:]
            guard let workoutId = (row["workout_id"] ?? workoutObject["id"]) as? String else { continue }
            let created = ISO8601DateFormatter().date(from: workoutObject["created_at"] as? String ?? "") ?? .now
            var workout = workouts[workoutId] ?? ProgressaWorkout(
                id: workoutId, title: workoutObject["title"] as? String ?? "Workout", createdAt: created,
                source: workoutObject["source"] as? String ?? "manual", location: workoutObject["location"] as? String,
                exercises: []
            )
            guard let exerciseId = row["exercise_id"] as? String else { workouts[workoutId] = workout; continue }
            let object = row["exercises"] as? [String: Any] ?? [:]
            let index = workout.exercises.firstIndex(where: { $0.id == exerciseId })
            var exercise = index.map { workout.exercises[$0] } ?? ProgressaExercise(
                id: exerciseId, name: object["name"] as? String ?? "Exercise",
                muscleGroup: object["default_muscles"] as? String, sets: []
            )
            exercise.sets.append(ProgressaWorkoutSet(
                id: row["id"] as? String ?? UUID().uuidString,
                weightKg: (row["weight_kg"] as? NSNumber)?.doubleValue,
                reps: (row["reps"] as? NSNumber)?.intValue,
                rir: (row["rir"] as? NSNumber)?.doubleValue,
                side: row["side"] as? String,
                isWarmup: row["is_warmup"] as? Bool ?? false
            ))
            if let index { workout.exercises[index] = exercise } else { workout.exercises.append(exercise) }
            workouts[workoutId] = workout
        }
        return workouts.values.sorted { $0.createdAt > $1.createdAt }
    }
}

protocol ProgressaSessionStoring {
    func load() -> ProgressaSession?
    func save(_ session: ProgressaSession) throws
    func clear()
}

final class ProgressaSessionStore: ProgressaSessionStoring {
    private let service = "com.bryandijkh.progressa.session"
    func load() -> ProgressaSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ProgressaSession.self, from: data)
    }
    func save(_ session: ProgressaSession) throws {
        let data = try JSONEncoder().encode(session)
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(base as CFDictionary)
        var value = base
        value[kSecValueData as String] = data
        value[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(value as CFDictionary, nil) == errSecSuccess else { throw ProgressaClientError.invalidResponse }
    }
    func clear() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
    }
}
