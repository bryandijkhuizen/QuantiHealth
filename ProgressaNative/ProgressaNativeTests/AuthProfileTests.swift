import XCTest
@testable import ProgressaNative

final class AuthProfileTests: XCTestCase {
    private var urlSession: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocol.self]
        urlSession = URLSession(configuration: configuration)
    }

    override func tearDown() {
        ProfileURLProtocol.handler = nil
        urlSession.invalidateAndCancel()
        super.tearDown()
    }

    func testProfileCompletenessMatchesProviderRules() {
        let date = Date(timeIntervalSince1970: 631_152_000)
        XCTAssertTrue(ProgressaProfile(userId: "u", fullName: "Bryan", country: "NL", birthdate: date).isComplete(appleUser: false))
        XCTAssertFalse(ProgressaProfile(userId: "u", fullName: "", country: "NL", birthdate: date).isComplete(appleUser: false))
        XCTAssertTrue(ProgressaProfile(userId: "u", fullName: nil, country: "NL", birthdate: date).isComplete(appleUser: true))
        XCTAssertFalse(ProgressaProfile(userId: "u", fullName: "Bryan", country: nil, birthdate: date).isComplete(appleUser: true))
    }

    func testStoredSessionWithoutNewMetadataStillDecodes() throws {
        let json = #"{"accessToken":"a","refreshToken":"r","userId":"u","expiresAt":0}"#.data(using: .utf8)!
        let session = try JSONDecoder().decode(ProgressaSession.self, from: json)
        XCTAssertNil(session.email)
        XCTAssertNil(session.provider)
    }

    func testFetchProfileUsesAuthenticatedUserFilter() async throws {
        ProfileURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer access")
            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "user_id" })?.value, "eq.user-1")
            return (200, #"[{"user_id":"user-1","full_name":"Bryan","country":"NL","birthdate":"1990-01-01"}]"#.data(using: .utf8)!)
        }
        let profile = try await client.fetchProfile(session: session)
        XCTAssertEqual(profile?.fullName, "Bryan")
        XCTAssertEqual(profile?.country, "NL")
        XCTAssertNotNil(profile?.birthdate)
    }

    func testUpsertNormalizesProfileAndRequestsRepresentation() async throws {
        ProfileURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "prefer"), "resolution=merge-duplicates,return=representation")
            let body = try JSONSerialization.jsonObject(with: try requestBody(request)) as? [String: Any]
            XCTAssertEqual(body?["user_id"] as? String, "user-1")
            XCTAssertEqual(body?["full_name"] as? String, "Bryan")
            XCTAssertEqual(body?["country"] as? String, "NL")
            XCTAssertEqual(body?["birthdate"] as? String, "1990-01-01")
            return (201, #"[{"user_id":"user-1","full_name":"Bryan","country":"NL","birthdate":"1990-01-01"}]"#.data(using: .utf8)!)
        }
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 1990, month: 1, day: 1))!
        let saved = try await client.upsertProfile(
            ProgressaProfile(userId: "user-1", fullName: "  Bryan ", country: "nl", birthdate: date),
            session: session
        )
        XCTAssertEqual(saved.country, "NL")
    }

    func testSignUpUsesConfirmationRedirectAndAcceptsEmailConfirmationFlow() async throws {
        ProfileURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/auth/v1/signup")
            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "redirect_to" })?.value, "https://progressa-app.com/auth/callback")
            let body = try JSONSerialization.jsonObject(with: try requestBody(request)) as? [String: Any]
            XCTAssertEqual(body?["email"] as? String, "person@example.com")
            return (200, #"{"id":"user-1","email":"person@example.com"}"#.data(using: .utf8)!)
        }

        let session = try await client.signUp(email: "person@example.com", password: "password123")

        XCTAssertNil(session)
    }

    func testPasswordResetUsesNativeCallback() async throws {
        ProfileURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/recover")
            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "redirect_to" })?.value, "progressa://reset-callback")
            return (200, Data("{}".utf8))
        }

        try await client.requestPasswordReset(email: "person@example.com")
    }

    func testRecoveryTokenLoadsUserAndPasswordUpdateIsAuthorized() async throws {
        var call = 0
        ProfileURLProtocol.handler = { request in
            call += 1
            XCTAssertEqual(request.url?.path, "/auth/v1/user")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer recovery-access")
            if call == 1 { return (200, #"{"id":"user-1","email":"person@example.com"}"#.data(using: .utf8)!) }
            XCTAssertEqual(request.httpMethod, "PUT")
            let body = try JSONSerialization.jsonObject(with: try requestBody(request)) as? [String: Any]
            XCTAssertEqual(body?["password"] as? String, "new-password")
            return (200, #"{"id":"user-1"}"#.data(using: .utf8)!)
        }

        let recovered = try await client.recoverySession(accessToken: "recovery-access", refreshToken: "recovery-refresh")
        try await client.updatePassword("new-password", session: recovered)

        XCTAssertEqual(recovered.userId, "user-1")
        XCTAssertEqual(call, 2)
    }

    @MainActor
    func testBootstrapRestoresSessionAndRequiresIncompleteProfile() async {
        ProfileURLProtocol.handler = { _ in
            (200, #"[{"user_id":"user-1","full_name":"Bryan","country":null,"birthdate":null}]"#.data(using: .utf8)!)
        }
        let store = InMemorySessionStore(value: session)
        let model = ProgressaModel(client: client, sessions: store)
        await model.bootstrap()
        XCTAssertEqual(model.session?.userId, "user-1")
        XCTAssertEqual(model.profileState, .required)
        XCTAssertNil(model.message)
    }

    @MainActor
    func testQuantivitaConnectRefreshesExpiredSessionBeforeCreatingCode() async throws {
        try await verifyQuantivitaConnection(expired: true)
    }

    @MainActor
    func testQuantivitaConnectRetriesServerRejectedTokenWithRefreshedSession() async throws {
        try await verifyQuantivitaConnection(expired: false)
    }

    @MainActor
    private func verifyQuantivitaConnection(expired: Bool) async throws {
        var paths: [String] = []
        var codeRequests = 0
        ProfileURLProtocol.handler = { request in
            paths.append(request.url!.path)
            if request.url?.path == "/auth/v1/token" {
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
                XCTAssertEqual(body["refresh_token"] as? String, "refresh")
                return (200, Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"user":{"id":"user-1"}}"#.utf8))
            }
            XCTAssertEqual(request.url?.path, "/api/quantivita/mobile-code")
            codeRequests += 1
            if !expired && codeRequests == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer access")
                return (401, Data(#"{"error":"Invalid or expired access token"}"#.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer new-access")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            XCTAssertEqual(body["refreshToken"] as? String, "new-refresh")
            return (200, Data(#"{"code":"connection-code"}"#.utf8))
        }
        let stored = InMemorySessionStore(value: nil)
        var callback: URL?
        let model = ProgressaModel(client: client, sessions: stored, openURL: { callback = $0 })
        model.session = ProgressaSession(accessToken: "access", refreshToken: "refresh", userId: "user-1",
                                        expiresAt: expired ? .distantPast : .distantFuture)
        model.handle(url: connectURL)
        await model.finishQuantivitaConnect(approved: true)
        XCTAssertEqual(paths, expired ? ["/auth/v1/token", "/api/quantivita/mobile-code"]
                       : ["/api/quantivita/mobile-code", "/auth/v1/token", "/api/quantivita/mobile-code"])
        XCTAssertEqual(stored.value?.accessToken, "new-access")
        XCTAssertEqual(stored.value?.refreshToken, "new-refresh")
        let callbackURL = try XCTUnwrap(callback)
        XCTAssertEqual(callbackURL.scheme, "quantivita")
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "code" })?.value, "connection-code")
        XCTAssertEqual(items?.first(where: { $0.name == "state" })?.value, "connection-state")
        XCTAssertNil(model.pendingConnect)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testQuantivitaConnectPreservesRequestWhenRefreshIsRejected() async {
        var requests = 0
        ProfileURLProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.path, "/auth/v1/token")
            return (400, Data(#"{"error":"Invalid refresh token"}"#.utf8))
        }
        let model = ProgressaModel(client: client, sessions: InMemorySessionStore(value: nil),
                                  openURL: { _ in XCTFail("Must not return a connection code") })
        model.session = ProgressaSession(accessToken: "access", refreshToken: "refresh", userId: "user-1", expiresAt: .distantPast)
        model.handle(url: connectURL)
        await model.finishQuantivitaConnect(approved: true)
        XCTAssertEqual(requests, 1)
        XCTAssertNil(model.session)
        XCTAssertNotNil(model.pendingConnect)
        XCTAssertEqual(model.message, "Your session expired. Sign in again.")
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testQuantivitaConnectDoesNotRetryNonAuthenticationFailures() async {
        var requests = 0
        ProfileURLProtocol.handler = { _ in
            requests += 1
            return (503, Data(#"{"error":"Service unavailable"}"#.utf8))
        }
        let model = ProgressaModel(client: client, sessions: InMemorySessionStore(value: session),
                                  openURL: { _ in XCTFail("Must not return a connection code") })
        model.session = session
        model.handle(url: connectURL)
        await model.finishQuantivitaConnect(approved: true)
        XCTAssertEqual(requests, 1)
        XCTAssertNotNil(model.session)
        XCTAssertNotNil(model.pendingConnect)
        XCTAssertEqual(model.message, "Connection failed: Service unavailable")
    }

    private var connectURL: URL {
        URL(string: "progressa://quantivita-connect?redirect_uri=quantivita%3A%2F%2Fquantivita.app%2Fprogressa-auth&state=connection-state&scope=workouts%3Aread")!
    }

    private var session: ProgressaSession {
        ProgressaSession(
            accessToken: "access", refreshToken: "refresh", userId: "user-1",
            expiresAt: .now.addingTimeInterval(3_600), email: "person@example.com", provider: "email"
        )
    }

    private var client: ProgressaClient {
        ProgressaClient(
            supabaseURL: URL(string: "https://supabase.test")!,
            connectURL: URL(string: "https://api.test")!,
            urlSession: urlSession, anonKey: "anon"
        )
    }
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else {
        throw XCTSkip("URLProtocol did not expose the request body on this runtime")
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? ProgressaClientError.invalidResponse }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private final class ProfileURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["content-type": "application/json"]
            )!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private final class InMemorySessionStore: ProgressaSessionStoring {
    var value: ProgressaSession?
    init(value: ProgressaSession?) { self.value = value }
    func load() -> ProgressaSession? { value }
    func save(_ session: ProgressaSession) throws { value = session }
    func clear() { value = nil }
}
