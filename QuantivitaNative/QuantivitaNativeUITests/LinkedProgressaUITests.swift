import XCTest

final class LinkedProgressaUITests: XCTestCase {
    func testCyclingDetailsAndCombineSelection() {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestingCycling")
        app.launch()
        app.tabBars.buttons["Log"].tap()
        XCTAssertTrue(app.staticTexts["Indoor Cycling · Part 1"].waitForExistence(timeout: 5))
        app.staticTexts["Indoor Cycling · Part 1"].tap()
        XCTAssertTrue(app.staticTexts["Average power, 185 W"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Average heart rate, 0 bpm"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Unavailable")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Normalized power")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "8[.,]00 km")).firstMatch.exists)
        let details = XCTAttachment(screenshot: app.screenshot())
        details.name = "Cycling measurements"; details.lifetime = .keepAlways; add(details)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Combine"].tap()
        XCTAssertTrue(app.staticTexts["Combine activities"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Indoor Cycling · Part 1")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Indoor Cycling · Part 2")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Preview combination"].isEnabled)
        let selection = XCTAttachment(screenshot: app.screenshot())
        selection.name = "Combine selection"; selection.lifetime = .keepAlways; add(selection)
    }

    func testRouteCardAndMissingMeasurements() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingCycling", "-uiTestingRoute"]
        app.launch()
        app.tabBars.buttons["Log"].tap()
        app.staticTexts["Indoor Cycling · Part 1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workoutRoute"].waitForExistence(timeout: 5))
        let route = XCTAttachment(screenshot: app.screenshot())
        route.name = "Workout route card"; route.lifetime = .keepAlways; add(route)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Indoor Cycling · Part 2"].tap()
        XCTAssertTrue(app.staticTexts["Average power, 0 W"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Energy")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Unavailable")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["workoutRoute"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " km")).firstMatch.exists)
    }

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
