import XCTest

@MainActor
final class LargeNativeNavigationRemoteTests: XCTestCase {
    func testTwentyLibrariesLimitHorizontalTabsAndKeepProfileSettingsReachable() throws {
        try exerciseNavigation(longNames: false)
    }

    func testTwentyLongLibraryNamesLimitHorizontalTabsAndKeepProfileSettingsReachable() throws {
        try exerciseNavigation(longNames: true)
    }

    func testNativeVerticalNavigationReachesAllTwentyLibrariesAndSettings() throws {
        try exerciseNavigation(longNames: false, sidebar: true)
    }

    func testNativeVerticalNavigationReachesTwentyLongLibraryNamesAndSettings() throws {
        try exerciseNavigation(longNames: true, sidebar: true)
    }

    func testHorizontalLibraryFocusStaysInNavigationThroughContentLoading() throws {
        try exerciseLibraryFocus(recommended: false)
    }

    func testHorizontalRecommendedLibraryFocusStaysInNavigationThroughContentLoading() throws {
        try exerciseLibraryFocus(recommended: true)
    }

    private func exerciseLibraryFocus(recommended: Bool) throws {
        #if targetEnvironment(simulator)
        let app = launch(arguments: ["--real-library-pages"] + (recommended ? ["--recommended-library-pages"] : []))
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["large-navigation-content"].waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.menu)
        for title in ["Watchlist", "Live TV", "Search", "Music", "All Libraries", "Library 1", "Library 2", "Library 3"] {
            XCUIRemote.shared.press(.right)
            let tab = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 5), app.debugDescription)
            assertFocused(tab, in: app)
            if title.hasPrefix("Library ") || title == "All Libraries" {
                XCTAssertTrue(app.staticTexts["Movie 0"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
                // Let the async real grid populate without pressing another direction.
                let stillFocused = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in !tab.exists || !tab.hasFocus }, object: nil
                )
                stillFocused.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [stillFocused], timeout: 1), .completed, app.debugDescription)
            }
        }
        XCUIRemote.shared.press(.down)
        let leavesNavigation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !app.buttons.matching(NSPredicate(format: "label == %@", "Library 3")).firstMatch.hasFocus
            }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [leavesNavigation], timeout: 5), .completed)
        XCUIRemote.shared.press(.menu)
        assertFocused(app.buttons.matching(NSPredicate(format: "label == %@", "Library 3")).firstMatch, in: app)
        XCUIRemote.shared.press(.left)
        assertFocused(app.buttons.matching(NSPredicate(format: "label == %@", "Library 2")).firstMatch, in: app)
        XCTAssertGreaterThan(
            app.buttons["library-content-mode-recommended"].frame.minY, app.tabBars.firstMatch.frame.maxY,
            "Root library controls must remain below native top navigation."
        )
        capture("Library navigation remains reachable", in: app)
        #else
        throw XCTSkip("Synthetic navigation fixtures run only on an owned simulator.")
        #endif
    }

    func testProfilePickerSettingsUsesOpaqueFallbackAndReturnsToNavigation() throws {
        #if targetEnvironment(simulator)
        let app = launch(arguments: ["--opaque-controls"])
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["large-navigation-content"].waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.menu)
        XCUIRemote.shared.press(.left)
        try openPickerSettings(in: app)
        #else
        throw XCTSkip("Synthetic navigation fixtures run only on an owned simulator.")
        #endif
    }

    private func exerciseNavigation(longNames: Bool, sidebar: Bool = false) throws {
        #if targetEnvironment(simulator)
        let app = launch(arguments: (longNames ? ["--long-library-names"] : [])
            + (sidebar ? ["--native-vertical-navigation"] : []))
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["large-navigation-content"].waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.menu)

        var focusedLabels: [String] = []
        var lastLibraryReached = false
        var settingsReached = false
        for _ in 0..<(sidebar ? 35 : 14) {
            let focused = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true")).firstMatch
            if focused.exists {
                // Native sidebar focus belongs to its cell, not the labeled button inside it.
                let label = focused.elementType == .cell ? focused.buttons.firstMatch.label : focused.label
                focusedLabels.append(label)
                if label == (longNames ? "Library \(sidebar ? 20 : 3) - Movies and Television Collection"
                    : "Library \(sidebar ? 20 : 3)") { lastLibraryReached = true }
                if label == "Settings" {
                    settingsReached = true
                    XCUIRemote.shared.press(.select)
                    break
                }
                XCTAssertTrue(
                    app.frame.contains(CGPoint(x: focused.frame.midX, y: focused.frame.midY)),
                    "The focused tab must remain visible: \(label) \(focused.frame)"
                )
            }
            XCUIRemote.shared.press(sidebar ? .down : .right)
        }
        let evidence = XCTAttachment(string: focusedLabels.joined(separator: "\n") + "\n\n" + app.debugDescription)
        evidence.name = longNames ? "Long library navigation traversal" : "Library navigation traversal"
        evidence.lifetime = .keepAlways
        add(evidence)
        capture(sidebar ? "Native sidebar after twenty libraries" : "Native top bar capped at ten items", in: app)
        XCTAssertTrue(lastLibraryReached, "The final library must be reachable. Visited: \(focusedLabels)")
        if sidebar {
            XCTAssertTrue(settingsReached, "Settings must be reachable after the libraries. Visited: \(focusedLabels)")
            XCTAssertTrue(app.staticTexts["large-navigation-settings"].waitForExistence(timeout: 5))
        } else {
            XCTAssertEqual(Set(focusedLabels).count, 9, "Nine destinations plus Profile fill the ten native slots.")
            XCTAssertFalse(settingsReached)
            for _ in 0..<9 { XCUIRemote.shared.press(.left) }
            try openPickerSettings(in: app)
        }
        #else
        throw XCTSkip("Synthetic navigation fixtures run only on an owned simulator.")
        #endif
    }

    private func launch(arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = [
            "--large-native-navigation-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + arguments
        app.launch()
        return app
    }

    private func openPickerSettings(in app: XCUIApplication) throws {
        let settings = app.buttons["profile-picker-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        XCUIRemote.shared.press(.up)
        assertFocused(settings, in: app)
        capture("Profile picker Settings cog", in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["large-navigation-settings"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["large-navigation-content"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        assertFocused(app.buttons.matching(NSPredicate(format: "label == %@", "Home")).firstMatch, in: app)
    }

    private func assertFocused(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in element.exists && element.hasFocus }, object: nil
        )], timeout: 5), .completed, app.debugDescription)
        XCTAssertTrue(app.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)))
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
