import XCTest

final class LinkedProgressaUITests: XCTestCase {
    func testOnlyLinkedProgressaDetailsAppearInsideHealthActivity() {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestingLinkedProgressa")
        app.launch()

        app.tabBars.buttons["Log"].tap()
        XCTAssertTrue(app.staticTexts["Strength Training"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["PROGRESSA LINKED"].exists)
        XCTAssertFalse(app.staticTexts["Standalone Progressa workout"].exists)
        XCTAssertFalse(app.staticTexts["Bench Press"].exists)

        app.staticTexts["Strength Training"].tap()
        XCTAssertTrue(app.staticTexts["Push day"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Linked Progressa details"].exists)
        XCTAssertTrue(app.staticTexts["Bench Press"].exists)
        XCTAssertTrue(app.staticTexts["80 kg · × 10 · RIR 2"].exists)
    }
}
