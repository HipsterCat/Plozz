import XCTest

@MainActor
final class IPTVOrganizationInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        #if os(tvOS)
        app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        #else
        app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        #endif
    }

    override func tearDown() {
        if let testRun, testRun.failureCount > 0 {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.lifetime = .keepAlways
            add(tree)
            capture("failure")
        }
        app.terminate()
        app = nil
        super.tearDown()
    }

    func testVisibilitySelectionAndFavoritesRemainIndependent() {
        launch()
        activate(app.buttons["live-tv-manage-categories"])
        let visibility = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "live-tv-category-visibility-")
        ).firstMatch
        XCTAssertTrue(visibility.waitForExistence(timeout: 5), app.debugDescription)
        let favorite = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "live-tv-category-favorite-")
        ).firstMatch
        #if os(iOS)
        let visibilityTitle = visibility.staticTexts["Visibility"]
        let favoriteTitle = favorite.staticTexts["Favorite category"]
        XCTAssertEqual(visibilityTitle.frame.minX, favoriteTitle.frame.minX, accuracy: 2)
        #endif
        capture("categories")
        activate(visibility)
        XCTAssertTrue(app.buttons["Show"].waitForExistence(timeout: 5), app.debugDescription)
        capture("visibility-options")
        activate(app.buttons["Show"])
        XCTAssertTrue(visibility.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(visibility.label.contains("Show"), app.debugDescription)
        #if os(iOS)
        XCTAssertEqual(favorite.value as? String, "0")
        #endif
        activate(favorite)
        #if os(iOS)
        XCTAssertEqual(favorite.value as? String, "1")
        #else
        XCTAssertTrue(favorite.label.contains("On") || (favorite.value as? String) == "1", app.debugDescription)
        #endif
        XCTAssertTrue(visibility.label.contains("Show"), app.debugDescription)
        back()
        activate(app.buttons["live-tv-manage-hidden"])
        XCTAssertFalse(app.buttons["live-tv-show-cinema"].exists)
        XCTAssertTrue(app.buttons["live-tv-show-community"].exists)
    }

    func testHiddenActionsAlignAndRestoreOnlyTheSelectedChannel() {
        launch(["--organization-hidden"])
        let cinema = app.buttons["live-tv-show-cinema"]
        let community = app.buttons["live-tv-show-community"]
        XCTAssertTrue(community.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(cinema.frame.maxX, community.frame.maxX, accuracy: 2)
        XCTAssertGreaterThanOrEqual(cinema.frame.height, 44)
        XCTAssertGreaterThanOrEqual(community.frame.height, 44)
        capture("hidden")
        activate(community)
        let gone = NSPredicate { _, _ in !community.exists }
        XCTAssertEqual(XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: gone, object: nil)], timeout: 5
        ), .completed, app.debugDescription)
        XCTAssertTrue(cinema.exists)
        XCTAssertTrue(app.buttons["live-tv-show-events"].exists)
        activate(app.buttons["live-tv-reset-visibility"])
        XCTAssertTrue(app.staticTexts["No hidden channels"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testRegionNavigationAndSelection() {
        launch()
        activate(app.buttons["live-tv-manage-regions"])
        XCTAssertTrue(app.buttons["live-tv-region-countries"].waitForExistence(timeout: 5))
        capture("regions")
        activate(app.buttons["live-tv-region-countries"])
        let country = element("live-tv-region-country-fr")
        XCTAssertTrue(country.waitForExistence(timeout: 5), app.debugDescription)
        activate(country)
        capture("countries")
        back()
        activate(app.buttons["live-tv-region-languages"])
        let language = element("live-tv-region-language-fr")
        XCTAssertTrue(language.waitForExistence(timeout: 5), app.debugDescription)
        activate(language)
        capture("languages")
        back()
        back()
        activate(app.buttons["live-tv-manage-hidden"])
        XCTAssertTrue(app.buttons["live-tv-show-cinema"].waitForExistence(timeout: 5),
                      "An explicitly hidden category must not be restored by a matching region.")
    }

    #if os(tvOS)
    func testRestoringLastChannelRetainsFocusOnPreviousChannelThenReset() {
        launch(["--organization-hidden"])
        activate(app.buttons["live-tv-show-events"])
        XCTAssertTrue(app.buttons["live-tv-show-community"].hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["live-tv-show-cinema"].hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["live-tv-reset-visibility"].hasFocus, app.debugDescription)
        XCTAssertTrue(app.staticTexts["No hidden channels"].exists)
    }
    #endif

    func testReadOnlyRecoveryCannotMutate() {
        launch(["--organization-hidden", "--organization-read-only"])
        let show = app.buttons["live-tv-show-community"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        XCTAssertFalse(show.isEnabled)
        XCTAssertFalse(app.buttons["live-tv-reset-visibility"].isEnabled)
    }

    func testLongDescriptionsAndRightToLeftRecovery() {
        launch(["--organization-hidden", "--organization-long-name", "--organization-rtl"])
        let action = app.buttons["live-tv-show-community"]
        let label = element("live-tv-hidden-label-community")
        reveal(action)
        XCTAssertFalse(action.frame.intersects(label.frame), app.debugDescription)
        XCTAssertGreaterThanOrEqual(action.frame.minX, app.windows.firstMatch.frame.minX)
        XCTAssertLessThanOrEqual(action.frame.maxX, app.windows.firstMatch.frame.maxX)
        capture("hidden-rtl")
        activate(action)
        XCTAssertFalse(action.exists)
    }

    #if os(iOS)
    func testLargeTextStacksRecoveryActionBelowItsDescription() {
        launch(["--organization-hidden", "--organization-long-name", "--organization-large-text"])
        let action = app.buttons["live-tv-show-community"]
        reveal(action)
        let label = element("live-tv-hidden-label-community")
        XCTAssertGreaterThanOrEqual(action.frame.minY, label.frame.maxY)
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        XCTAssertLessThanOrEqual(action.frame.maxX, app.windows.firstMatch.frame.maxX)
        capture("hidden-large-text")
        action.tap()
        XCTAssertFalse(action.exists)
    }
    #endif

    private func launch(_ arguments: [String] = []) {
        app.launchArguments = [
            "--iptv-organization-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + arguments
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func activate(_ target: XCUIElement) {
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        reveal(target)
        #if os(tvOS)
        XCTAssertTrue(target.hasFocus || target.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists, app.debugDescription)
        XCUIRemote.shared.press(.select)
        #else
        if target.elementType == .switch, target.switches.firstMatch.exists {
            target.switches.firstMatch.tap()
        } else {
            target.tap()
        }
        #endif
    }

    private func reveal(_ target: XCUIElement) {
        #if os(tvOS)
        for _ in 0..<24 {
            if target.hasFocus || target.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists { return }
            let focused = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let direction: XCUIRemote.Button
            if !focused.exists || target.frame.midY > focused.frame.midY + 10 { direction = .down }
            else if target.frame.midY < focused.frame.midY - 10 { direction = .up }
            else { direction = target.frame.midX < focused.frame.midX ? .left : .right }
            XCUIRemote.shared.press(direction)
        }
        #else
        for _ in 0..<16 {
            let safeFrame = app.windows.firstMatch.frame.insetBy(dx: 0, dy: 100)
            if target.exists && target.isHittable && safeFrame.contains(target.frame) { return }
            if target.exists && target.frame.midY < app.windows.firstMatch.frame.midY {
                app.scrollViews.firstMatch.swipeDown()
            } else {
                app.scrollViews.firstMatch.swipeUp()
            }
        }
        #endif
        XCTFail("Could not reach control: \(target.identifier)\n\(app.debugDescription)")
    }

    private func back() {
        #if os(tvOS)
        XCUIRemote.shared.press(.menu)
        #else
        app.navigationBars.buttons.firstMatch.tap()
        #endif
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "iptv-organization-\(name)"
        image.lifetime = .keepAlways
        add(image)
    }
}
