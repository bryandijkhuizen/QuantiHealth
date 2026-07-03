import Foundation

protocol SocialServing {
    func fetchFeed(_ mode: FeedMode, session: ProgressaSession) async throws -> [SocialPost]
    func createPost(text: String, visibility: String, session: ProgressaSession) async throws
    func updatePost(id: String, text: String, session: ProgressaSession) async throws
    func deletePost(id: String, session: ProgressaSession) async throws
    func searchUsers(_ query: String, session: ProgressaSession) async throws -> [SocialUser]
    func follow(_ userId: String, session: ProgressaSession) async throws -> String
    func unfollow(_ userId: String, session: ProgressaSession) async throws
    func followStatus(_ userId: String, session: ProgressaSession) async throws -> String
    func followers(_ userId: String, session: ProgressaSession) async throws -> [SocialUser]
    func following(_ userId: String, session: ProgressaSession) async throws -> [SocialUser]
    func postLikers(_ postId: String, session: ProgressaSession) async throws -> [SocialUser]
    func profilePosts(_ userId: String, session: ProgressaSession) async throws -> [SocialPost]
    func isPostLiked(_ postId: String, session: ProgressaSession) async throws -> Bool
    func setPostLiked(_ liked: Bool, postId: String, session: ProgressaSession) async throws
    func setCommentLiked(_ liked: Bool, commentId: String, session: ProgressaSession) async throws
    func comments(_ postId: String, session: ProgressaSession) async throws -> [SocialComment]
    func createComment(postId: String, text: String, parentId: String?, session: ProgressaSession) async throws
    func updateComment(id: String, text: String, session: ProgressaSession) async throws
    func deleteComment(id: String, session: ProgressaSession) async throws
}

final class SocialClient: SocialServing {
    private let baseURL: URL
    private let anonKey: String
    private let urlSession: URLSession

