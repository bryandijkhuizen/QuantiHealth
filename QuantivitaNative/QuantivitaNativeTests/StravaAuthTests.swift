import XCTest
@testable import QuantivitaNative

@MainActor
final class StravaAuthTests: XCTestCase {
    func testValidCallbackReturnsCode() throws {
        let url = URL(string: "quantivita://quantivita.app/strava-auth?state=expected&code=strava-code")!
        XCTAssertEqual(try StravaAuthService.code(from: url, expectedState: "expected"), "strava-code")
    }

    func testCallbackPreservesGrantedUploadScope() throws {
        let url = URL(string: "quantivita://quantivita.app/strava-auth?state=expected&code=strava-code&scope=read%2Cactivity%3Awrite")!
        let authorization = try StravaAuthService.authorization(from: url, expectedState: "expected")
        XCTAssertEqual(authorization, StravaAuthorization(code: "strava-code", scopes: ["read", "activity:write"]))
    }

    func testCallbackRejectsMismatchedState() {
        let url = URL(string: "quantivita://quantivita.app/strava-auth?state=wrong&code=strava-code")!
        XCTAssertThrowsError(try StravaAuthService.code(from: url, expectedState: "expected")) { error in
            guard case StravaAuthError.stateMismatch = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testCallbackSurfacesDenial() {
        let url = URL(string: "quantivita://quantivita.app/strava-auth?state=expected&error=access_denied")!
        XCTAssertThrowsError(try StravaAuthService.code(from: url, expectedState: "expected")) { error in
            guard case StravaAuthError.denied = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testCallbackRejectsAnotherPath() {
        let url = URL(string: "quantivita://quantivita.app/progressa-auth?state=expected&code=strava-code")!
        XCTAssertThrowsError(try StravaAuthService.code(from: url, expectedState: "expected"))
    }
}
