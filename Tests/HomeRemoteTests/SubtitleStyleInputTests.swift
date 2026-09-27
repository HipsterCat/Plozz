import XCTest

@MainActor
final class SubtitleStyleInputTests: XCTestCase {
    func testClicksAndHeldDirectionsThroughProductionPlayerInput() throws {
        let app = launchFixture(extra: ["--production-player-input"])
        defer { app.terminate() }
        let subtitles = app.buttons["Subtitles"]
        XCTAssertTrue(subtitles.waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(subtitles.hasFocus)
        XCUIRemote.shared.press(.select)
        let style = app.buttons["Style"]
        XCTAssertTrue(style.waitForExistence(timeout: 5))
        for _ in 0..<4 where !style.hasFocus { XCUIRemote.shared.press(.up) }
        XCTAssertTrue(style.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        let row = try focusTextSize(in: app)
        let value = app.staticTexts["subtitle-text-size-value"]
        let initial = try XCTUnwrap(Int(value.label))
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(row.hasFocus)
        XCTAssertEqual(Int(value.label), initial - 1)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(row.hasFocus)
        XCTAssertEqual(Int(value.label), initial)
        XCUIRemote.shared.press(.right, forDuration: 1)
        let afterRight = try XCTUnwrap(Int(value.label))
        XCTAssertGreaterThan(afterRight, initial + 2)
        XCTAssertTrue(row.hasFocus)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(Int(value.label), afterRight)
        XCUIRemote.shared.press(.left, forDuration: 1)
        let afterLeft = try XCTUnwrap(Int(value.label))
        XCTAssertLessThan(afterLeft, afterRight - 2)
        XCTAssertTrue(row.hasFocus)
        XCUIRemote.shared.press(.up)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(Int(value.label), afterLeft)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Weight")).firstMatch.hasFocus)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(style.waitForExistence(timeout: 5))
    }

    func testHorizontalPressesAdjustTextSizeWithoutFocusingBack() throws {
        let app = launchFixture(extra: ["--nearby-back"])
        defer { app.terminate() }
        let row = try focusTextSize(in: app)
        let value = app.staticTexts["subtitle-text-size-value"]
        let initial = try XCTUnwrap(Int(value.label))
        for index in 1...8 {
            XCUIRemote.shared.press(.left)
            XCTAssertTrue(row.hasFocus, "Left must adjust Text Size, never select the header's Back button.")
            XCTAssertEqual(Int(value.label), initial - index)
        }
        for index in 1...8 {
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(row.hasFocus)
            XCTAssertEqual(Int(value.label), initial - 8 + index)
        }
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Weight")).firstMatch.hasFocus)
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Weight")).firstMatch.hasFocus)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(row.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(Int(value.label), initial + 1)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Position")).firstMatch.hasFocus)
    }

    func testLeftAtMinimumKeepsTextSizeFocused() throws {
        let app = launchFixture(extra: ["--minimum-text-size"])
        defer { app.terminate() }
        let row = try focusTextSize(in: app)
        let value = app.staticTexts["subtitle-text-size-value"]
        let minimum = value.label
        for _ in 0..<6 {
            XCUIRemote.shared.press(.left)
            XCTAssertTrue(row.hasFocus)
            XCTAssertEqual(value.label, minimum)
        }
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(row.hasFocus)
        XCTAssertEqual(Int(value.label), try XCTUnwrap(Int(minimum)) + 1)
    }

    func testRightAtMaximumAndHeldLeftKeepTextSizeFocused() throws {
        let app = launchFixture(extra: ["--maximum-text-size", "--nearby-back"])
        defer { app.terminate() }
        let row = try focusTextSize(in: app)
        let value = app.staticTexts["subtitle-text-size-value"]
        let maximum = try XCTUnwrap(Int(value.label))
        for _ in 0..<6 {
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(row.hasFocus)
            XCTAssertEqual(Int(value.label), maximum)
        }
        XCUIRemote.shared.press(.left, forDuration: 1.5)
        XCTAssertTrue(row.hasFocus)
        XCTAssertLessThan(try XCTUnwrap(Int(value.label)), maximum - 2,
                          "A held click must keep stepping, not act as one tap.")
        let afterHold = try XCTUnwrap(Int(value.label))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(Int(value.label), afterHold, "Releasing the click must stop repeating.")
        for _ in 0..<8 {
            XCUIRemote.shared.press(.left)
            XCTAssertTrue(row.hasFocus)
        }
        XCTAssertLessThanOrEqual(try XCTUnwrap(Int(value.label)), afterHold - 8)
    }

    func testFontSubmenuAndMenuStillNavigateNatively() throws {
        let app = launchFixture()
        defer { app.terminate() }
        _ = try focusTextSize(in: app)
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.up)
        let font = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Font")).firstMatch
        XCTAssertTrue(font.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "OpenDyslexic"
        )).firstMatch.waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(font.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Match Apple TV Subtitle Style"
        )).firstMatch.hasFocus)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(font.hasFocus)
    }

    private func launchFixture(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--subtitle-style-input-fixture"] + extra
        app.launch()
        return app
    }

    private func focusTextSize(in app: XCUIApplication) throws -> XCUIElement {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Text Size")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        for _ in 0..<6 where !row.hasFocus {
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(row.hasFocus, app.debugDescription)
        return row
    }
}
