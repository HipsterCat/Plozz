import XCTest

@MainActor
final class LargeNativeNavigationRemoteTests: XCTestCase {
    func testProfileRapidHorizontalNavigation() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        let attach = ProcessInfo.processInfo.environment["PLOZZ_PERFORMANCE_ATTACH"] == "1"
        if attach {
            XCTAssertEqual(app.state, .runningForeground)
        } else {
            app.launchArguments = [
                "--large-native-navigation-fixture", "--real-library-pages", "--trace-tab-transitions"
            ]
            app.launch()
        }
        defer { if !attach { app.terminate() } }
        XCTAssertTrue(app.buttons["top-navigation-home"].waitForExistence(timeout: 15))
        assertFocused(app.buttons["top-navigation-home"], in: app)
        var durations: [TimeInterval] = []
        for _ in 0..<3 {
            let start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<15 { XCUIRemote.shared.press(.right) }
            assertFocused(app.buttons["top-navigation-library:plex:10"], in: app)
            for _ in 0..<15 { XCUIRemote.shared.press(.left) }
            assertFocused(app.buttons["top-navigation-home"], in: app)
            durations.append(ProcessInfo.processInfo.systemUptime - start)
        }
        let journal = app.staticTexts["native-tab-transition-journal"].label
        let evidence = XCTAttachment(string: "Remote round-trip seconds: \(durations)\n" + journal)
        evidence.name = "Rapid horizontal navigation"
        evidence.lifetime = .keepAlways
        add(evidence)
        capture("Rapid navigation returns to Home", in: app)
        #else
        throw XCTSkip("Synthetic navigation fixtures run only on an owned simulator.")
        #endif
    }

    func testHorizontalFocusPresentsEachDestinationOnce() throws {
        try exerciseTransitions(sceneStorage: false)
    }

    func testSceneStoredHorizontalFocusPresentsEachDestinationOnce() throws {
        try exerciseTransitions(sceneStorage: true)
    }

    private func exerciseTransitions(sceneStorage: Bool) throws {
        #if targetEnvironment(simulator)
        let app = launch(arguments: ["--trace-tab-transitions"] + (sceneStorage ? ["--scene-stored-navigation"] : []))
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["large-navigation-content"].waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.menu)
        let journal = app.staticTexts["native-tab-transition-journal"]
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        for (title, key) in [("Watchlist", "watchlist"), ("Live TV", "liveTV"), ("Search", "search")] {
            let before = journal.label.components(separatedBy: "\n").filter { $0 == "\(key):willAppear" }.count
            XCUIRemote.shared.press(.right)
            let tab = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
            assertFocused(tab, in: app)
            let appeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                journal.label.components(separatedBy: "\n").filter { $0 == "\(key):didAppear" }.count > before
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [appeared], timeout: 5), .completed, journal.label)
            let repeated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                journal.label.components(separatedBy: "\n").filter { $0 == "\(key):willAppear" }.count > before + 1
                    || !tab.hasFocus
            }, object: nil)
            repeated.isInverted = true
            let result = XCTWaiter.wait(for: [repeated], timeout: 1)
            let evidence = XCTAttachment(string: journal.label + "\n\n" + app.debugDescription)
            evidence.name = "\(sceneStorage ? "Scene" : "State") transition to \(title)"
            evidence.lifetime = .keepAlways
            add(evidence)
            XCTAssertEqual(result, .completed, "One directional input must present \(title) once and retain tab focus.\n\(journal.label)")
        }
        #else
        throw XCTSkip("Synthetic navigation fixtures run only on an owned simulator.")
        #endif
    }

    func testHorizontalNavigationReachesTwentyLibrariesAndProfileSettings() throws {
        try exerciseNavigation(longNames: false)
    }

    func testHorizontalNavigationReachesTwentyLongLibrariesAndProfileSettings() throws {
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
            app.buttons["library-content-mode-recommended"].frame.minY,
            app.buttons["top-navigation-library:plex:3"].frame.maxY,
            "Root library controls must remain below horizontal navigation."
        )
        let bar = app.descendants(matching: .any)["top-navigation"]
        let modes = app.descendants(matching: .any)["library-content-mode"]
        XCTAssertEqual(bar.frame.midX, app.frame.midX, accuracy: 1)
        XCTAssertEqual(bar.frame.height, 68, accuracy: 1, "Use compact native-like proportions.")
        let sort = app.buttons["library-sort-menu"]
        if sort.exists {
            XCTAssertEqual(bar.frame.width, (sort.frame.maxX - modes.frame.minX) * 0.75, accuracy: 1,
                           "The maximum bar must be exactly 25% narrower than the page keylines.")
        }
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
        assertFocused(app.buttons["top-navigation-profile"], in: app)
        XCTAssertFalse(app.buttons["profile-picker-settings"].exists)
        XCUIRemote.shared.press(.select)
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
        for _ in 0..<35 {
            let focused = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true")).firstMatch
            if focused.exists {
                // Native sidebar focus belongs to its cell, not the labeled button inside it.
                let label = focused.elementType == .cell ? focused.buttons.firstMatch.label : focused.label
                focusedLabels.append(label)
                if label == (longNames ? "Library 20 - Movies and Television Collection"
                    : "Library 20") { lastLibraryReached = true }
                if label == "Settings" {
                    settingsReached = true
                    if sidebar { XCUIRemote.shared.press(.select) }
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
        capture(sidebar ? "Native sidebar after twenty libraries" : "Horizontal navigation after twenty libraries", in: app)
        XCTAssertTrue(lastLibraryReached, "The final library must be reachable. Visited: \(focusedLabels)")
        if sidebar {
            XCTAssertTrue(settingsReached, "Settings must be reachable after the libraries. Visited: \(focusedLabels)")
            XCTAssertTrue(app.staticTexts["large-navigation-settings"].waitForExistence(timeout: 5))
        } else {
            XCTAssertEqual(Set(focusedLabels).count, 27, "Every content destination and Settings must remain reachable.")
            XCTAssertTrue(settingsReached)
            for _ in 0..<27 { XCUIRemote.shared.press(.left) }
            assertFocused(app.buttons["top-navigation-profile"], in: app)
            XCTAssertFalse(app.buttons["profile-picker-settings"].exists, "Focusing the profile must not open it.")
            capture("Concentric profile end of navigation", in: app)
            XCUIRemote.shared.press(.select)
            try openPickerSettings(in: app)
        }

        #else
        throw XCTSkip("Synthetic navigation fixtures run only on an owned simulator.")
        #endif
    }

    func testProfileCancelKeepsHorizontalNavigationResponsive() throws {
        #if targetEnvironment(simulator)
        let app = launch(arguments: ["--trace-tab-transitions"])
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["top-navigation-home"].waitForExistence(timeout: 15))
        for _ in 0..<3 {
            assertFocused(app.buttons["top-navigation-home"], in: app)
            XCUIRemote.shared.press(.left)
            assertFocused(app.buttons["top-navigation-profile"], in: app)
            XCTAssertFalse(app.buttons["profile-picker-settings"].exists)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
            XCUIRemote.shared.press(.menu)
            assertFocused(app.buttons["top-navigation-home"], in: app)
            for key in ["watchlist", "liveTV", "search"] {
                XCUIRemote.shared.press(.right)
                assertFocused(app.buttons["top-navigation-\(key)"], in: app)
            }
            for _ in 0..<3 { XCUIRemote.shared.press(.left) }
        }
        capture("Profile return preserves horizontal navigation", in: app)
        #else
        throw XCTSkip("Synthetic navigation fixtures run only on an owned simulator.")
        #endif
    }

    func testHorizontalStartsOnTheSelectedOffscreenLibrary() throws {
        #if targetEnvironment(simulator)
        let app = launch(arguments: ["--initial-last-library", "--long-library-names"])
        defer { app.terminate() }
        let library = app.buttons["top-navigation-library:plex:20"]
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        assertFocused(library, in: app)
        let bar = app.descendants(matching: .any)["top-navigation"]
        let settings = app.buttons["top-navigation-settings"]
        XCTAssertEqual(bar.frame.midY, library.frame.midY, accuracy: 1)
        XCTAssertEqual(
            bar.frame.maxX - settings.frame.maxX,
            (bar.frame.height - settings.frame.height) / 2, accuracy: 1,
            "The fixed Settings capsule must have equal end and vertical insets."
        )
        capture("Concentric horizontal navigation end", in: app)
        XCUIRemote.shared.press(.down)
        assertFocused(app.buttons["large-navigation-content"], in: app)
        XCUIRemote.shared.press(.menu)
        assertFocused(library, in: app)
        XCUIRemote.shared.press(.left)
        assertFocused(app.buttons["top-navigation-library:plex:19"], in: app)
        #else
        throw XCTSkip("Synthetic navigation fixtures run only on an owned simulator.")
        #endif
    }

    func testHorizontalContentAndDetailReturnKeepNavigationReachable() throws {
        #if targetEnvironment(simulator)
        let app = launch(arguments: ["--navigation-detail-pages"])
        defer { app.terminate() }
        let home = app.buttons["top-navigation-home"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        assertFocused(home, in: app)
        XCUIRemote.shared.press(.down)
        assertFocused(app.buttons["large-navigation-content"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["large-navigation-detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(home.exists, "Detail pages must hide the navigation strip.")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["large-navigation-content"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        assertFocused(home, in: app)
        XCUIRemote.shared.press(.right)
        assertFocused(app.buttons["top-navigation-watchlist"], in: app)
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
        // Behavior is asserted separately; capture settled native transitions.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
