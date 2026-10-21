import XCTest

@MainActor
final class SettingsWorkspaceRemoteTests: XCTestCase {
    func testSwitchingFromPinnedSidebarKeepsNavigationSettingsResponsive() throws {
        try exerciseSidebarSwitch(from: "rail")
    }

    func testSwitchingFromTopBarKeepsNavigationSettingsResponsive() throws {
        try exerciseSidebarSwitch(from: "tabBar")
    }

    private func exerciseSidebarSwitch(from style: String) throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(style: style)
        defer { app.terminate() }
        let navigation = app.buttons["settings-page-navigation"]
        try focus(section("screensNavigation", in: app), in: app)
        XCUIRemote.shared.press(.select)
        try focus(navigation, in: app)
        XCUIRemote.shared.press(.select)
        let choice = app.buttons["Sidebar"]
        try focus(choice, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(hasFocus(choice), "Changing chrome must preserve the focused Settings control. \(app.debugDescription)")
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(hasFocus(app.buttons["Pinned Sidebar"]), "The next directional input must work.")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(navigation.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(hasFocus(navigation), "Back must return to the Navigation action.")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(section("screensNavigation", in: app).waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertFalse(section("screensNavigation", in: app).exists, app.debugDescription)
        try openSettingsIfNeeded(in: app)
        try enterAndReturn("playback", in: app)
        #else
        throw XCTSkip("Never changes navigation settings on a physical device.")
        #endif
    }

    func testDeviceSetupOpensAndReturnsToICloudSettings() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        defer { app.terminate() }
        try focus(section("syncSetup", in: app), in: app)
        XCUIRemote.shared.press(.select)
        for attempt in 1...2 {
            let setup = app.buttons.containing(.staticText, identifier: "Set Up Another Device").firstMatch
            XCTAssertTrue(setup.waitForExistence(timeout: 5), app.debugDescription)
            try focus(setup, in: app)
            XCUIRemote.shared.press(.select)
            let heading = app.staticTexts["Set up another device"]
            XCTAssertTrue(heading.waitForExistence(timeout: 5), app.debugDescription)
            let disappeared = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in !heading.exists }, object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 2), .timedOut,
                           "Setup must not disappear without user input.")
            capture("device-setup-open-\(attempt)", in: app)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(setup.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(heading.exists)
        }
        #else
        throw XCTSkip("Simulator-only setup presentation review.")
        #endif
    }

    func testSettingsMenusShareWholeRowFocusAndRestoreChoices() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        defer { capture("settings-menus-final", in: app) }
        let language = section("language", in: app)
        try focus(language, in: app)
        let menuWidth = language.frame.width
        XCTAssertGreaterThan(menuWidth, 800)
        capture("settings-language-whole-row", in: app)
        try focus(section("playback", in: app), in: app)
        XCUIRemote.shared.press(.select)
        let audio = app.buttons["Preferred audio language"]
        try focus(audio, in: app)
        XCTAssertTrue(hasFocus(audio))
        XCTAssertEqual(audio.frame.width, menuWidth, accuracy: 1)
        XCTAssertEqual(audio.value as? String, "Original")
        capture("settings-audio-whole-row", in: app)
        XCUIRemote.shared.press(.select)
        let device = app.cells.containing(.any, identifier: "Device").firstMatch
        XCTAssertTrue(device.waitForExistence(timeout: 5), app.debugDescription)
        try focus(device, in: app)
        XCUIRemote.shared.press(.select)
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in audio.value as? String == "Device" }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        XCTAssertTrue(hasFocus(audio), "Selecting a menu value must restore the full row's focus.")
        XCUIRemote.shared.press(.select)
        try focus(app.cells.containing(.any, identifier: "Original").firstMatch, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(audio.value as? String, "Original")

        let separate = app.switches["Set separately for movies, TV shows & anime"]
        try focus(separate, in: app)
        XCUIRemote.shared.press(.select)
        let movies = app.buttons["Movies"]
        try focus(movies, in: app)
        XCTAssertEqual(movies.frame.width, menuWidth, accuracy: 1)
        capture("settings-audio-per-type", in: app)
        try focus(separate, in: app)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.menu)
        waitForCategoryFocus("playback", in: app)
        try focus(section("subtitles", in: app), in: app)
        XCUIRemote.shared.press(.select)
        let subtitles = app.buttons["Subtitle language"]
        try focus(subtitles, in: app)
        XCTAssertEqual(subtitles.frame.width, menuWidth, accuracy: 1)
        capture("settings-subtitle-whole-row", in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.cells.containing(.any, identifier: "Device Default")
            .firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCUIRemote.shared.press(.menu)
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.hasFocus(subtitles) }, object: nil
        )
        let restoration = XCTWaiter.wait(for: [restored], timeout: 5)
        capture("settings-subtitle-menu-return", in: app)
        XCTAssertEqual(restoration, .completed, app.debugDescription)
        XCUIRemote.shared.press(.menu)
        waitForCategoryFocus("subtitles", in: app)
        #else
        throw XCTSkip("Never changes language preferences on a physical device.")
        #endif
    }

    func testSettingsSectionsAndNestedPagesInTheProductionApp() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        defer { capture("final-state", in: app) }
        let playback = section("playback", in: app)
        XCTAssertTrue(playback.isSelected, app.debugDescription)
        XCTAssertTrue(app.buttons["settings-profile-switch"].exists)
        XCTAssertTrue(app.buttons["settings-profile-edit"].exists)
        XCTAssertFalse(app.buttons["settings-group-language"].exists,
                       "Categories must not preview a second page beside the list.")
        assertCenteredSettingsColumn(in: app)
        capture("01-playback", in: app)
        XCTAssertFalse(section("general", in: app).exists)
        XCTAssertFalse(section("customizeHome", in: app).exists)
        XCTAssertFalse(app.buttons["settings-page-theme"].exists)
        let profileRows = ["playback", "subtitles", "liveTV", "myLibraries", "appearance",
                           "screensNavigation", "integrations", "language"].map { section($0, in: app) }
        XCTAssertTrue(profileRows.allSatisfy(\.exists), app.debugDescription)
        let positions = profileRows.map(\.frame.minY)
        XCTAssertEqual(positions, positions.sorted())
        try enterAndReturn("playback", in: app)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(section("subtitles", in: app).isSelected, app.debugDescription)

        for (index, name) in [
            "subtitles", "liveTV", "myLibraries", "appearance", "screensNavigation", "integrations",
            "servers", "profile", "parentalPIN", "seerr", "syncSetup", "metadata", "help"
        ].enumerated() {
            let target = section(name, in: app)
            XCTAssertTrue(target.exists, "Missing Settings section: \(name)")
            try focus(target, in: app)
            XCTAssertTrue(hasFocus(target))
            capture(String(format: "%02d-%@", index + 2, name), in: app)
            try enterAndReturn(name, in: app, usingRight: index.isMultiple(of: 2))
        }
        try focus(section("playback", in: app), in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Audio"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["settings-page-subtitles"].exists)
        XCTAssertFalse(app.staticTexts["Show subtitles"].exists)
        capture("19-playback-entered", in: app)
        let audioKeyline = app.staticTexts["Audio"].frame.minX
        for label in [
            "Preferred audio language", "Set separately for movies, TV shows & anime",
            "Remember audio per series", "TrueHD Atmos and DTS:X", "Autoplay & Up Next"
        ] {
            let text = app.staticTexts[label].firstMatch
            XCTAssertTrue(text.exists, label)
            XCTAssertEqual(text.frame.minX, audioKeyline, accuracy: 1,
                           "\(label) must share the section-heading keyline.")
        }
        let helper = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "How Plozz picks the audio language")
        ).firstMatch
        XCTAssertTrue(helper.exists)
        XCTAssertEqual(helper.frame.minX, audioKeyline, accuracy: 1,
                       "Multiline helper text must align with the native control labels.")
        XCTAssertFalse(section("screensNavigation", in: app).exists, app.debugDescription)
        XCUIRemote.shared.press(.menu)
        try focus(section("subtitles", in: app), in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Show subtitles"].waitForExistence(timeout: 5), app.debugDescription)
        capture("20-subtitles", in: app)
        let style = app.buttons["Customize subtitle style"]
        try focus(style, in: app)
        capture("subtitles-lower", in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Back"))
            .firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        capture("subtitle-style", in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(style.waitForExistence(timeout: 5), app.debugDescription)
        XCUIRemote.shared.press(.menu)
        waitForCategoryFocus("subtitles", in: app)
        #else
        throw XCTSkip("Never seeds or changes settings on a physical device.")
        #endif
    }

    func testLanguageOpensItsPickerDirectlyAndKeepsFeedbackReachable() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        let language = section("language", in: app)
        try focus(language, in: app)
        if language.value as? String != "System", language.value as? String != "English" {
            XCUIRemote.shared.press(.select)
            try focus(app.cells.containing(.any, identifier: "English").firstMatch, in: app)
            XCUIRemote.shared.press(.select)
            try focus(language, in: app)
        }
        capture("language-row", in: app)
        XCTAssertEqual(language.label, "Language")
        let originalValue = try XCTUnwrap(language.value as? String)
        XCTAssertTrue(originalValue.contains("System") || originalValue.contains("English"), originalValue)
        let originalOption = originalValue.contains("System") ? "System" : "English"
        XCTAssertLessThanOrEqual(language.frame.height, 80)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.cells.containing(.any, identifier: "English").firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["settings-category-back"].exists)
        capture("language-picker", in: app)
        XCUIRemote.shared.press(.menu)
        waitForCategoryFocus("language", in: app)

        XCUIRemote.shared.press(.select)
        try focus(app.cells.containing(.any, identifier: "Français").firstMatch, in: app)
        XCUIRemote.shared.press(.select)
        let updated = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                language.exists && (language.value as? String)?.contains("Français") == true
            }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
        try focus(language, in: app)
        XCUIRemote.shared.press(.select)
        let feedback = app.cells.containing(.any, identifier: "settings-language-feedback").firstMatch
        for _ in 0..<50 where !feedback.exists { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(feedback.waitForExistence(timeout: 5), app.debugDescription)
        try focus(feedback, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["settings-language-feedback-close"].waitForExistence(timeout: 5), app.debugDescription)
        capture("language-feedback", in: app)
        XCUIRemote.shared.press(.menu)
        waitForCategoryFocus("language", in: app)
        XCUIRemote.shared.press(.select)
        try focus(app.cells.containing(.any, identifier: "English").firstMatch, in: app)
        XCUIRemote.shared.press(.select)
        if originalOption == "System" {
            try focus(language, in: app)
            XCUIRemote.shared.press(.select)
            try focus(app.cells.containing(.any, identifier: "System").firstMatch, in: app)
            XCUIRemote.shared.press(.select)
        }
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        XCTAssertEqual(language.value as? String, originalValue)
        try focus(section("playback", in: app), in: app)
        #else
        throw XCTSkip("Never changes language on a physical device.")
        #endif
    }

    func testCompactAboutRemainsAtSettingsRoot() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        XCTAssertTrue(section("screensNavigation", in: app).exists)
        XCTAssertTrue(app.staticTexts["Trakt, Simkl, AniList, MyAnimeList, Last.fm"].exists)
        XCTAssertFalse(section("about", in: app).exists)
        let version = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Version ")).firstMatch
        try focus(version, in: app)
        let summary = app.descendants(matching: .any).matching(identifier: "settings-about-summary").firstMatch
        XCTAssertTrue(summary.exists)
        XCTAssertLessThanOrEqual(summary.frame.height, 400, "About should remain a compact root summary.")
        let attributions = app.buttons["Attributions"]
        try focus(attributions, in: app)
        capture("about-inline", in: app)
        let discord = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Scan to join the Plozz Discord community")
        ).firstMatch
        let github = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Scan to view the Plozz GitHub repository")
        ).firstMatch
        XCTAssertTrue(discord.exists)
        XCTAssertTrue(github.exists)
        XCTAssertEqual(discord.frame.minY, github.frame.minY, accuracy: 1)
        XCTAssertEqual(discord.frame.height, github.frame.height, accuracy: 1)
        XCTAssertEqual(discord.frame.width, github.frame.width, accuracy: 1)
        XCTAssertLessThanOrEqual(github.frame.height, 180, "The QR code must not wrap below its caption.")
        XCUIRemote.shared.press(.select)
        let back = pageBack("settings-category-back", in: app)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        assertInlineSettingsHeader("Attributions", back: back, in: app)
        XCUIRemote.shared.press(.menu)
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.hasFocus(attributions) }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        try focus(section("playback", in: app), in: app)
        #else
        throw XCTSkip("Never seeds or changes settings on a physical device.")
        #endif
    }

    func testAppearancePagesAndNavigationStyleChanges() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        defer { capture("appearance-final-state", in: app) }
        try focus(section("appearance", in: app), in: app)
        XCUIRemote.shared.press(.select)
        assertInlineSettingsHeader("Appearance", back: pageBack("settings-category-back", in: app), in: app)
        for id in ["theme", "cards", "artwork", "spoilers", "night-shift"] {
            XCTAssertTrue(app.buttons["settings-page-\(id)"].exists)
        }
        for id in ["display-size", "navigation", "music-player", "title-details", "customize-home"] {
            XCTAssertFalse(app.buttons["settings-page-\(id)"].exists)
        }
        let cards = app.buttons["settings-page-cards"]
        let artwork = app.buttons["settings-page-artwork"]
        XCTAssertEqual(artwork.frame.minY - cards.frame.maxY, 8, accuracy: 1)
        let theme = app.buttons["settings-page-theme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5), app.debugDescription)
        try focus(theme, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Gradient Backgrounds"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Liquid Glass")).firstMatch.exists,
                      app.debugDescription)
        capture("theme", in: app)
        assertCenteredSettingsColumn(in: app)
        XCUIRemote.shared.press(.menu)
        waitForEnabled(theme)
        try focus(app.buttons["settings-page-artwork"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["artwork-customization"].waitForExistence(timeout: 5))
        capture("artwork", in: app)
        try focus(app.buttons["artwork-customization"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["view-customization-back"].waitForExistence(timeout: 5), app.debugDescription)
        assertInlineSettingsHeader("Artwork by view", back: pageBack("view-customization-back", in: app), in: app)
        capture("artwork-customization", in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["artwork-customization"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        try focus(app.buttons["settings-page-cards"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Default"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["DISPLAY SIZE"].waitForExistence(timeout: 5), app.debugDescription)
        let cardHeadings = ["Labels", "Watched Indicator", "Focus", "Style", "Display Size"].map {
            app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", $0)).firstMatch
        }
        XCTAssertTrue(cardHeadings.allSatisfy(\.exists))
        let cardPositions = cardHeadings.map(\.frame.minY)
        XCTAssertEqual(cardPositions, cardPositions.sorted(), "Display Size must be the final Cards group.")
        capture("cards-top", in: app)
        try focus(app.buttons["Default"], in: app)
        capture("display-size", in: app)
        XCTAssertTrue(app.buttons["card-label-customization"].waitForExistence(timeout: 5))
        capture("cards", in: app)
        try focus(app.buttons["card-label-customization"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["view-customization-back"].waitForExistence(timeout: 5), app.debugDescription)
        assertInlineSettingsHeader("Labels by view", back: pageBack("view-customization-back", in: app), in: app)
        capture("card-label-customization", in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["card-label-customization"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        for (page, heading) in [("spoilers", "Spoiler Protection"), ("night-shift", "Circadian Mode")] {
            let link = app.buttons["settings-page-\(page)"]
            try focus(link, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 5), app.debugDescription)
            capture(page, in: app)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
        }
        XCUIRemote.shared.press(.menu)
        waitForCategoryFocus("appearance", in: app)
        try focus(section("screensNavigation", in: app), in: app)
        XCUIRemote.shared.press(.select)
        assertInlineSettingsHeader("Screens & Navigation", back: pageBack("settings-category-back", in: app), in: app)
        for id in ["customize-home", "navigation", "title-details", "music-player"] {
            XCTAssertTrue(app.buttons["settings-page-\(id)"].exists)
        }
        XCTAssertFalse(app.buttons["settings-page-cards"].exists)
        capture("screens-navigation", in: app)
        let home = app.buttons["settings-page-customize-home"]
        try focus(home, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["home-section-hero"].waitForExistence(timeout: 5), app.debugDescription)
        capture("customize-home", in: app)
        assertCenteredSettingsColumn(in: app)
        try focus(app.buttons["home-section-home-continueWatching"], in: app)
        XCUIRemote.shared.press(.select)
        capture("home-rows", in: app)
        assertCenteredSettingsColumn(in: app)
        XCUIRemote.shared.press(.menu)
        waitForEnabled(app.buttons["home-section-home-continueWatching"])
        XCUIRemote.shared.press(.menu)
        waitForEnabled(home)
        XCTAssertTrue(hasFocus(home))
        try focus(app.buttons["settings-page-navigation"], in: app)
        XCUIRemote.shared.press(.select)
        for style in ["Top Bar", "Sidebar", "Pinned Sidebar"] {
            let choice = app.buttons[style]
            XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
            try focus(choice, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["Prevent Accidental Exit"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(section("screensNavigation", in: app).exists)
            capture("navigation-\(style)", in: app)
        }
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["settings-page-navigation"].waitForExistence(timeout: 5), app.debugDescription)
        for (page, heading) in [
            ("music-player", "Music Player"),
            ("title-details", "Detail Page")
        ] {
            let link = app.buttons["settings-page-\(page)"]
            try focus(link, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 5), app.debugDescription)
            capture(page, in: app)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
        }
        XCUIRemote.shared.press(.menu)
        waitForCategoryFocus("screensNavigation", in: app)
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testNativeSidebarAndTopBarEntryAndExit() throws {
        #if targetEnvironment(simulator)
        for style in ["sidebar", "tabBar"] {
            let app = try launchSettings(style: style)
            XCTAssertTrue(section("playback", in: app).isSelected)
            capture("entry-\(style)", in: app)
            try enterAndReturn("playback", in: app)
            XCUIRemote.shared.press(.menu)
            XCTAssertFalse(section("playback", in: app).exists, app.debugDescription)
            capture("exit-\(style)", in: app)
            try openSettingsIfNeeded(in: app)
            try enterAndReturn("playback", in: app)
            app.terminate()
        }
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testRootCategoriesOnlyStaySelectedWhileFocused() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        defer { app.terminate() }
        let playback = section("playback", in: app)
        for identifier in ["settings-profile-switch", "settings-profile-edit"] {
            try focus(playback, in: app)
            XCTAssertTrue(playback.isSelected)
            try focus(app.buttons[identifier], in: app)
            XCTAssertFalse(playback.isSelected, "Remembering Playback for Back must not keep it highlighted.")
            capture("selection-\(identifier)", in: app)
        }
        try focus(playback, in: app)
        try enterAndReturn("playback", in: app)
        XCTAssertTrue(playback.isSelected)

        let language = section("language", in: app)
        try focus(language, in: app)
        XCTAssertTrue(language.isSelected)
        try focus(app.buttons["settings-profile-switch"], in: app)
        XCTAssertFalse(language.isSelected, "Native menu rows must release their selected state too.")

        let help = section("help", in: app)
        try focus(help, in: app)
        try enterAndReturn("help", in: app)
        XCTAssertTrue(help.isSelected)
        try focus(app.buttons.containing(.staticText, identifier: "Attributions").firstMatch, in: app)
        XCTAssertFalse(help.isSelected)
        XCTAssertFalse(playback.isSelected)
        capture("selection-after-help", in: app)
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testProfileEditorAndSwitcherShareTheWorkspace() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        try focus(app.buttons["settings-profile-edit"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["How this profile looks, and who can open it."].waitForExistence(timeout: 5))
        capture("profile-edit", in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(section("playback", in: app).waitForExistence(timeout: 5))
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.buttons["settings-profile-switch"].isEnabled }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed, app.debugDescription)
        try focus(app.buttons["settings-profile-switch"], in: app)
        XCUIRemote.shared.press(.select)
        let sam = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "Sam")).firstMatch
        XCTAssertTrue(sam.waitForExistence(timeout: 5), app.debugDescription)
        capture("profile-switcher", in: app)
        try focus(sam, in: app)
        XCUIRemote.shared.press(.select)
        try openSettingsIfNeeded(in: app)
        XCTAssertEqual(app.buttons["settings-profile-switch"].value as? String, "Sam")
        XCTAssertTrue(section("playback", in: app).isSelected)
        capture("profile-switched", in: app)
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testProfileAppearanceAndPINUseFullWidthDestinations() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(style: "tabBar")
        try focus(app.buttons["settings-profile-edit"], in: app)
        XCUIRemote.shared.press(.select)
        let appearance = app.buttons["profile.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5), app.debugDescription)
        try focus(appearance, in: app)
        XCUIRemote.shared.press(.select)
        let heading = app.staticTexts["Edit Profile"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertLessThan(heading.frame.height, 90, "The editor heading must stay on one line.")
        XCTAssertGreaterThan(heading.frame.width, 200)
        let done = app.buttons["Done"]
        // Cross into the editor column before the single-column vertical navigation helper.
        XCUIRemote.shared.press(.right)
        try focus(done, in: app)
        XCTAssertTrue(app.frame.contains(done.frame), "The editor actions must fit on screen.")
        capture("profile-appearance-full-width", in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(appearance.waitForExistence(timeout: 5), app.debugDescription)
        let lock = app.buttons["profile.lock"]
        try focus(lock, in: app)
        XCUIRemote.shared.press(.select)
        let pinTitle = app.staticTexts["pin-entry-title"]
        XCTAssertTrue(pinTitle.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertLessThan(pinTitle.frame.minX, app.frame.midX - 400,
                          "PIN prose must start in the left half of a centered two-column composition.")
        try focus(app.buttons["1"], in: app)
        capture("profile-lock-full-width", in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(lock.waitForExistence(timeout: 5), app.debugDescription)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(section("playback", in: app).waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testKidsSettingsRequirePINOnlyWhenConfigured() throws {
        #if targetEnvironment(simulator)
        for mode in ["no-pin", "pin"] {
            let app = try launchSettings(profile: "Sam", kids: mode)
            XCTAssertFalse(section("servers", in: app).exists)
            XCTAssertFalse(section("metadata", in: app).exists)
            capture("kids-\(mode)", in: app)
            for personal in ["appearance", "screensNavigation", "language"] {
                XCTAssertTrue(section(personal, in: app).exists)
            }
            for household in ["metadata", "servers", "profile", "parentalPIN", "seerr", "syncSetup"] {
                XCTAssertFalse(section(household, in: app).exists)
            }
            try focus(section("screensNavigation", in: app), in: app)
            try enterAndReturn("screensNavigation", in: app)
            try focus(section("myLibraries", in: app), in: app)
            XCUIRemote.shared.press(.select)
            if mode == "pin" {
                XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 5), app.debugDescription)
                let keypadFocused = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in self.hasFocus(app.buttons["1"]) }, object: nil
                )
                XCTAssertEqual(XCTWaiter.wait(for: [keypadFocused], timeout: 5), .completed,
                               "The PIN page must take native focus before Menu can cancel it.")
                capture("kids-pin-required", in: app)
                XCUIRemote.shared.press(.menu)
                waitForCategoryFocus("myLibraries", in: app)
                XCUIRemote.shared.press(.select)
                for digit in ["1", "2", "3", "4"] {
                    try focus(app.buttons[digit], in: app)
                    XCUIRemote.shared.press(.select)
                }
                let unlocked = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in !app.buttons["1"].exists }, object: nil
                )
                XCTAssertEqual(XCTWaiter.wait(for: [unlocked], timeout: 5), .completed, app.debugDescription)
                XCTAssertTrue(app.buttons["settings-category-back"].exists, "Unlock must stay in the category.")
                XCTAssertFalse(section("myLibraries", in: app).exists)
                capture("kids-unlocked", in: app)
            } else {
                XCTAssertTrue(app.buttons["settings-category-back"].waitForExistence(timeout: 5))
            }
            XCTAssertFalse(section("metadata", in: app).exists)
            XCTAssertFalse(section("servers", in: app).exists)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(section("playback", in: app).waitForExistence(timeout: 5))
            XCTAssertFalse(section("metadata", in: app).exists)
            XCTAssertFalse(section("servers", in: app).exists)
            app.terminate()
        }
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testTrackersHideUnreleasedWetrakr() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(style: "tabBar")
        try focus(section("integrations", in: app), in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["settings-page-trakt"].waitForExistence(timeout: 5), app.debugDescription)
        for tracker in ["trakt", "simkl", "anilist", "mal", "lastfm"] {
            XCTAssertTrue(app.buttons["settings-page-\(tracker)"].exists, app.debugDescription)
        }
        XCTAssertFalse(app.buttons["settings-page-wetrakr"].exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["WeTrakr"].exists, app.debugDescription)
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testPlaybackLiveTVAndTrackerChildPages() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(style: "tabBar")
        for (category, pages) in [
            ("playback", []),
            ("liveTV", ["sources", "hidden-channels"]),
            ("integrations", ["trakt", "simkl", "anilist", "mal", "lastfm"])
        ] {
            try focus(section(category, in: app), in: app)
            XCUIRemote.shared.press(.select)
            if category == "playback" {
                let separate = app.switches["Set each marker separately"]
                XCTAssertTrue(separate.waitForExistence(timeout: 5), app.debugDescription)
                XCTAssertFalse(app.buttons["settings-page-skip-intros-mode"].exists)
                try focus(separate, in: app)
                let community = app.switches["Use community markers"]
                XCTAssertTrue(community.exists, app.debugDescription)
                try focus(community, in: app)
                capture("playback-inline-skip-controls", in: app)
            }
            for page in pages {
                let link = app.buttons["settings-page-\(page)"]
                XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
                try focus(link, in: app)
                XCUIRemote.shared.press(.select)
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Back"))
                    .firstMatch.waitForExistence(timeout: 5), app.debugDescription)
                capture("child-\(page)", in: app)
                XCUIRemote.shared.press(.menu)
                XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
            }
            for _ in 0..<9 { XCUIRemote.shared.press(.down) }
            capture("lower-\(category)", in: app)
            XCUIRemote.shared.press(.menu)
        }
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testUninstrumentedSettingsEntry() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(diagnostics: false)
        try enterAndReturn("playback", in: app)
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testHomeSectionEditorKeepsHeroFixedAndUsesNativeBack() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        defer { app.terminate() }
        try focus(section("screensNavigation", in: app), in: app)
        XCUIRemote.shared.press(.select)
        try focus(app.buttons["settings-page-customize-home"], in: app)
        XCUIRemote.shared.press(.select)
        let hero = app.buttons["home-section-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5), app.debugDescription)
        try focus(hero, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Home layout"].waitForExistence(timeout: 5))
        try focus(app.buttons["Showcase"], in: app)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.menu)
        waitForEnabled(hero)
        XCTAssertEqual(hero.label, "Home layout: Showcase")
        XCTAssertFalse(app.staticTexts["Pinned at top"].exists)
        try focus(hero, in: app)
        XCUIRemote.shared.press(.select)
        try focus(app.buttons["Fullscreen Hero"], in: app)
        XCUIRemote.shared.press(.select)
        let enabledHero = app.switches["hero-enabled"]
        try focus(enabledHero, in: app)
        if enabledHero.value as? String != "1" { XCUIRemote.shared.press(.select) }
        XCUIRemote.shared.press(.menu)
        waitForEnabled(hero)
        XCTAssertEqual(hero.label, "Home layout: Hero")
        XCTAssertFalse(app.staticTexts["Pinned at top"].exists)
        capture("home-hero-pin", in: app)
        let heroY = hero.frame.minY
        let reorder = app.buttons["home-section-reorder"]
        let preset = app.buttons["home-row-preset"]
        XCTAssertGreaterThanOrEqual(preset.frame.minY - reorder.frame.maxY, 16)
        XCTAssertGreaterThanOrEqual(hero.frame.minY - preset.frame.maxY, 16)
        try focus(reorder, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(hero.isEnabled)
        XCTAssertFalse(app.staticTexts["Pinned at top"].exists)
        XCTAssertEqual(hero.label, "Home layout: Hero")
        capture("home-hero-pin-reordering", in: app)
        XCTAssertFalse(app.staticTexts["HIDDEN"].exists)
        let watching = app.buttons.containing(.staticText, identifier: "Continue Watching").firstMatch
        try focus(watching, in: app)
        let originalY = watching.frame.minY
        let watchlist = app.buttons.containing(.staticText, identifier: "Watchlist").firstMatch
        let movingUp = originalY > watchlist.frame.minY
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(movingUp ? .up : .down)
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                watching.exists && self.hasFocus(watching)
                    && (movingUp ? watching.frame.minY < originalY : watching.frame.minY > originalY)
            }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed, app.debugDescription)
        XCUIRemote.shared.press(.select)
        waitForEnabled(reorder)
        try focus(reorder, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(hero.isEnabled)
        XCTAssertFalse(app.staticTexts["Pinned at top"].exists)
        XCTAssertEqual(hero.frame.minY, heroY, accuracy: 1)
        let configured = app.buttons["home-section-home-continueWatching"]
        try focus(configured, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["home-section-remove"].waitForExistence(timeout: 5), app.debugDescription)
        capture("home-section-continue-watching", in: app)
        XCUIRemote.shared.press(.menu)
        waitForEnabled(configured)
        XCTAssertTrue(hasFocus(configured), "Back must restore the section that opened its configuration.")
        try focus(reorder, in: app)
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(hasFocus(pageBack("settings-workspace-back", in: app)), app.debugDescription)
        capture("home-section-header-back", in: app)
        let watchingWasBelowWatchlist = configured.frame.minY > app.buttons["home-section-home-watchlist"].frame.minY
        XCTAssertEqual(preset.value as? String, "Custom")
        try focus(preset, in: app)
        XCUIRemote.shared.press(.select)
        let combinedOption = app.cells.containing(.other, identifier: "Combined rows").firstMatch
        XCTAssertTrue(combinedOption.waitForExistence(timeout: 5), app.debugDescription)
        try focus(combinedOption, in: app)
        XCUIRemote.shared.press(.select)
        let confirmation = app.sheets["Replace your row arrangement?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), app.debugDescription)
        try focus(confirmation.buttons.matching(identifier: "Cancel").firstMatch, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
        XCTAssertTrue(configured.exists)
        XCTAssertEqual(configured.frame.minY > app.buttons["home-section-home-watchlist"].frame.minY, watchingWasBelowWatchlist)
        try focus(preset, in: app)
        XCUIRemote.shared.press(.select)
        try focus(combinedOption, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), app.debugDescription)
        try focus(confirmation.buttons.matching(identifier: "Combined rows").firstMatch, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home-section-home-recentlyAdded"].waitForExistence(timeout: 5))
        for identifier in ["home-section-add", "home-section-add-bottom"] {
            let add = app.buttons[identifier]
            try focus(add, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["Add section"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(reorder.exists)
            XCUIRemote.shared.press(.menu)
            waitForEnabled(add)
            XCTAssertTrue(hasFocus(add))
        }
        #else
        throw XCTSkip("Simulator-only Home editor navigation.")
        #endif
    }

    func testHomeReorderAcceptsHeldAndRapidDirectionalInput() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        defer { app.terminate() }
        try focus(section("screensNavigation", in: app), in: app)
        XCUIRemote.shared.press(.select)
        try focus(app.buttons["settings-page-customize-home"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["home-section-home-continueWatching"].waitForExistence(timeout: 5))
        let controls: Set<String> = [
            "home-section-hero", "home-section-reorder", "home-section-add", "home-section-add-bottom"
        ]
        let count = app.buttons.allElementsBoundByIndex.filter {
            $0.identifier.hasPrefix("home-section-") && !controls.contains($0.identifier)
        }.count
        XCTAssertGreaterThan(count, 2)
        let reorder = app.buttons["home-section-reorder"]
        try focus(reorder, in: app)
        XCUIRemote.shared.press(.select)
        let watching = app.buttons.containing(.staticText, identifier: "Continue Watching").firstMatch
        try focus(watching, in: app)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.down, forDuration: 3)
        capture("home-reorder-held-down", in: app)
        XCTAssertTrue(watching.staticTexts[String(count)].exists,
                      "Holding Down must move the lifted row all the way to the bottom. \(app.debugDescription)")
        XCTAssertTrue(hasFocus(watching))
        XCUIRemote.shared.press(.up, forDuration: 3)
        capture("home-reorder-held-up", in: app)
        XCTAssertTrue(watching.staticTexts["1"].exists,
                      "Holding Up must reach the top without reversing direction. \(app.debugDescription)")
        XCTAssertTrue(hasFocus(watching))
        let moves = min(3, count - 1)
        for _ in 0..<moves { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(watching.staticTexts[String(moves + 1)].exists, app.debugDescription)
        for _ in 0..<moves { XCUIRemote.shared.press(.up) }
        XCTAssertTrue(watching.staticTexts["1"].exists, app.debugDescription)
        XCTAssertTrue(hasFocus(watching))
        XCUIRemote.shared.press(.select)
        waitForEnabled(reorder)
        func menuAction(_ title: String) throws {
            XCUIRemote.shared.press(.select, forDuration: 1)
            let action = app.cells.containing(.other, identifier: title).firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 3), app.debugDescription)
            try focus(action, in: app)
            XCUIRemote.shared.press(.select)
        }
        for (title, rank) in [("Move to bottom", count), ("Move to top", 1)] {
            try menuAction(title)
            let followed = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in watching.staticTexts[String(rank)].exists && self.hasFocus(watching) },
                object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [followed], timeout: 3), .completed, app.debugDescription)
        }
        try menuAction("Remove section")
        XCTAssertTrue(watching.waitForNonExistence(timeout: 3), app.debugDescription)
        XCTAssertFalse(app.staticTexts["HIDDEN"].exists)
        waitForEnabled(reorder)
        try focus(reorder, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(app.buttons["home-section-home-continueWatching"].exists)
        try focus(app.buttons["home-section-add"], in: app)
        XCUIRemote.shared.press(.select)
        let addWatching = app.buttons["home-add-home-continueWatching"]
        XCTAssertTrue(addWatching.waitForExistence(timeout: 3), app.debugDescription)
        try focus(addWatching, in: app)
        XCUIRemote.shared.press(.select)
        let restored = app.buttons["home-section-home-continueWatching"]
        XCTAssertTrue(restored.waitForExistence(timeout: 3), app.debugDescription)
        try focus(restored, in: app)
        try menuAction("Remove section")
        XCTAssertTrue(restored.waitForNonExistence(timeout: 3))
        try focus(app.buttons["home-section-add"], in: app)
        XCUIRemote.shared.press(.select)
        try focus(addWatching, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(restored.waitForExistence(timeout: 3), app.debugDescription)
        #else
        throw XCTSkip("Simulator-only Home reorder input regression.")
        #endif
    }

    func testHeldReorderScrollsLongListsAndCrossesVisibilityDivider() throws {
        #if targetEnvironment(simulator)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PLOZZ_SETTINGS_REVIEW"] == "1")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        defer { app.terminate() }
        for allowsHiding in [false, true] {
            app.launchArguments = ["--reorder-input-fixture"] + (allowsHiding ? ["--with-hidden-rows"] : [])
            app.launch()
            let row = app.buttons.containing(.staticText, identifier: "Row 0").firstMatch
            try focus(row, in: app)
            XCUIRemote.shared.press(.select)
            XCUIRemote.shared.press(.down, forDuration: 4)
            let position = app.staticTexts["reorder-fixture-position"]
            XCTAssertEqual(position.label, "Position \(allowsHiding ? 25 : 23); hidden \(allowsHiding)")
            func positions() throws -> [Int] {
                let value = try XCTUnwrap(position.value as? String)
                return try value.split(separator: ",").map { try XCTUnwrap(Int($0)) }
            }
            let downward = try positions()
            XCTAssertEqual(downward, Array(1...23) + (allowsHiding ? [23, 24, 25] : []),
                           "Every delivered move must advance, never bounce or skip a row.")
            XCTAssertTrue(hasFocus(row), app.debugDescription)
            XCTAssertTrue(row.isHittable)
            XCTAssertGreaterThan(row.frame.minY, 0)
            XCTAssertLessThan(row.frame.maxY, app.frame.maxY)
            capture("long-reorder-bottom-hidden-\(allowsHiding)", in: app)
            XCUIRemote.shared.press(.up, forDuration: 4)
            XCTAssertEqual(position.label, "Position 0; hidden false")
            let upward = Array(try positions().dropFirst(downward.count))
            XCTAssertEqual(upward, (allowsHiding ? [24, 23] : []) + Array((0...23).reversed().dropFirst(allowsHiding ? 0 : 1)))
            XCTAssertTrue(hasFocus(row), app.debugDescription)
            XCTAssertTrue(row.isHittable)
            capture("long-reorder-top-hidden-\(allowsHiding)", in: app)
            XCUIRemote.shared.press(.down, forDuration: 0.7)
            let releasedPosition = position.label
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            XCTAssertEqual(position.label, releasedPosition, "Repetition must stop when the button is released.")
            XCUIRemote.shared.press(.up, forDuration: 4)
            XCUIRemote.shared.press(.select)
            XCUIRemote.shared.press(.down)
            XCTAssertTrue(hasFocus(app.buttons.containing(.staticText, identifier: "Row 1").firstMatch))
            app.terminate()
        }
        #else
        throw XCTSkip("Task-owned simulator input fixture.")
        #endif
    }

    func testHeroRandomAndDiscoverySourcesKeepSettingsResponsive() throws {
        #if targetEnvironment(simulator)
        func openSources(in app: XCUIApplication) throws {
            try focus(section("screensNavigation", in: app), in: app)
            XCUIRemote.shared.press(.select)
            try focus(app.buttons["settings-page-customize-home"], in: app)
            XCUIRemote.shared.press(.select)
            try focus(app.buttons["home-section-hero"], in: app)
            XCUIRemote.shared.press(.select)
            try focus(app.buttons["Fullscreen Hero"], in: app)
            XCUIRemote.shared.press(.select)
            try focus(app.buttons["hero-settings-titles"], in: app)
            XCUIRemote.shared.press(.select)
        }

        var app = try launchSettings()
        defer { app.terminate() }
        try openSources(in: app)

        let random = app.switches["Random from Library"]
        let discovery = app.switches["Discovery"]
        for source in [random, discovery] {
            try focus(source, in: app)
            if source.value as? String == "1" { XCUIRemote.shared.press(.select) }
            XCTAssertEqual(source.value as? String, "0")
        }
        for source in [random, discovery] {
            try focus(source, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertEqual(source.value as? String, "1")
            XCTAssertTrue(hasFocus(source), app.debugDescription)
        }
        capture("hero-random-and-discovery-enabled", in: app)
        let providers = app.buttons["hero-settings-discovery"]
        for visit in 0..<3 {
            try focus(providers, in: app)
            XCUIRemote.shared.press(.select)
            let labels = app.switches["Show provider labels"]
            XCTAssertTrue(labels.waitForExistence(timeout: 5), app.debugDescription)
            try focus(labels, in: app)
            let previous = labels.value as? String
            XCUIRemote.shared.press(.select)
            XCTAssertNotEqual(labels.value as? String, previous)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(providers.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(hasFocus(providers), app.debugDescription)
            if visit == 0 {
                XCUIRemote.shared.press(.menu)
                let sources = app.buttons["hero-settings-titles"]
                XCTAssertTrue(sources.waitForExistence(timeout: 5))
                try focus(sources, in: app)
                XCUIRemote.shared.press(.select)
            }
        }

        app.terminate()
        // Use native top-bar entry after relaunch; the fixture leaves Hero preferences intact.
        app = try launchSettings(style: "tabBar")
        try openSources(in: app)
        for title in ["Random from Library", "Discovery"] {
            XCTAssertEqual(app.switches[title].value as? String, "1", "The enabled sources must survive restart.")
        }
        let restoredDiscovery = app.switches["Discovery"]
        try focus(restoredDiscovery, in: app)
        for value in ["0", "1"] {
            XCUIRemote.shared.press(.select)
            XCTAssertEqual(restoredDiscovery.value as? String, value)
            XCTAssertTrue(hasFocus(restoredDiscovery), app.debugDescription)
        }
        let restoredProviders = app.buttons["hero-settings-discovery"]
        try focus(restoredProviders, in: app)
        XCUIRemote.shared.press(.select)
        let labels = app.switches["Show provider labels"]
        XCTAssertTrue(labels.waitForExistence(timeout: 5), app.debugDescription)
        try focus(labels, in: app)
        let previous = labels.value as? String
        XCUIRemote.shared.press(.select)
        XCTAssertNotEqual(labels.value as? String, previous)
        XCUIRemote.shared.press(.menu)
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.hasFocus(restoredProviders) }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed, app.debugDescription)
        #else
        throw XCTSkip("Simulator-only Hero source investigation.")
        #endif
    }

    func testHeroEditorsRemainInsideTheSettingsPane() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        try focus(section("screensNavigation", in: app), in: app)
        XCUIRemote.shared.press(.select)
        try focus(app.buttons["settings-page-customize-home"], in: app)
        XCUIRemote.shared.press(.select)
        let hero = app.buttons["home-section-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        try focus(hero, in: app)
        XCUIRemote.shared.press(.select)
        let fullscreen = app.buttons["Fullscreen Hero"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))
        try focus(fullscreen, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["hero-settings-titles"].waitForExistence(timeout: 5))
        capture("hero", in: app)
        for label in ["Items to show", "Seconds per item"] {
            let stepper = app.buttons[label]
            try focus(stepper, in: app)
            XCTAssertGreaterThan(stepper.frame.width, 700)
            let title = app.staticTexts[label].firstMatch
            let peer = app.staticTexts["Hide watched content"].firstMatch
            XCTAssertEqual(title.frame.minX, peer.frame.minX, accuracy: 1)
            XCTAssertEqual(title.frame.height, peer.frame.height, accuracy: 1)
            let original = try XCTUnwrap(stepper.value as? String)
            XCUIRemote.shared.press(.right)
            XCTAssertNotEqual(stepper.value as? String, original)
            XCTAssertTrue(stepper.hasFocus)
            XCUIRemote.shared.press(.left)
            XCTAssertEqual(stepper.value as? String, original)
            capture("hero-stepper-\(label)", in: app)
        }
        for (page, content) in [
            ("titles", "Hero content sources"), ("ratings", "Ratings"), ("trailers", "Trailers")
        ] {
            let link = app.buttons["hero-settings-\(page)"]
            try focus(link, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["view-customization-back"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[content].exists)
            capture("hero-\(page)", in: app)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(link.waitForExistence(timeout: 5))
        }
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testCircadianSteppersKeepWholeRowFocusAndRestoreValues() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        try focus(section("appearance", in: app), in: app)
        XCUIRemote.shared.press(.select)
        try focus(app.buttons["settings-page-night-shift"], in: app)
        XCUIRemote.shared.press(.select)
        try focus(app.buttons["Manual"], in: app)
        XCUIRemote.shared.press(.select)
        for label in ["Turns on", "Turns off", "Fade", "Darkness", "Warmth"] {
            let stepper = app.buttons[label]
            try focus(stepper, in: app)
            XCTAssertGreaterThan(stepper.frame.width, 700)
            let original = try XCTUnwrap(stepper.value as? String)
            XCUIRemote.shared.press(.right)
            XCTAssertNotEqual(stepper.value as? String, original)
            XCTAssertTrue(stepper.hasFocus)
            XCUIRemote.shared.press(.left)
            XCTAssertEqual(stepper.value as? String, original)
            capture("circadian-stepper-\(label)", in: app)
        }
        try focus(app.buttons["Always On"], in: app)
        XCUIRemote.shared.press(.up)
        let back = pageBack(in: app)
        let headerFocused = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.hasFocus(back) }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [headerFocused], timeout: 5), .completed,
                       "Up from the rightmost mode must reach Back across the full header width.")
        capture("circadian-header-back", in: app)
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.select)
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !app.buttons["Darkness"].exists }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed,
                       "Restore the fixture before later visual checks.")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["settings-page-night-shift"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testCompactIPTVSourcesAndChildBackNavigation() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(style: "tabBar", sources: true)
        defer { capture("compact-final-state", in: app) }
        try focus(section("metadata", in: app), in: app)
        XCUIRemote.shared.press(.select)
        let recommended = app.buttons["Recommended"]
        XCTAssertTrue(recommended.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertLessThanOrEqual(recommended.frame.height, 66)
        capture("compact-metadata-options", in: app)
        XCUIRemote.shared.press(.menu)
        try focus(section("liveTV", in: app), in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertLessThan(
            app.staticTexts["Preview the focused channel as you browse."].firstMatch.frame.height,
            app.staticTexts["Auto preview"].firstMatch.frame.height,
            "Helper text must render smaller than the control label, not just use a different text style."
        )
        capture("compact-guide-settings", in: app)
        try focus(app.buttons["settings-page-sources"], in: app)
        XCUIRemote.shared.press(.select)
        let first = app.buttons["live-tv-source-details-settings-review-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        for index in 0..<6 {
            let row = app.buttons["live-tv-source-details-settings-review-\(index)"]
            XCTAssertTrue(row.exists)
            XCTAssertLessThanOrEqual(row.frame.height, 110, "Sources must be compact summary rows.")
        }
        XCTAssertFalse(app.buttons["live-tv-remove-source-settings-review-0"].exists)
        capture("compact-iptv-sources", in: app)
        try focus(app.buttons["live-tv-add-server"], in: app)
        capture("iptv-sources-scrolled", in: app)
        let detailScroll = try XCTUnwrap(app.scrollViews.allElementsBoundByIndex.first {
            $0.buttons["live-tv-add-server"].exists
        })
        XCTAssertLessThanOrEqual(detailScroll.frame.minY, 1, "The scroll viewport must reach the screen edge.")
        let detailMaxX = detailScroll.frame.maxX
        try focus(first, in: app)
        XCUIRemote.shared.press(.select)
        let back = pageBack("live-tv-settings-back", in: app)
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Northstar TV"].exists)
        capture("iptv-source-controls", in: app)
        for link in [
            "live-tv-edit-source-settings-review-0",
            "live-tv-source-guides-settings-review-0"
        ] {
            try focus(app.buttons[link], in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
            if link == "live-tv-source-guides-settings-review-0" {
                for identifier in ["live-tv-guide-lookback", "live-tv-guide-lookahead"] {
                    let menu = app.buttons[identifier]
                    XCTAssertTrue(menu.exists)
                    XCTAssertLessThanOrEqual(menu.frame.maxX, detailMaxX - 28)
                }
            }
            capture(link, in: app)
            try focus(back, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons[link].waitForExistence(timeout: 5), app.debugDescription)
        }
        try focus(back, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(first.waitForExistence(timeout: 5), app.debugDescription)
        #else
        throw XCTSkip("Never seeds sources on a physical device.")
        #endif
    }

    func testSubtitleStyleEditorsExpandAndRestoreTheWorkspace() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(style: "tabBar")
        defer { capture("subtitle-fullscreen-final-state", in: app) }
        try focus(section("subtitles", in: app), in: app)
        XCUIRemote.shared.press(.select)
        let primaryStyle = app.buttons["Customize subtitle style"]
        let styleVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in primaryStyle.exists && primaryStyle.isHittable }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [styleVisible], timeout: 5), .completed,
                       "Subtitle style must be visible near the top without scrolling after the transition.")
        XCTAssertLessThan(primaryStyle.frame.minY, app.staticTexts["Subtitle language"].firstMatch.frame.minY)
        for (title, captureName) in [
            ("Customize subtitle style", "subtitle-style"),
            ("Customize Live TV subtitles", "subtitle-style-live-tv")
        ] {
            if title == "Customize Live TV subtitles", !app.buttons[title].exists {
                let separateStyle = app.switches["Use a separate style for Live TV"]
                try focus(separateStyle, in: app)
                XCUIRemote.shared.press(.select)
            }
            let link = app.buttons[title]
            XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
            try focus(link, in: app)
            capture("\(captureName)-before", in: app)
            XCUIRemote.shared.press(.select)
            let heading = app.staticTexts[title]
            XCTAssertTrue(heading.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(section("subtitles", in: app).exists, app.debugDescription)
            XCTAssertFalse(app.buttons["settings-profile-switch"].exists)
            let back = pageBack(in: app)
            XCTAssertLessThan(back.frame.minX, 200, "The editor must reclaim the sidebar column.")
            let controlColumn = app.scrollViews["subtitle-style-editor-card"]
            XCTAssertTrue(controlColumn.waitForExistence(timeout: 5))
            XCTAssertFalse(controlColumn.buttons["settings-workspace-back"].exists)
            XCTAssertFalse(controlColumn.staticTexts[title].exists)
            let headingAtEntry = heading.frame
            assertInlineSettingsHeader(title, back: back, in: app)
            XCTAssertGreaterThan(controlColumn.frame.minY, heading.frame.maxY)
            XCTAssertFalse(app.staticTexts["Appearance"].exists)
            let preview = app.otherElements["subtitle-style-preview"]
            XCTAssertTrue(preview.exists)
            let previewAtEntry = preview.frame
            XCTAssertTrue(back.exists)
            let editorCard = controlColumn
            XCTAssertTrue(editorCard.exists)
            XCTAssertFalse(editorCard.buttons["settings-workspace-back"].exists,
                           "Page navigation belongs outside the Appearance card.")
            capture(captureName, in: app)
            let font = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Font")).firstMatch
            let matchedSystemStyle = !font.isEnabled
            let matchSystemStyle = app.buttons["Match Apple TV Subtitle Style"]
            if matchedSystemStyle {
                try focus(matchSystemStyle, in: app)
                XCUIRemote.shared.press(.select)
            }
            try focus(font, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["Font"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(section("subtitles", in: app).exists)
            try focus(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "System Fonts")).firstMatch,
                      in: app)
            XCTAssertEqual(heading.frame, headingAtEntry, "Only the editor pane may scroll.")
            XCTAssertEqual(preview.frame.minY, previewAtEntry.minY, accuracy: 1)
            XCTAssertEqual(preview.frame.width, previewAtEntry.width, accuracy: 1)
            XCTAssertEqual(preview.frame.height, previewAtEntry.height, accuracy: 1)
            capture("\(captureName)-fonts", in: app)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(matchSystemStyle.waitForExistence(timeout: 5), app.debugDescription)
            if matchedSystemStyle {
                try focus(matchSystemStyle, in: app)
                XCUIRemote.shared.press(.select)
            }
            let paneBeforePreview = controlColumn.frame
            let previewHeader = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Preview")).firstMatch
            try focus(previewHeader, in: app)
            let expanded = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    app.buttons["HDR preview"].exists
                        && controlColumn.frame.height < paneBeforePreview.height - 100
                }, object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
            XCTAssertEqual(heading.frame, headingAtEntry)
            XCTAssertEqual(preview.frame, previewAtEntry)
            let previewControls = app.otherElements["subtitle-preview-controls"]
            XCTAssertGreaterThan(previewControls.frame.minY, controlColumn.frame.maxY)
            XCTAssertLessThan(previewControls.frame.maxY, app.frame.maxY)
            capture("\(captureName)-preview-expanded", in: app)
            XCUIRemote.shared.press(.select)
            let fullScreenBack = app.buttons["Back"].firstMatch
            XCTAssertTrue(fullScreenBack.waitForExistence(timeout: 5))
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(previewHeader.waitForExistence(timeout: 5))
            try focus(matchSystemStyle, in: app)
            let collapsed = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    abs(controlColumn.frame.height - paneBeforePreview.height) < 1
                }, object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed)
            XCTAssertEqual(heading.frame, headingAtEntry)
            if title == "Customize subtitle style" {
                XCUIRemote.shared.press(.menu)
            } else {
                let back = pageBack(in: app)
                try focus(back, in: app)
                XCUIRemote.shared.press(.select)
            }
            XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(section("subtitles", in: app).exists)
            XCTAssertFalse(app.buttons["settings-profile-switch"].exists)
            XCTAssertTrue(app.buttons["settings-category-back"].exists)
            capture("\(captureName)-returned", in: app)
        }
        XCUIRemote.shared.press(.menu)
        waitForCategoryFocus("subtitles", in: app)
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testDirectionalSteppersAdjustWithoutMovingFocus() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(style: "tabBar")
        defer { capture("directional-steppers-final", in: app) }
        try focus(section("playback", in: app), in: app)
        XCUIRemote.shared.press(.select)
        var trailingEdge: CGFloat?
        for label in ["Time before the end", "Backward", "Forward", "Rewind on resume"] {
            let stepper = app.buttons[label]
            XCTAssertTrue(stepper.waitForExistence(timeout: 5), app.debugDescription)
            try focus(stepper, in: app)
            let initialValue = stepper.value as? String
            XCTAssertNotNil(initialValue)
            let title = app.staticTexts[label].firstMatch
            let labelInsideTarget = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in stepper.frame.contains(title.frame) }, object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [labelInsideTarget], timeout: 3), .completed,
                           "After native scrolling settles, the focus target must contain its label.")
            let initialFrame = stepper.frame
            XCTAssertGreaterThan(initialFrame.width, 800, "The entire Settings row must receive native focus.")
            let peer = app.staticTexts["Show Up Next card"].firstMatch
            XCTAssertEqual(title.frame.minX, peer.frame.minX, accuracy: 1,
                           "Stepper text must align with neighboring setting rows.")
            XCTAssertEqual(title.frame.height, peer.frame.height, accuracy: 1)
            if let trailingEdge {
                XCTAssertEqual(initialFrame.maxX, trailingEdge, accuracy: 2)
            } else {
                trailingEdge = initialFrame.maxX
            }
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(hasFocus(stepper), "Right must adjust rather than move focus.")
            XCTAssertNotEqual(stepper.value as? String, initialValue)
            XCTAssertEqual(stepper.frame.width, initialFrame.width, accuracy: 1)
            XCTAssertEqual(stepper.frame.height, initialFrame.height, accuracy: 1)
            XCTAssertEqual(stepper.frame.minX, initialFrame.minX, accuracy: 1)
            XCUIRemote.shared.press(.left)
            XCTAssertEqual(stepper.value as? String, initialValue)
            XCTAssertTrue(hasFocus(stepper))
            capture("directional-stepper-\(label)", in: app)
            XCUIRemote.shared.press(.down)
            XCTAssertFalse(hasFocus(stepper), "Down must remain native navigation.")
            try focus(stepper, in: app)
            XCUIRemote.shared.press(.up)
            XCTAssertFalse(hasFocus(stepper), "Up must remain native navigation.")
        }
        XCTAssertEqual(
            app.staticTexts["Backward"].firstMatch.frame.height,
            app.staticTexts["Rewind on resume"].firstMatch.frame.height, accuracy: 1
        )
        #else
        throw XCTSkip("Never changes settings on a physical device.")
        #endif
    }

    func testAlignedIdentityHeadersAndCompactDetailPageControls() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(style: "tabBar")
        let profile = app.staticTexts["settings-profile-name"]
        let everyone = app.staticTexts["settings-everyone-name"]
        XCTAssertTrue(profile.exists && everyone.exists, app.debugDescription)
        XCTAssertEqual(profile.frame.minX, everyone.frame.minX, accuracy: 2)
        XCTAssertEqual(profile.frame.height, everyone.frame.height, accuracy: 2)
        XCTAssertLessThanOrEqual(profile.frame.height, 46)
        let avatar = app.descendants(matching: .any).matching(identifier: "settings-profile-avatar").firstMatch
        let scope = app.descendants(matching: .any).matching(identifier: "settings-everyone-icon").firstMatch
        XCTAssertTrue(avatar.exists && scope.exists, app.debugDescription)
        XCTAssertEqual(avatar.frame.width, scope.frame.width, accuracy: 1)
        XCTAssertEqual(avatar.frame.height, scope.frame.height, accuracy: 1)
        XCTAssertEqual(scope.frame.width, 52, accuracy: 1)
        capture("aligned-settings-headers", in: app)
        try focus(section("servers", in: app), in: app)
        capture("everyone-circular-badge-and-divider", in: app)

        try focus(section("screensNavigation", in: app), in: app)
        XCUIRemote.shared.press(.select)
        try focus(app.buttons["settings-page-title-details"], in: app)
        XCUIRemote.shared.press(.select)
        let showScores = app.switches["Show review scores"]
        XCTAssertTrue(showScores.waitForExistence(timeout: 5), app.debugDescription)
        let back = pageBack(in: app)
        XCTAssertTrue(back.exists)
        let scroll = try XCTUnwrap(app.scrollViews.allElementsBoundByIndex.first {
            $0.buttons["settings-workspace-back"].exists
        }, "Back must be inside the page scroll view, not overlaid above it.")
        capture("detail-page-scrolling-back", in: app)
        try focus(showScores, in: app)
        let countLabel = app.staticTexts.matching(NSPredicate(
            format: "label ==[c] %@", "Maximum ratings shown"
        )).firstMatch
        XCTAssertTrue(countLabel.exists, app.debugDescription)
        XCTAssertGreaterThan(countLabel.frame.minY, showScores.frame.maxY)
        XCTAssertLessThanOrEqual(countLabel.frame.minY - showScores.frame.maxY, 40,
                                "Related review-score controls must use the compact shared gap.")
        let countControl = app.buttons["Maximum ratings shown"]
        try focus(countControl, in: app)
        let originalCount = countControl.value as? String
        XCTAssertNotNil(originalCount)
        XCTAssertGreaterThan(countControl.frame.width, 800)
        XCTAssertTrue(countControl.frame.contains(countLabel.frame))
        XCUIRemote.shared.press(originalCount == "10" ? .left : .right)
        XCTAssertNotEqual(countControl.value as? String, originalCount)
        XCTAssertTrue(hasFocus(countControl))
        XCUIRemote.shared.press(originalCount == "10" ? .right : .left)
        XCTAssertEqual(countControl.value as? String, originalCount)
        capture("compact-review-score-controls", in: app)
        let age = app.switches["Show Common Sense age"]
        try focus(age, in: app)
        XCTAssertTrue(scroll.buttons["settings-workspace-back"].exists)
        capture("detail-page-scrolled", in: app)
        try focus(back, in: app)
        capture("detail-page-back-returned", in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["settings-page-title-details"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    private func launchSettings(
        style: String = "rail", profile: String = "Alex", kids: String = "off",
        diagnostics: Bool = false, sources: Bool = false
    ) throws -> XCUIApplication {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PLOZZ_SETTINGS_REVIEW"] == "1",
            "Requires the production app installed on a task-owned simulator."
        )
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz")
        app.launchEnvironment["PLOZZ_SHOTS_SETTINGS"] = "1"
        app.launchEnvironment["PLOZZ_SHOTS_SETTINGS_NAVIGATION"] = style
        app.launchEnvironment["PLOZZ_SHOTS_SETTINGS_KIDS"] = kids
        if sources {
            app.launchEnvironment["PLOZZ_SHOTS_SETTINGS_SOURCES"] = try XCTUnwrap(
                ProcessInfo.processInfo.environment["PLOZZ_SETTINGS_SOURCE_ORIGIN"],
                "Source review requires an owned loopback fixture server."
            )
        }
        if diagnostics { app.launchEnvironment["PLZHFOCUS"] = "1" }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.buttons["Looks good"].waitForExistence(timeout: 2) {
            try focus(app.buttons["Looks good"], in: app)
            XCUIRemote.shared.press(.select)
        }
        try completeAppearanceChoices(in: app)
        let alex = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", profile)).firstMatch
        if alex.waitForExistence(timeout: 2) {
            try focus(alex, in: app)
            XCUIRemote.shared.press(.select)
        }
        try completeAppearanceChoices(in: app)
        let keepPreviewsOff = app.buttons["live-tv-preview-disable"]
        if keepPreviewsOff.waitForExistence(timeout: 2) {
            try focus(keepPreviewsOff, in: app)
            XCUIRemote.shared.press(.select)
        }
        if sources { capture("source-fixture-entry", in: app) }
        try openSettingsIfNeeded(in: app)
        return app
    }

    private func completeAppearanceChoices(in app: XCUIApplication) throws {
        for title in [
            "Choose theme for this profile",
            "Choose navigation for this profile",
            "Choose Home layout for this profile"
        ] {
            if app.staticTexts[title].waitForExistence(timeout: 2) {
                try focus(app.buttons["Continue"], in: app)
                XCUIRemote.shared.press(.select)
            }
        }
    }

    private func openSettingsIfNeeded(in app: XCUIApplication) throws {
        let playback = section("playback", in: app)
        if !playback.waitForExistence(timeout: 3) {
            XCTAssertEqual(app.state, .runningForeground, "Settings navigation requires the actual foreground app.")
            let settings = app.buttons.matching(NSPredicate(
                format: "label IN %@", ["Settings", "Réglages"]
            )).firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
            if !settings.isEnabled {
                XCUIRemote.shared.press(.menu)
                waitForEnabled(settings)
            }
            try focus(settings, in: app, stoppingWhen: { playback.exists })
            if !playback.waitForExistence(timeout: 2) { XCUIRemote.shared.press(.select) }
        }
        XCTAssertTrue(playback.waitForExistence(timeout: 20), app.debugDescription)
        try focus(playback, in: app)
    }

    private func section(_ route: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "settings-section-\(route)")
            .matching(NSPredicate(format: "enabled == true")).firstMatch
    }

    private func waitForCategoryFocus(_ route: String, in app: XCUIApplication) {
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.hasFocus(self.section(route, in: app)) }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed,
                       "Native focus must return after the page transition. \(app.debugDescription)")
    }

    private func enterAndReturn(_ route: String, in app: XCUIApplication, usingRight: Bool = false) throws {
        let selected = section(route, in: app)
        let other = section(route == "playback" ? "subtitles" : "playback", in: app)
        XCUIRemote.shared.press(usingRight ? .right : .select)
        let arrived = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !selected.exists && !other.exists && app.buttons["settings-category-back"].exists
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 4), .completed,
                       "Native focus did not enter \(route). \(app.debugDescription)")
        assertCenteredSettingsColumn(in: app)
        capture("editing-\(route)", in: app)
        if route == "appearance" {
            try focus(app.buttons["settings-page-cards"], in: app)
            capture("appearance-options", in: app)
        }
        if usingRight {
            try focus(app.buttons["settings-category-back"], in: app)
            XCUIRemote.shared.press(.select)
        } else {
            XCUIRemote.shared.press(.menu)
        }
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.hasFocus(selected) && selected.isSelected && other.exists && other.isEnabled },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 4), .completed,
                       "Native focus did not return from \(route). \(app.debugDescription)")
        assertCenteredSettingsColumn(in: app)
    }

    private func waitForEnabled(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in element.exists && element.isEnabled }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    }

    private func assertInlineSettingsHeader(_ title: String, back: XCUIElement, in app: XCUIApplication) {
        let heading = app.staticTexts[title].firstMatch
        let aligned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                heading.exists && back.exists
                    && back.frame.maxX < heading.frame.minX
                    && abs(back.frame.midY - heading.frame.midY) <= 1
            }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [aligned], timeout: 5), .completed,
                       "The shared Back button and title must form one horizontal header. \(app.debugDescription)")
    }

    private func assertCenteredSettingsColumn(in app: XCUIApplication) {
        let scroll = app.scrollViews.allElementsBoundByIndex.first { scroll in
            scroll.isEnabled && scroll.buttons.allElementsBoundByIndex.contains {
                $0.isEnabled && ($0.identifier.hasPrefix("settings-section-")
                    || ["settings-category-back", "settings-workspace-back",
                        "live-tv-settings-back", "view-customization-back"].contains($0.identifier))
            }
        }
        guard let scroll else {
            XCTFail("No current Settings column. \(app.debugDescription)")
            return
        }
        XCTAssertEqual(scroll.frame.width, 960, accuracy: 1, "Every ordinary Settings page shares one width.")
        XCTAssertEqual(scroll.frame.midX, app.frame.midX, accuracy: 1, "Settings pages stay centered.")
    }

    private func focus(
        _ target: XCUIElement, in app: XCUIApplication, stoppingWhen: () -> Bool = { false }
    ) throws {
        guard target.waitForExistence(timeout: 5) else {
            XCTFail("Missing focus target. \(app.debugDescription)")
            return
        }
        var requestedNavigation = false
        var lastDirection: XCUIRemote.Button = .left
        for _ in 0..<35 {
            if stoppingWhen() { return }
            if hasFocus(target) { return }
            let nativeFocused = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true AND enabled == true")).firstMatch
            let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "settings-section-"))
                .allElementsBoundByIndex.first(where: \.isSelected)
            guard let focused = nativeFocused.exists ? nativeFocused : selected else {
                if !requestedNavigation && target.label == "Settings" {
                    XCUIRemote.shared.press(.menu)
                    requestedNavigation = true
                } else {
                    // Single-label SwiftUI buttons can highlight without exposing AX focus.
                    XCUIRemote.shared.press(lastDirection)
                }
                continue
            }
            let from = focused.frame
            let to = target.frame
            let playback = section("playback", in: app)
            let fullWidthSettings = pageBack("settings-category-back", in: app).exists
                || pageBack(in: app).exists || pageBack("live-tv-settings-back", in: app).exists
            let sameDetail = fullWidthSettings
                || (playback.exists && from.minX > playback.frame.maxX && to.minX > playback.frame.maxX)
            if sameDetail && to.maxY <= from.minY {
                lastDirection = .up
            } else if sameDetail && to.minY >= from.maxY {
                lastDirection = .down
            } else if to.minX > from.maxX {
                lastDirection = .right
            } else if to.maxX < from.minX {
                lastDirection = .left
            } else if min(to.maxY, from.maxY) > max(to.minY, from.minY),
                      abs(to.midX - from.midX) > abs(to.midY - from.midY) {
                // Native focus scaling can overlap adjacent cards' horizontal frames.
                lastDirection = to.midX > from.midX ? .right : .left
            } else {
                lastDirection = to.midY < from.midY ? .up : .down
            }
            XCUIRemote.shared.press(lastDirection)
        }
        capture("unreachable-focus-\(target.identifier)", in: app)
        XCTFail("Could not focus \(target.identifier) \(target.label). \(app.debugDescription)")
    }

    private func hasFocus(_ target: XCUIElement) -> Bool {
        guard target.exists, target.isEnabled else { return false }
        return target.hasFocus || target.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists
    }

    private func pageBack(_ identifier: String = "settings-workspace-back", in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: identifier)
            .matching(NSPredicate(format: "enabled == true")).firstMatch
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        // Behavior is asserted separately; let the native animation finish for the image.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "settings-native-\(name)"
        image.lifetime = .keepAlways
        add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "settings-native-\(name)-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
