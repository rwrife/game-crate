import XCTest

final class GameCrateLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddGameRendersEnteredAndUnknownFields() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let addGame = app.buttons["shelf.addGame"]
        XCTAssertTrue(addGame.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, identifier: "shelf.empty").waitForExistence(timeout: 5))
        addGame.tap()

        let title = app.textFields["game.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Sky Team")

        let categories = app.textFields["game.categories"]
        categories.tap()
        categories.typeText("cooperative, two-player")
        app.buttons["game.save"].tap()

        let card = app.buttons["game.card.Sky Team"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Players unknown"))
        XCTAssertTrue(card.label.contains("Time unknown"))
        XCTAssertTrue(card.label.contains("cooperative"))
    }

    @MainActor
    func testDeleteGameCitesAndCascadesOnePlay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-seed-play"]
        app.launch()

        let card = app.buttons["game.card.Seeded Game"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let delete = app.buttons["game.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        let destructive = app.buttons["Delete Game and 1 Play"]
        XCTAssertTrue(destructive.waitForExistence(timeout: 5))
        destructive.tap()

        XCTAssertTrue(element(app, identifier: "shelf.empty").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["game.card.Seeded Game"].exists)
    }

    @MainActor
    func testPeopleRosterCreateEditAndDelete() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.tabBars.buttons["People"].tap()
        XCTAssertTrue(element(app, identifier: "people.empty").waitForExistence(timeout: 5))
        app.buttons["people.addPerson"].tap()

        let name = app.textFields["person.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Ana")
        app.buttons["person.save"].tap()

        let row = app.buttons["person.row.Ana"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let editedName = app.textFields["person.name"]
        editedName.tap()
        editedName.clearAndTypeText("Anita")
        app.buttons["person.save"].tap()

        let editedRow = app.buttons["person.row.Anita"]
        XCTAssertTrue(editedRow.waitForExistence(timeout: 5))
        editedRow.tap()
        app.buttons["person.delete"].tap()
        app.buttons["Delete Person"].tap()
        XCTAssertTrue(element(app, identifier: "people.empty").waitForExistence(timeout: 5))
    }

    @MainActor
    func testValidationMessagesAreVisibleForEmptyRequiredFields() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["shelf.addGame"].tap()
        app.buttons["game.save"].tap()
        let gameError = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Title is required")).firstMatch
        XCTAssertTrue(gameError.waitForExistence(timeout: 5))
        app.buttons["game.cancel"].tap()

        app.tabBars.buttons["People"].tap()
        app.buttons["people.addPerson"].tap()
        app.buttons["person.save"].tap()
        let personError = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Name is required")).firstMatch
        XCTAssertTrue(personError.waitForExistence(timeout: 5))
    }

    @MainActor
    func testShortlistPickLogAndWallUpdateJourney() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-seed-shortlist"]
        app.launch()

        app.tabBars.buttons["Tonight"].tap()

        let pick = app.buttons["shortlist.pick.Cascadia"]
        XCTAssertTrue(pick.waitForExistence(timeout: 10))
        XCTAssertTrue(pick.label.contains("Never played"))

        let unspecified = app.buttons["shortlist.unspecified"]
        XCTAssertTrue(unspecified.waitForExistence(timeout: 5))
        XCTAssertTrue(unspecified.label.contains("1"))

        let exclusion = element(app, identifier: "shortlist.exclusion.Twilight Imperium")
        XCTAssertTrue(exclusion.waitForExistence(timeout: 5))

        pick.tap()
        let save = app.buttons["quicklog.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let wallCard = app.buttons["wall.game.Cascadia"]
        XCTAssertTrue(wallCard.waitForExistence(timeout: 5))
        XCTAssertTrue(wallCard.label.contains("Fits tonight"))
        XCTAssertTrue(wallCard.label.contains("Last played today"))
    }

    @MainActor
    func testCorrectionAppendsVisibleCompensatingEvent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-seed-shortlist"]
        app.launch()

        app.tabBars.buttons["Tonight"].tap()
        XCTAssertTrue(app.buttons["shortlist.pick.Cascadia"].waitForExistence(timeout: 10))
        app.buttons["shortlist.pick.Cascadia"].tap()
        app.buttons["quicklog.save"].tap()

        let wallCard = app.buttons["wall.game.Cascadia"]
        XCTAssertTrue(wallCard.waitForExistence(timeout: 5))
        wallCard.tap()

        let correctionButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "history.correct.")
        ).firstMatch
        XCTAssertTrue(correctionButton.waitForExistence(timeout: 5))
        correctionButton.tap()
        XCTAssertTrue(app.buttons["quicklog.save"].waitForExistence(timeout: 5))
        app.buttons["quicklog.save"].tap()

        let superseded = app.staticTexts["Superseded by a compensating correction"]
        XCTAssertTrue(superseded.waitForExistence(timeout: 5))
        let correction = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "history.correction.")
        ).firstMatch
        XCTAssertTrue(correction.waitForExistence(timeout: 5))
    }

    /// Issue #4 acceptance: Dynamic Type reflow. Key controls on both
    /// management screens stay hittable at AX5, the largest accessibility
    /// content size category.
    @MainActor
    func testManagementScreensStayHittableAtAX5() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launchEnvironment["UIPreferredContentSizeCategoryName"] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launch()

        let addGame = app.buttons["shelf.addGame"]
        XCTAssertTrue(addGame.waitForExistence(timeout: 10))
        XCTAssertTrue(addGame.isHittable)

        app.tabBars.buttons["People"].tap()
        let addPerson = app.buttons["people.addPerson"]
        XCTAssertTrue(addPerson.waitForExistence(timeout: 5))
        XCTAssertTrue(addPerson.isHittable)
    }
}

/// Exact-identifier lookup that does not depend on the surfaced
/// accessibility element type (a List-wrapped empty state can surface as
/// `Other`, `Cell`, or `StaticText` depending on iOS version).
private func element(_ app: XCUIApplication, identifier: String) -> XCUIElement {
    app.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier == %@", identifier))
        .firstMatch
}

private extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        tap()
        press(forDuration: 0.8)
        let selectAll = XCUIApplication().menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
            typeText(text)
        } else {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (value as? String)?.count ?? 0))
            typeText(text)
        }
    }
}