    init(
        bundle: Bundle = .main,
        baseURL: URL = URL(string: "https://supabase-progressa.bryandijkh.com")!,
        urlSession: URLSession = .shared,
        anonKey: String? = nil
    ) {
        self.anonKey = anonKey ?? bundle.object(forInfoDictionaryKey: "ProgressaSupabaseAnonKey") as? String ?? ""
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func fetchFeed(_ mode: FeedMode, session: ProgressaSession) async throws -> [SocialPost] {
        let name: String
        var body: [String: Any] = ["p_before": NSNull(), "p_lim": 25]
        switch mode {
        case .following: name = "list_feed_posts_following"
        case .recent: name = "list_feed_posts_recent"
        case .popular: name = "list_feed_posts_popular"; body["p_since_days"] = 7
        }
        return try await enrichedPosts(rows(from: await rpc(name, body: body, session: session)), session: session)
    }

    func createPost(text: String, visibility: String, session: ProgressaSession) async throws {
        var request = try restRequest(table: "posts", method: "POST", session: session)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "author_id": session.userId, "type": "post", "text": text, "visibility": visibility,
        ])
        try await perform(request)
    }

    func updatePost(id: String, text: String, session: ProgressaSession) async throws {
        var request = try restRequest(table: "posts", method: "PATCH", session: session, filters: [
            URLQueryItem(name: "id", value: "eq.\(id)"), URLQueryItem(name: "author_id", value: "eq.\(session.userId)"),
        ])
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        try await perform(request)
    }

    func deletePost(id: String, session: ProgressaSession) async throws {
        if let shareRequest = try? restRequest(table: "post_workout_shares", method: "DELETE", session: session, filters: [
            URLQueryItem(name: "post_id", value: "eq.\(id)"),
        ]) {
            try? await perform(shareRequest)
        }
        try await perform(try restRequest(table: "posts", method: "DELETE", session: session, filters: [
            URLQueryItem(name: "id", value: "eq.\(id)"), URLQueryItem(name: "author_id", value: "eq.\(session.userId)"),
        ]))
    }

    func searchUsers(_ query: String, session: ProgressaSession) async throws -> [SocialUser] {
        let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50))
        let name = trimmed.isEmpty ? "suggest_users" : "search_users"
        let body: [String: Any] = trimmed.isEmpty ? ["lim": 30] : ["q": trimmed, "lim": 30]
        return try rows(from: await rpc(name, body: body, session: session)).compactMap { row in
            guard let id = string(row["user_id"]), id != session.userId else { return nil }
            return SocialUser(
                userId: id, fullName: string(row["full_name"]) ?? "Unknown",
                handle: normalizedHandle(row), country: string(row["country"]), avatarPath: string(row["avatar_path"]),
                profileVisibility: string(row["profile_visibility"]) ?? "public"
            )
        }
    }

    func follow(_ userId: String, session: ProgressaSession) async throws -> String {
        status(from: try await rpc("request_follow", body: ["p_target": userId], session: session), fallback: "accepted")
    }

    func unfollow(_ userId: String, session: ProgressaSession) async throws {
        _ = try await rpc("unfollow", body: ["p_target": userId], session: session)
    }

    func followStatus(_ userId: String, session: ProgressaSession) async throws -> String {
        status(from: try await rpc("get_follow_status", body: ["p_target": userId], session: session), fallback: "none")
    }

    func followers(_ userId: String, session: ProgressaSession) async throws -> [SocialUser] {
        try rows(from: await rpc("list_followers", body: ["uid": userId, "lim": 200], session: session)).compactMap(socialUser)
    }

    func following(_ userId: String, session: ProgressaSession) async throws -> [SocialUser] {
        try rows(from: await rpc("list_following", body: ["uid": userId, "lim": 200], session: session)).compactMap(socialUser)
    }

    func postLikers(_ postId: String, session: ProgressaSession) async throws -> [SocialUser] {
        try rows(from: await rpc("list_post_likers", body: ["p_post_id": postId, "p_lim": 100], session: session)).compactMap(socialUser)
    }

    private func socialUser(_ row: [String: Any]) -> SocialUser? {
        guard let id = string(row["user_id"]) else { return nil }
        return SocialUser(
            userId: id, fullName: string(row["full_name"]) ?? "Unknown",
            handle: normalizedHandle(row), country: string(row["country"]),
            avatarPath: string(row["avatar_path"]), profileVisibility: string(row["profile_visibility"]) ?? "public"
        )
    }

    func profilePosts(_ userId: String, session: ProgressaSession) async throws -> [SocialPost] {
        let own = userId == session.userId
        let body: [String: Any] = own ? ["p_uid": userId, "p_lim": 30] : ["p_profile_uid": userId, "p_lim": 30]
        let rows = try rows(from: await rpc(own ? "list_posts_for_profile" : "list_posts_for_public_profile", body: body, session: session))
        return try await enrichedPosts(rows, session: session)
    }

    func isPostLiked(_ postId: String, session: ProgressaSession) async throws -> Bool {
        var request = try restRequest(table: "post_likes", method: "GET", session: session, filters: [
            .init(name: "select", value: "post_id"), .init(name: "post_id", value: "eq.\(postId)"),
            .init(name: "user_id", value: "eq.\(session.userId)"), .init(name: "limit", value: "1"),
        ])
        request.setValue("application/json", forHTTPHeaderField: "accept")
        let (data, response) = try await urlSession.data(for: request); try validate(response, data: data)
        return ((try JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.isEmpty == false)
    }

    func setPostLiked(_ liked: Bool, postId: String, session: ProgressaSession) async throws {
        if liked {
            var request = try restRequest(table: "post_likes", method: "POST", session: session)
            request.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["post_id": postId, "user_id": session.userId])
            try await perform(request)
        } else {
            try await perform(try restRequest(table: "post_likes", method: "DELETE", session: session, filters: [
                .init(name: "post_id", value: "eq.\(postId)"), .init(name: "user_id", value: "eq.\(session.userId)"),
            ]))
        }
    }

    func setCommentLiked(_ liked: Bool, commentId: String, session: ProgressaSession) async throws {
        if liked {
            var request = try restRequest(table: "post_comment_likes", method: "POST", session: session)
            request.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["comment_id": commentId, "user_id": session.userId])
            try await perform(request)
        } else {
            try await perform(try restRequest(table: "post_comment_likes", method: "DELETE", session: session, filters: [
                .init(name: "comment_id", value: "eq.\(commentId)"), .init(name: "user_id", value: "eq.\(session.userId)"),
            ]))
        }
    }

    func comments(_ postId: String, session: ProgressaSession) async throws -> [SocialComment] {
        let request = try restRequest(table: "post_comments", method: "GET", session: session, filters: [
            .init(name: "select", value: "id,post_id,user_id,parent_comment_id,text,created_at,edited_at,profiles:profiles!post_comments_user_id_fkey(full_name,handle,avatar_path),likes_count:post_comment_likes(count),i_liked:post_comment_likes!left(user_id)"),
            .init(name: "post_id", value: "eq.\(postId)"), .init(name: "order", value: "created_at.asc"), .init(name: "limit", value: "300"),
        ])
        let (data, response) = try await urlSession.data(for: request); try validate(response, data: data)
        guard let values = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ProgressaClientError.invalidResponse }
        return values.compactMap { row in
            guard let id = string(row["id"]), let user = string(row["user_id"]), let text = string(row["text"]),
                  let created = date(row["created_at"]) else { return nil }
            let profile = row["profiles"] as? [String: Any]
            let countRows = row["likes_count"] as? [[String: Any]]
            let likedRows = row["i_liked"] as? [[String: Any]]
            return SocialComment(
                id: id, postId: postId, userId: user, parentId: string(row["parent_comment_id"]), text: text,
                createdAt: created, editedAt: date(row["edited_at"]), authorName: string(profile?["full_name"]) ?? "User",
                authorHandle: string(profile?["handle"]), avatarPath: string(profile?["avatar_path"]),
                likeCount: integer(countRows?.first?["count"]),
                isLiked: likedRows?.contains(where: { string($0["user_id"]) == session.userId }) == true
            )
        }
    }

    func createComment(postId: String, text: String, parentId: String?, session: ProgressaSession) async throws {
        var request = try restRequest(table: "post_comments", method: "POST", session: session)
        var body: [String: Any] = ["post_id": postId, "user_id": session.userId, "text": text]
        if let parentId { body["parent_comment_id"] = parentId }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await perform(request)
    }

    func updateComment(id: String, text: String, session: ProgressaSession) async throws {
        var request = try restRequest(table: "post_comments", method: "PATCH", session: session, filters: [
            .init(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(session.userId)"),
        ])
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text, "edited_at": ISO8601DateFormatter().string(from: .now),
        ])
        try await perform(request)
    }

    func deleteComment(id: String, session: ProgressaSession) async throws {
        try await perform(try restRequest(table: "post_comments", method: "DELETE", session: session, filters: [
            .init(name: "id", value: "eq.\(id)"),
        ]))
    }

    private func rpc(_ name: String, body: [String: Any], session: ProgressaSession) async throws -> Any {
        var request = try restRequest(table: "rpc/\(name)", method: "POST", session: session)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response, data: data)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func restRequest(table: String, method: String, session: ProgressaSession, filters: [URLQueryItem] = []) throws -> URLRequest {
        guard !anonKey.isEmpty else { throw ProgressaClientError.configuration }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = filters
        guard let url = components.url else { throw ProgressaClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }

    private func perform(_ request: URLRequest) async throws {
        let (data, response) = try await urlSession.data(for: request)
        try validate(response, data: data)
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ProgressaClientError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw ProgressaClientError.server(http.statusCode, string(object?["message"] ?? object?["error"]) ?? "Request failed")
        }
    }

    private func rows(from value: Any) throws -> [[String: Any]] {
        guard let rows = value as? [[String: Any]] else { throw ProgressaClientError.invalidResponse }
        return rows
    }

    private func enrichedPosts(_ rows: [[String: Any]], session: ProgressaSession) async throws -> [SocialPost] {
        var posts = rows.map(post)
        let authorIDs = Set(posts.map(\.authorId).filter { !$0.isEmpty })
        if !authorIDs.isEmpty {
            let profiles = try await restRows(table: "profiles", filters: [
                .init(name: "select", value: "user_id,full_name,handle,avatar_path,profile_visibility"),
                .init(name: "user_id", value: "in.(\(authorIDs.joined(separator: ",")))"),
            ], session: session)
            let byID = Dictionary(uniqueKeysWithValues: profiles.compactMap { row -> (String, [String: Any])? in
                guard let id = string(row["user_id"]) else { return nil }; return (id, row)
            })
            for index in posts.indices {
                guard let profile = byID[posts[index].authorId] else { continue }
                posts[index].authorName = string(profile["full_name"]) ?? posts[index].authorName
                posts[index].authorHandle = string(profile["handle"]) ?? posts[index].authorHandle
                posts[index].avatarPath = string(profile["avatar_path"]) ?? posts[index].avatarPath
            }
        }

        let workoutPostIDs = posts.filter { $0.type == "workout_share" }.map(\.id)
        if !workoutPostIDs.isEmpty {
            let shares = try await restRows(table: "post_workout_shares", filters: [
                .init(name: "select", value: "post_id,workout_id,workout_title,snapshot"),
                .init(name: "post_id", value: "in.(\(workoutPostIDs.joined(separator: ",")))"),
            ], session: session)
            let byPost = Dictionary(uniqueKeysWithValues: shares.compactMap { row -> (String, [String: Any])? in
                guard let id = string(row["post_id"]) else { return nil }; return (id, row)
            })
            for index in posts.indices {
                guard let share = byPost[posts[index].id] else { continue }
                let title = string(share["workout_title"]) ?? posts[index].workoutTitle ?? "Workout"
                posts[index].workoutTitle = title
                posts[index].workoutShare = workoutSnapshot(
                    share["snapshot"], workoutId: string(share["workout_id"]) ?? "", title: title
                )
            }
        }
        return posts
    }

    private func restRows(table: String, filters: [URLQueryItem], session: ProgressaSession) async throws -> [[String: Any]] {
        let request = try restRequest(table: table, method: "GET", session: session, filters: filters)
        let (data, response) = try await urlSession.data(for: request); try validate(response, data: data)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ProgressaClientError.invalidResponse }
        return result
    }

    private func post(_ row: [String: Any]) -> SocialPost {
        let created = date(row["effective_created_at"] ?? row["created_at"]) ?? .distantPast
        let title = string(row["workout_title"] ?? row["workoutTitle"])
        return SocialPost(
            id: string(row["id"]) ?? UUID().uuidString, authorId: string(row["author_id"]) ?? "",
            text: string(row["text"]), visibility: string(row["visibility"]) ?? "public", createdAt: created,
            authorName: string(row["author_name"] ?? row["author_full_name"] ?? row["full_name"]) ?? "User",
            authorHandle: string(row["author_handle"] ?? row["handle"]), avatarPath: string(row["author_avatar_path"] ?? row["avatar_path"]),
            type: string(row["type"]) ?? "post", workoutTitle: title,
            workoutShare: workoutSnapshot(
                row["workout_snapshot"] ?? row["workoutSnapshot"] ?? row["snapshot"],
                workoutId: string(row["workout_id"] ?? row["workoutId"]) ?? "", title: title ?? "Workout"
            ),
            likeCount: integer(row["like_count"] ?? row["likes_count"]), commentsCount: integer(row["comments_count"])
        )
    }

    private func workoutSnapshot(_ value: Any?, workoutId: String, title: String) -> WorkoutShareSnapshot? {
        guard let decoded = deepJSON(value) else { return nil }
        let object = decoded as? [String: Any]
        let rawGroups = decoded as? [Any] ?? object?["groups"] as? [Any] ?? object?["Groups"] as? [Any] ?? []
        let groups = rawGroups.compactMap { raw -> WorkoutShareGroup? in
            guard let group = raw as? [String: Any] else { return nil }
            let name = string(group["exercise_name"] ?? group["exerciseName"]) ?? "Exercise"
            let id = string(group["exercise_block_id"] ?? group["exerciseBlockId"]) ?? "\(name)-\(UUID().uuidString)"
            let sets = (group["sets"] as? [[String: Any]] ?? []).map {
                WorkoutShareSet(weightKg: number($0["weight_kg"] ?? $0["weightKg"]), reps: integerOptional($0["reps"]))
            }
            return WorkoutShareGroup(id: id, exerciseName: name, sets: sets)
        }
        return WorkoutShareSnapshot(
            workoutId: string(object?["workout_id"] ?? object?["workoutId"]) ?? workoutId,
            workoutTitle: string(object?["workout_title"] ?? object?["workoutTitle"]) ?? title,
            workoutCreatedAt: date(object?["workout_created_at"] ?? object?["workoutCreatedAt"]), groups: groups,
            activityType: string(object?["activity_type"] ?? object?["activityType"]),
            durationSeconds: number(object?["duration_secs"] ?? object?["durationSeconds"]),
            calories: number(object?["calories"]),
            averageHeartRate: number(object?["avg_heart_rate"] ?? object?["avgHeartRate"]),
            maxHeartRate: number(object?["max_heart_rate"] ?? object?["maxHeartRate"]),
            location: string(object?["location"]), distanceMeters: number(object?["distance_m"] ?? object?["distanceM"]),
            routePoints: routePoints(object?["route_points"] ?? object?["routePoints"])
        )
    }

    /// Route is stored in the snapshot as `[{lat, lng}, ...]`; only a real track (>1 point) is kept.
    private func routePoints(_ value: Any?) -> [RouteCoordinate] {
        guard let rows = value as? [Any] else { return [] }
        let points = rows.compactMap { raw -> RouteCoordinate? in
            guard let point = raw as? [String: Any],
                  let latitude = number(point["lat"] ?? point["latitude"]),
                  let longitude = number(point["lng"] ?? point["longitude"]) else { return nil }
            return RouteCoordinate(latitude: latitude, longitude: longitude)
        }
        return points.count > 1 ? points : []
    }

    private func deepJSON(_ value: Any?) -> Any? {
        guard let value, !(value is NSNull) else { return nil }
        guard let text = value as? String else { return value }
        guard let data = text.data(using: .utf8), let decoded = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return decoded is String ? deepJSON(decoded) : decoded
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return string(value).flatMap(Double.init)
    }

    private func integerOptional(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return string(value).flatMap(Int.init)
    }

    private func status(from value: Any, fallback: String) -> String {
        let object = (value as? [[String: Any]])?.first ?? value as? [String: Any]
        return string(object?["status"])?.lowercased() ?? fallback
    }

    private func normalizedHandle(_ row: [String: Any]) -> String? {
        for key in ["handle", "username", "user_handle", "profile_handle"] {
            if let value = string(row[key]) { return value.hasPrefix("@") ? String(value.dropFirst()) : value }
        }
        return nil
    }

    private func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func integer(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? Int(string(value) ?? "") ?? 0 }

    private func date(_ value: Any?) -> Date? {
        guard let value = string(value) else { return nil }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
