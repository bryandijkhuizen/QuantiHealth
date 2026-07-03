import XCTest
@testable import QuantivitaNative

@MainActor
final class StravaErrorTests: XCTestCase {
    func testDuplicateErrorBecomesFriendlyMessageWithActivityName() {
        let raw = "quantivita-1781346038.tcx duplicate of <a href='/activities/18902225605' target='_blank'>Lunch Run</a>"
        XCTAssertEqual(AppModel.friendlyStravaError(raw), "This workout is already on Strava as “Lunch Run”.")
    }

    func testDuplicateWithoutNameFallsBack() {
        XCTAssertEqual(AppModel.friendlyStravaError("This upload is a duplicate"), "This workout is already on Strava.")
    }

    func testNonDuplicateErrorIsStrippedOfMarkup() {
        XCTAssertEqual(
            AppModel.friendlyStravaError("<b>Invalid</b> file"),
            "Strava rejected the workout: Invalid file"
        )
    }

    func testEmptyErrorHasGenericMessage() {
        XCTAssertEqual(AppModel.friendlyStravaError(nil), "Strava could not process the workout.")
    }
}
