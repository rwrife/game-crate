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
        let originalEventIdentifier = correctionButton.identifier
        correctionButton.tap()
        XCTAssertTrue(app.buttons["quicklog.save"].waitForExistence(timeout: 5))
        app.buttons["quicklog.save"].tap()

        let superseded = app.staticTexts["Superseded by a compensating correction"]
        XCTAssertTrue(superseded.waitForExistence(timeout: 5))

        // Rows appended inside an already-presented sheet have been observed
        // to never surface in the accessibility tree during that sheet's
        // lifetime (verified across four query strategies on CI). Re-present
        // the history sheet so the ledger renders into a fresh accessibility
        // surface before asserting the compensating event is visible.
        app.buttons["history.done"].tap()
        let wallCardAfterCorrection = app.buttons["wall.game.Cascadia"]
        XCTAssertTrue(wallCardAfterCorrection.waitForExistence(timeout: 5))
        wallCardAfterCorrection.tap()

        let reopenedSuperseded = app.staticTexts["Superseded by a compensating correction"]
        XCTAssertTrue(reopenedSuperseded.waitForExistence(timeout: 5))

        // The original event is now superseded, so the only row still offering
        // a correction is the newly appended compensating event.
        let remainingCorrectionButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "history.correct.")
        )
        XCTAssertTrue(remainingCorrectionButtons.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(remainingCorrectionButtons.count, 1)
        XCTAssertNotEqual(remainingCorrectionButtons.element(boundBy: 0).identifier, originalEventIdentifier)

        // The compensating event is itself visible as a distinct "Correction" entry.
        let correctionHeadline = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Correction")
        ).firstMatch
        XCTAssertTrue(correctionHeadline.waitForExistence(timeout: 5))
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

    // MARK: - Issue #6: insights (profiles + shelf holes)

    /// Empty-store state: the Insights tab says there is nothing to count
    /// instead of inventing numbers.
    @MainActor
    func testInsightsEmptyStatesSayNothingToCount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(element(app, identifier: "insights.profiles.empty").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, identifier: "holes.empty").waitForExistence(timeout: 5))
    }

    /// A rated history renders as integer counts only: play count, rated
    /// fraction, the 1–5 distribution, and per-category counts.
    @MainActor
    func testProfileShowsIntegerCountsForRatedHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-seed-insights"]
        app.launch()

        app.tabBars.buttons["Insights"].tap()
        let anaRow = app.buttons["insights.person.Ana"]
        XCTAssertTrue(anaRow.waitForExistence(timeout: 10))
        XCTAssertTrue(anaRow.label.contains("2 plays"))
        anaRow.tap()

        XCTAssertTrue(element(app, identifier: "profile.plays.Ana").waitForExistence(timeout: 5))
        XCTAssertTrue(staticText(app, containing: "2 plays logged").waitForExistence(timeout: 5))
        XCTAssertTrue(scrollHunt(app, staticText(app, containing: "2 of 2 plays rated")))
        XCTAssertTrue(scrollHunt(app, staticText(app, containing: "5 stars: 1")))
        XCTAssertTrue(scrollHunt(app, staticText(app, containing: "4 stars: 1")))
        XCTAssertTrue(scrollHunt(app, staticText(app, containing: "1 star: 0")))
        XCTAssertTrue(scrollHunt(app, staticText(app, containing: "Card: 1")))
        XCTAssertTrue(scrollHunt(app, staticText(app, containing: "Party: 1")))
        // No ratings means no guessed wellness/personality framing anywhere.
        XCTAssertFalse(app.staticTexts["Typical gamer personality"].exists)
    }

    /// Short-history state: a player with plays but zero ratings sees an
    /// explicit "nothing recorded, distribution stays zero" state rather
    /// than interpolated values.
    @MainActor
    func testShortHistoryProfileRendersUnknownRatings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-seed-insights"]
        app.launch()

        app.tabBars.buttons["Insights"].tap()
        let boRow = app.buttons["insights.person.Bo"]
        XCTAssertTrue(boRow.waitForExistence(timeout: 10))
        XCTAssertTrue(boRow.label.contains("1 play"))
        boRow.tap()

        XCTAssertTrue(element(app, identifier: "profile.plays.Bo").waitForExistence(timeout: 5))
        XCTAssertTrue(staticText(app, containing: "1 play logged").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, identifier: "profile.no-ratings-short.Bo").waitForExistence(timeout: 5))
        XCTAssertTrue(staticText(app, containing: "0 of 1 plays rated").waitForExistence(timeout: 5))
        XCTAssertTrue(staticText(app, containing: "5 stars: 0").waitForExistence(timeout: 5))
    }

    /// Shelf-hole flow: an unmatched category request validates and is
    /// rejected without touching the list; accepted requests explain each
    /// line with proven matches or the explicit "never counted" unknowns;
    /// rows are removable.
    @MainActor
    func testShelfHoleListIsExplainedAndRemovable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-seed-insights"]
        app.launch()

        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(element(app, identifier: "holes.empty").waitForExistence(timeout: 10))

        // Accept the default draft (2 players within 30 min, no category).
        revealTap(app, button: app.buttons["hole.add"])
        XCTAssertTrue(scrollHunt(app, element(app, identifier: "holes.row.0")))
        XCTAssertTrue(scrollHunt(app, staticText(app, containing: "1 proven match: Jaipur")))
        XCTAssertTrue(staticText(app, containing: "1 game with unspecified fields never counted").exists)

        // Category requested with no tag: validation error, list unchanged.
        enableSwitch(app, identifier: "hole.category")
        revealTap(app, button: app.buttons["hole.add"])
        XCTAssertTrue(scrollHunt(app, element(app, identifier: "hole.error")))
        XCTAssertTrue(staticText(app, containing: "Pick or type a category tag").exists)
        // List untouched: a second row never materialized.
        XCTAssertFalse(element(app, identifier: "holes.row.1").exists)

        // Type a tag directly (the same proven interaction the game editor
        // uses): the chip buttons live inside a horizontal ScrollView row,
        // which bridges unreliably into the XCUITest hierarchy inside a
        // virtualized List (observed on CI as "No matches found" for
        // hole.tag.Party while every sibling control resolved). Add a true
        // hole explained by zero proven coverage.
        let categoryField = app.textFields["hole.categoryTag"]
        XCTAssertTrue(scrollHunt(app, categoryField), "category field never became hittable")
        categoryField.tap()
        // Trailing newline commits the text and dismisses the keyboard so it
        // cannot absorb the Add tap below the field.
        categoryField.typeText("Party\n")
        revealTap(app, button: app.buttons["hole.add"])
        let secondRow = element(app, identifier: "holes.row.1")
        XCTAssertTrue(scrollHunt(app, secondRow))
        XCTAssertTrue(secondRow.label.contains("Party"))
        XCTAssertTrue(scrollHunt(app, staticText(app, containing: "no shelf game provably covers this")))

        // Remove the Party row. The original row re-explains itself (row
        // index shifts to 0) and the hole explanation disappears completely.
        revealTap(app, button: app.buttons["holes.remove.1"])
        XCTAssertFalse(staticText(app, containing: "no shelf game provably covers this").waitForExistence(timeout: 2))
        let survivor = element(app, identifier: "holes.row.0")
        XCTAssertTrue(survivor.waitForExistence(timeout: 5))
        XCTAssertTrue(survivor.label.contains("2 players"))
        XCTAssertTrue(scrollHunt(app, staticText(app, containing: "1 proven match: Jaipur")))
    }

    // MARK: - Issue #7: backup restore preview

    /// Restore is preview-first (issue #7 acceptance): choosing a valid
    /// backup shows an integer counts diff, and Cancel keeps the store
    /// byte-for-byte untouched (empty store stays empty). The destructive
    /// Replace path is only reachable from a preview; cancellation safety
    /// on invalid files is covered by the CrateStore test suite.
    @MainActor
    func testRestorePreviewShowsCountsAndCancelKeepsStore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-restore-preview"]
        app.launch()

        app.tabBars.buttons["Insights"].tap()
        let openButton = element(app, identifier: "privacy.open")
        XCTAssertTrue(openButton.waitForExistence(timeout: 10))
        XCTAssertTrue(openButton.isHittable)
        openButton.tap()

        // The fixture pushed a real codec round-trip through the same
        // startRestorePreview path file import uses. Identified via the
        // title (container-level identifiers clobber child identifiers).
        let previewTitle = element(app, identifier: "restore.preview.title")
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 5))
        let summary = staticText(app, containing: "Backup contains 2 games, 2 people, and 2 plays")
        XCTAssertTrue(scrollHunt(app, summary), "restore summary counts never surfaced")

        // Cancel leaves everything as it was: preview gone, shelf still
        // empty (the fixture never wrote to the store).
        revealTap(app, button: app.buttons["restore.cancel"])
        XCTAssertFalse(element(app, identifier: "restore.preview.title").waitForExistence(timeout: 2))

        app.tabBars.buttons["Shelf"].tap()
        XCTAssertTrue(element(app, identifier: "shelf.empty").waitForExistence(timeout: 5))
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

