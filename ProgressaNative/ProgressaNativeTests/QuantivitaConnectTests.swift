import XCTest
@testable import ProgressaNative

final class QuantivitaConnectTests: XCTestCase {
    func testAcceptsExactQuantivitaConnectLink() throws {
        let url = URL(string: "progressa://quantivita-connect?redirect_uri=quantivita%3A%2F%2Fquantivita.app%2Fprogressa-auth&state=abc&scope=workouts%3Aread")!
        let request = try XCTUnwrap(QuantivitaConnectRequest(url: url))
        XCTAssertEqual(request.state, "abc")
        XCTAssertEqual(request.scope, "workouts:read")
    }

    func testRejectsUntrustedRedirect() {
        let url = URL(string: "progressa://quantivita-connect?redirect_uri=evil%3A%2F%2Fcallback&state=abc")!
        XCTAssertNil(QuantivitaConnectRequest(url: url))
    }
}
