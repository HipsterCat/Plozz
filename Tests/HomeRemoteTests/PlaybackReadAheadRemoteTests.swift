import XCTest

@MainActor
final class PlaybackReadAheadRemoteTests: XCTestCase {
    func testSDHPreferenceIsAvailableWithoutSubtitleDownloads() {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--read-ahead-settings-fixture", "--subtitle-settings-workspace"]
        app.launch()
        defer { app.terminate() }
        let menu = app.buttons["settings-group-subtitle-sdh"]
        XCTAssertTrue(app.staticTexts["read-ahead-saved"].waitForExistence(timeout: 10))
        for _ in 0..<20 {
            if hasFocus(menu) { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(hasFocus(menu))
        XCTAssertFalse(app.staticTexts["Downloading subtitles"].exists)
        XCTAssertGreaterThan(menu.frame.width, 800)
        XCTAssertEqual(menu.frame.width, app.buttons["Subtitle language"].frame.width, accuracy: 1)
        XCTAssertTrue(menu.isHittable)
        XCUIRemote.shared.press(.select)
        let prefer = app.cells.containing(.any, identifier: "Prefer SDH").firstMatch
        XCTAssertTrue(prefer.waitForExistence(timeout: 5))
        for _ in 0..<5 {
            if prefer.hasFocus { break }
            XCUIRemote.shared.press(.up)
        }
        if !prefer.hasFocus { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(waitUntil { prefer.hasFocus })
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitUntil {
            app.staticTexts["Use SDH when available; otherwise use regular subtitles."].exists
        })
        XCUIRemote.shared.press(.select)
        let strict = app.cells.containing(.any, identifier: "Only SDH").firstMatch
        XCTAssertTrue(strict.waitForExistence(timeout: 5))
        let regular = app.cells.containing(.any, identifier: "Prefer Non-SDH").firstMatch
        for _ in 0..<4 {
            if regular.hasFocus { break }
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(waitUntil { regular.hasFocus })
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitUntil { strict.hasFocus })
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitUntil {
            app.staticTexts["Use only SDH. Leave subtitles off if unavailable."].exists
        })
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "SDH selection for network shares"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFocusOnlyPreviewsAndSelectPersistsAcrossLaunches() {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--read-ahead-settings-fixture", "--reset-read-ahead"]
        app.launch()
        defer { app.terminate() }
        let row = app.buttons["settings-master-read-ahead"]
        XCTAssertTrue(app.staticTexts["read-ahead-saved"].waitForExistence(timeout: 10))
        for _ in 0..<35 {
            if row.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(row.hasFocus)
        XCTAssertTrue(row.label.contains("Video buffer"))
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(app.staticTexts[
            "Larger buffers use more storage. Unavailable with Apple’s native player."
        ].exists)
        let choices = ["Automatic", "1 minute", "5 minutes", "10 minutes", "Maximum available"]
        XCTAssertTrue(waitUntil { choices.contains { app.buttons[$0].hasFocus } })
        // Directional entry follows native geometry; walk to the first choice.
        for _ in 0..<choices.count {
            if app.buttons["Automatic"].hasFocus { break }
            XCTAssertEqual(app.staticTexts["read-ahead-saved"].label, "automatic")
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(waitUntil { app.buttons["Automatic"].hasFocus })
        for title in ["1 minute", "5 minutes", "10 minutes", "Maximum available"] {
            XCUIRemote.shared.press(.down)
            XCTAssertTrue(waitUntil { app.buttons[title].hasFocus })
            XCTAssertEqual(app.staticTexts["read-ahead-saved"].label, "automatic")
        }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitUntil { app.staticTexts["read-ahead-saved"].label == "maximumAvailable" })
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Playback read-ahead maximum"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitUntil { row.hasFocus })
        app.terminate()
        app.launchArguments = ["--read-ahead-settings-fixture"]
        app.launch()
        XCTAssertTrue(app.staticTexts["read-ahead-saved"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["read-ahead-saved"].label, "maximumAvailable")
    }

    private func waitUntil(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        ], timeout: 5) == .completed
    }

    private func hasFocus(_ element: XCUIElement) -> Bool {
        element.exists && (element.hasFocus || element.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists)
    }
}
