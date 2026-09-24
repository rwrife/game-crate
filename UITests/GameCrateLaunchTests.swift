import XCTest

final class GameCrateLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBootstrapHomeLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.otherElements["bootstrap.home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Game Crate"].exists)
        XCTAssertTrue(app.staticTexts["Shelf, play ledger, and tonight's shortlist arrive in the next milestones."].exists)
    }
}
