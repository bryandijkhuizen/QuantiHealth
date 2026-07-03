import XCTest
@testable import QuantivitaNative

@MainActor
final class ProgressaAuthTests: XCTestCase {
    func testValidAppCallbackReturnsCode() throws {
        let url = URL(string: "quantivita://quantivita.app/progressa-auth?state=expected&code=temporary-code")!
        XCTAssertEqual(try ProgressaAuthService.code(from: url, expectedState: "expected"), "temporary-code")
    }

    func testCallbackRejectsMismatchedState() {
        let url = URL(string: "quantivita://quantivita.app/progressa-auth?state=wrong&code=temporary-code")!
        XCTAssertThrowsError(try ProgressaAuthService.code(from: url, expectedState: "expected")) { error in
            guard case ProgressaAuthError.stateMismatch = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testCallbackSurfacesCancellation() {
        let url = URL(string: "quantivita://quantivita.app/progressa-auth?state=expected&error=access_denied")!
        XCTAssertThrowsError(try ProgressaAuthService.code(from: url, expectedState: "expected")) { error in
            guard case ProgressaAuthError.denied = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
}
