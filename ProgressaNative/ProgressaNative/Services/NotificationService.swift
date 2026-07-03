import Foundation

protocol ProgressaNotificationServing {
    func list(session: ProgressaSession) async throws -> [ProgressaNotification]
    func markRead(id: String, session: ProgressaSession) async throws
    func respond(notification: ProgressaNotification, accept: Bool, session: ProgressaSession) async throws
    func preferences(session: ProgressaSession) async throws -> ProgressaNotificationPreferences
    func save(_ value: ProgressaNotificationPreferences, session: ProgressaSession) async throws
}

final class ProgressaNotificationService: ProgressaNotificationServing {
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

    func list(session: ProgressaSession) async throws -> [ProgressaNotification] {
        let notifications = try await rows("notifications", query: [
            .init(name: "select", value: "id,actor_id,type,post_id,comment_id,payload,created_at,read_at,handled_at"),
            .init(name: "user_id", value: "eq.\(session.userId)"),
            .init(name: "or", value: "type.neq.follow_request,and(type.eq.follow_request,handled_at.is.null)"),
            .init(name: "order", value: "created_at.desc"), .init(name: "limit", value: "80"),
        ], session: session)
        let actorIDs = Set(notifications.compactMap { $0["actor_id"] as? String })
        let profiles = actorIDs.isEmpty ? [] : try await rows("profiles", query: [
            .init(name: "select", value: "user_id,full_name,handle,avatar_path"),
            .init(name: "user_id", value: "in.(\(actorIDs.joined(separator: ",")))"),
        ], session: session)
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.compactMap { row -> (String, [String: Any])? in
            guard let id = row["user_id"] as? String else { return nil }; return (id, row)
        })
        return notifications.compactMap { row in
            guard let id = row["id"] as? String, let type = row["type"] as? String,
                  let created = Self.date(row["created_at"]) else { return nil }
            let actorID = row["actor_id"] as? String, profile = actorID.flatMap { profilesByID[$0] }
            let payload = row["payload"] as? [String: Any]
            return ProgressaNotification(
                id: id, actorId: actorID, type: type, postId: row["post_id"] as? String,
                commentId: row["comment_id"] as? String, message: Self.message(type: type, payload: payload),
                createdAt: created, readAt: Self.date(row["read_at"]),
                actorName: profile?["full_name"] as? String ?? "User",
                actorHandle: profile?["handle"] as? String, actorAvatarPath: profile?["avatar_path"] as? String
            )
        }
    }

    func markRead(id: String, session: ProgressaSession) async throws {
        _ = try await request("notifications", method: "PATCH", query: [.init(name: "id", value: "eq.\(id)")],
                              body: ["read_at": ISO8601DateFormatter().string(from: .now)], session: session, returnsRows: false)
    }

    func respond(notification: ProgressaNotification, accept: Bool, session: ProgressaSession) async throws {
        guard let actor = notification.actorId else { throw ProgressaClientError.invalidResponse }
        _ = try await request("rpc/respond_follow_request", method: "POST", body: [
            "p_follower": actor, "p_action": accept ? "accept" : "reject",
        ], session: session)
        _ = try await request("notifications", method: "PATCH", query: [.init(name: "id", value: "eq.\(notification.id)")], body: [
            "handled_at": ISO8601DateFormatter().string(from: .now), "handled_action": accept ? "accepted" : "declined",
        ], session: session, returnsRows: false)
    }

    func preferences(session: ProgressaSession) async throws -> ProgressaNotificationPreferences {
        let result = try await rows("notification_prefs", query: [
            .init(name: "select", value: "push_new_followers,push_likes,push_comments"),
            .init(name: "user_id", value: "eq.\(session.userId)"), .init(name: "limit", value: "1"),
        ], session: session).first
        guard let result else { return .init() }
        return .init(
            newFollowers: result["push_new_followers"] as? Bool ?? true,
            likes: result["push_likes"] as? Bool ?? true,
            comments: result["push_comments"] as? Bool ?? true
        )
    }

    func save(_ value: ProgressaNotificationPreferences, session: ProgressaSession) async throws {
        _ = try await request("notification_prefs", method: "POST", query: [.init(name: "on_conflict", value: "user_id")], body: [[
            "user_id": session.userId, "push_new_followers": value.newFollowers,
            "push_likes": value.likes, "push_comments": value.comments,
        ]], prefer: "resolution=merge-duplicates,return=minimal", session: session, returnsRows: false)
    }

    private func rows(_ table: String, query: [URLQueryItem], session: ProgressaSession) async throws -> [[String: Any]] {
        try await request(table, query: query, session: session)
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
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw ProgressaClientError.invalidResponse }
        if !returnsRows || data.isEmpty { return [] }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ProgressaClientError.invalidResponse }
        return rows
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    private static func message(type: String, payload: [String: Any]?) -> String {
        let preview = payload?["text_preview"] as? String
        switch type {
        case "follow_request": return "wants to follow you"
        case "follow_accepted": return "started following you"
        case "post_like": return "liked your post"
        case "post_comment": return preview?.isEmpty == false ? preview! : "commented on your post"
        case "comment_reply": return preview?.isEmpty == false ? preview! : "replied to your comment"
        default: return payload?["message"] as? String ?? "New notification"
        }
    }
}
