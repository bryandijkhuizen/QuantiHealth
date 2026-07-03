import XCTest
@testable import ProgressaNative

final class SocialFeedContractTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SocialFeedURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        SocialFeedURLProtocol.handler = nil
        session.invalidateAndCancel()
    }

    func testFeedEnrichesProfileAndCardioSnapshot() async throws {
        SocialFeedURLProtocol.handler = { request in
            switch request.url?.path {
            case "/rest/v1/rpc/list_feed_posts_following":
                return Self.response(#"[{"id":"post-1","author_id":"user-1","type":"workout_share","visibility":"public","created_at":"2026-06-20T07:00:00Z","workout_title":"Morning Run","like_count":2,"comments_count":1}]"#)
            case "/rest/v1/profiles":
                return Self.response(#"[{"user_id":"user-1","full_name":"Bryan","handle":"bryan","avatar_path":"user-1/avatar.jpg","profile_visibility":"public"}]"#)
            case "/rest/v1/post_workout_shares":
                return Self.response(#"[{"post_id":"post-1","workout_id":"workout-1","workout_title":"Morning Run","snapshot":{"activity_type":"Running","duration_secs":1800,"distance_m":5200,"calories":340,"avg_heart_rate":148,"route_points":[{"lat":52.1,"lng":4.3},{"lat":52.2,"lng":4.4}]}}]"#)
            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "nil")")
                return Self.response("[]")
            }
        }
        let client = SocialClient(baseURL: URL(string: "https://social.test")!, urlSession: session, anonKey: "anon")
        let auth = ProgressaSession(accessToken: "access", refreshToken: "refresh", userId: "me", expiresAt: .distantFuture)

        let posts = try await client.fetchFeed(.following, session: auth)

        XCTAssertEqual(posts.first?.authorName, "Bryan")
        XCTAssertEqual(posts.first?.avatarPath, "user-1/avatar.jpg")
        XCTAssertEqual(posts.first?.workoutShare?.activityType, "Running")
        XCTAssertEqual(posts.first?.workoutShare?.distanceMeters, 5_200)
        XCTAssertTrue(posts.first?.workoutShare?.isCardio == true)
        XCTAssertEqual(posts.first?.workoutShare?.routePoints, [
            RouteCoordinate(latitude: 52.1, longitude: 4.3),
            RouteCoordinate(latitude: 52.2, longitude: 4.4),
        ])
    }

    func testProfilePostsDecodeLegacyStrengthSnapshotList() async throws {
        SocialFeedURLProtocol.handler = { request in
            switch request.url?.path {
            case "/rest/v1/rpc/list_posts_for_public_profile":
                return Self.response(#"[{"id":"post-2","author_id":"user-2","type":"workout_share","visibility":"public","created_at":"2026-06-20T07:00:00Z","workout_title":"Push Day"}]"#)
            case "/rest/v1/profiles":
                return Self.response(#"[{"user_id":"user-2","full_name":"Alex","avatar_path":"user-2/avatar.jpg"}]"#)
            case "/rest/v1/post_workout_shares":
                return Self.response(#"[{"post_id":"post-2","workout_id":"workout-2","workout_title":"Push Day","snapshot":[{"exercise_name":"Bench Press","sets":[{"weight_kg":80,"reps":8},{"weight_kg":85,"reps":6}]}]}]"#)
            default: return Self.response("[]")
            }
        }
        let client = SocialClient(baseURL: URL(string: "https://social.test")!, urlSession: session, anonKey: "anon")
        let auth = ProgressaSession(accessToken: "access", refreshToken: "refresh", userId: "me", expiresAt: .distantFuture)

        let posts = try await client.profilePosts("user-2", session: auth)

        XCTAssertEqual(posts.first?.authorName, "Alex")
        XCTAssertEqual(posts.first?.workoutShare?.groups.first?.exerciseName, "Bench Press")
        XCTAssertEqual(posts.first?.workoutShare?.totalSets, 2)
        XCTAssertFalse(posts.first?.workoutShare?.isCardio == true)
    }

    private static func response(_ json: String) -> (Int, Data) { (200, Data(json.utf8)) }
}

private final class SocialFeedURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["content-type": "application/json"]
            )!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
