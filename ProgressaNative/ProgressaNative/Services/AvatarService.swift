import Foundation

actor ProgressaAvatarService {
    static let shared = ProgressaAvatarService()

    private let baseURL: URL
    private let anonKey: String
    private let urlSession: URLSession
    private var signedURLs: [String: URL] = [:]

    init(bundle: Bundle = .main, baseURL: URL? = nil, anonKey: String? = nil, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
            ?? (bundle.object(forInfoDictionaryKey: "ProgressaSupabaseURL") as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://supabase-progressa.bryandijkh.com")!
        self.anonKey = anonKey ?? (bundle.object(forInfoDictionaryKey: "ProgressaSupabaseAnonKey") as? String ?? "")
        self.urlSession = urlSession
    }

    func signedURL(path: String, session: ProgressaSession) async throws -> URL {
        if let cached = signedURLs[path] { return cached }
        var request = try storageRequest("object/sign/avatars/\(encoded(path))", method: "POST", session: session)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": 3600])
        let object = try await json(request)
        guard let value = object["signedURL"] as? String ?? object["signedUrl"] as? String else {
            throw ProgressaClientError.invalidResponse
        }
        let finalValue = value.hasPrefix("http") ? value : "storage/v1/\(value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        guard let url = URL(string: finalValue, relativeTo: baseURL)?.absoluteURL else { throw ProgressaClientError.invalidResponse }
        signedURLs[path] = url
        return url
    }

    func uploadJPEG(_ data: Data, oldPath: String?, session: ProgressaSession) async throws -> String {
        guard !data.isEmpty, data.count <= 5 * 1_024 * 1_024 else {
            throw ProgressaClientError.server(413, "Profile photo must be smaller than 5 MB.")
        }
        let path = "\(session.userId)/profile_\(Int(Date().timeIntervalSince1970 * 1_000)).jpg"
        var upload = try storageRequest("object/avatars/\(encoded(path))", method: "POST", session: session)
        upload.setValue("image/jpeg", forHTTPHeaderField: "content-type")
        upload.setValue("true", forHTTPHeaderField: "x-upsert")
        upload.httpBody = data
        try await perform(upload)
        try await updateProfile(path: path, session: session)
        if let oldPath, oldPath != path { try? await removeObject(oldPath, session: session) }
        if let oldPath { signedURLs[oldPath] = nil }
        return path
    }

    func remove(path: String?, session: ProgressaSession) async throws {
        try await updateProfile(path: nil, session: session)
        if let path, !path.isEmpty {
            try? await removeObject(path, session: session)
            signedURLs[path] = nil
        }
    }

    func clearCache() { signedURLs.removeAll() }

    private func updateProfile(path: String?, session: ProgressaSession) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "user_id", value: "eq.\(session.userId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"; authorize(&request, session: session)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "avatar_path": path.map { $0 as Any } ?? NSNull(),
        ])
        try await perform(request)
    }

    private func removeObject(_ path: String, session: ProgressaSession) async throws {
        var request = try storageRequest("object/avatars", method: "DELETE", session: session)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prefixes": [path]])
        try await perform(request)
    }

    private func storageRequest(_ path: String, method: String, session: ProgressaSession) throws -> URLRequest {
        guard !anonKey.isEmpty, let url = URL(string: "storage/v1/\(path)", relativeTo: baseURL)?.absoluteURL else {
            throw ProgressaClientError.configuration
        }
        var request = URLRequest(url: url); request.httpMethod = method; authorize(&request, session: session)
        if request.value(forHTTPHeaderField: "content-type") == nil { request.setValue("application/json", forHTTPHeaderField: "content-type") }
        return request
    }

    private func encoded(_ path: String) -> String {
        path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
    }

    private func authorize(_ request: inout URLRequest, session: ProgressaSession) {
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
    }

    private func perform(_ request: URLRequest) async throws {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProgressaClientError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw ProgressaClientError.server(http.statusCode, object?["message"] as? String ?? "Avatar request failed")
        }
    }

    private func json(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProgressaClientError.invalidResponse
        }
        return object
    }
}
