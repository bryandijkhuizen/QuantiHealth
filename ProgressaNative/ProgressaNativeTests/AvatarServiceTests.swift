import XCTest
@testable import ProgressaNative

final class AvatarServiceTests: XCTestCase {
    private let session = ProgressaSession(
        accessToken: "access", refreshToken: "refresh", userId: "user-1", expiresAt: .distantFuture
    )

    override func tearDown() {
        AvatarURLProtocol.handler = nil
        super.tearDown()
    }

    func testSignedURLUsesPrivateStoragePathAndMemoryCache() async throws {
        var requests = 0
        AvatarURLProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.path, "/storage/v1/object/sign/avatars/user-1/profile.jpg")
            return (200, #"{"signedURL":"/object/sign/avatars/user-1/profile.jpg?token=signed"}"#.data(using: .utf8)!)
        }
        let service = makeService()

        let first = try await service.signedURL(path: "user-1/profile.jpg", session: session)
        let second = try await service.signedURL(path: "user-1/profile.jpg", session: session)

        XCTAssertEqual(first.absoluteString, "https://supabase.test/storage/v1/object/sign/avatars/user-1/profile.jpg?token=signed")
        XCTAssertEqual(second, first)
        XCTAssertEqual(requests, 1)
    }

    func testAvatarUploadUpdatesProfileAfterStorageSucceeds() async throws {
        var paths: [String] = []
        AvatarURLProtocol.handler = { request in
            paths.append(request.url!.path)
            if request.url?.path == "/rest/v1/profiles" {
                XCTAssertEqual(request.httpMethod, "PATCH")
                return (204, Data())
            }
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "image/jpeg")
            return (200, Data("{}".utf8))
        }

        let path = try await makeService().uploadJPEG(Data(repeating: 1, count: 200), oldPath: nil, session: session)

        XCTAssertTrue(path.hasPrefix("user-1/profile_"))
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths[0].hasPrefix("/storage/v1/object/avatars/user-1/profile_"))
        XCTAssertEqual(paths[1], "/rest/v1/profiles")
    }

    private func makeService() -> ProgressaAvatarService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AvatarURLProtocol.self]
        return ProgressaAvatarService(
            baseURL: URL(string: "https://supabase.test")!, anonKey: "anon",
            urlSession: URLSession(configuration: configuration)
        )
    }
}

private final class AvatarURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["content-type": "application/json"]
            )!, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