/// Scroll-hunt for a target inside a SwiftUI List. A List virtualizes rows
/// outside the rendered window, so `waitForExistence` can never realize an
/// off-screen row and `tap` needs a hittable element. Probe existence via
/// `exists` (never throws on absence) BEFORE querying `isHittable`. After
/// a candidate is visible, require it to STILL be visible after a settle
/// delay: momentum scrolling plus row insertions/removals re-virtualize the
/// List and can evict the target between check and tap (observed on CI as
/// "Failed to get matching snapshot" right after a swipe revealed the chip
/// row). Strategy: current viewport, then progressive DOWN swipes, then
/// rewind UP. Success means visible AND hittable AND stable.
@discardableResult
private func scrollHunt(_ app: XCUIApplication, _ target: XCUIElement, maxScrolls: Int = 8) -> Bool {
    func settled() -> Bool {
        guard target.exists, target.isHittable else { return false }
        usleep(400_000)
        return target.exists && target.isHittable
    }
    if settled() { return true }
    for _ in 0 ..< maxScrolls {
        app.swipeUp() // moves the List toward later rows
        if settled() { return true }
    }
    for _ in 0 ..< maxScrolls {
        app.swipeDown() // rewind toward earlier rows
        if settled() { return true }
    }
    return false
}

/// Reveal-then-tap for controls that can sit off-screen in a virtualized
/// List after rows are inserted or removed. Scrolls to a settled hittable
/// state BEFORE any tap, because an unrealized row exists only after being
/// scrolled into the rendered window.
private func revealTap(_ app: XCUIApplication, button: XCUIElement) {
    XCTAssertTrue(scrollHunt(app, button), "button never became hittable: \(button.identifier)")
    button.tap()
}

private func staticText(_ app: XCUIApplication, containing fragment: String) -> XCUIElement {
    app.staticTexts
        .matching(NSPredicate(format: "label CONTAINS %@", fragment))
        .firstMatch
}

/// Toggle in a List row can surface as one merged element whose label
/// region absorbs a raw tap; scroll it into a hittable position, drive the
/// nested switch when present, and prove the flip by revealing the
/// dependent control.
private func enableSwitch(_ app: XCUIApplication, identifier: String) {
    let toggle = app.switches[identifier].firstMatch
    let dependent = element(app, identifier: "hole.categoryTag")
    if dependent.isHittable { return }
    XCTAssertTrue(scrollHunt(app, toggle), "switch never became hittable: \(identifier)")
    let nested = toggle.switches.firstMatch
    if nested.isHittable {
        nested.tap()
    } else {
        toggle.tap()
    }
    if !scrollHunt(app, dependent) {
        XCTAssertTrue(scrollHunt(app, toggle))
        toggle.tap()
        XCTAssertTrue(scrollHunt(app, dependent))
    }
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
