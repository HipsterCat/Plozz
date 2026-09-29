import UIKit
import XCTest

@MainActor
final class PlayerEpisodeRowRemoteTests: XCTestCase {
    func testHeldDirectionsCrossViewportAndSeasonBoundaries() throws {
        try assertContinuousBrowsing()
    }

    func testHeldDirectionsCrossLoadingBoundariesInRTL() throws {
        try assertContinuousBrowsing(rtl: true)
    }

    private func assertContinuousBrowsing(rtl: Bool = false) throws {
        continueAfterFailure = false
        let app = launch(arguments: rtl ? ["--rtl"] : [])
        defer { app.terminate() }
        XCUIRemote.shared.press(.down)
        let start = try focusedEpisode(in: app)
        XCUIRemote.shared.press(rtl ? .left : .right, forDuration: 18)
        let right = try focusedEpisode(in: app)
        let afterHold = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        afterHold.name = "Episode right hold"
        afterHold.lifetime = .keepAlways
        add(afterHold)
        XCTAssertGreaterThan(right, 48, "One hold must continue into the following season.")
        XCTAssertGreaterThan(right, start + 8, "One hold must cross several viewports.")
        let forwardTrace = trace(in: app)
        XCTAssertGreaterThan(forwardTrace.count, 8)
        XCTAssertTrue(zip(forwardTrace, forwardTrace.dropFirst()).allSatisfy { $0 < $1 },
                      "Forward focus must not jump backward as cells and seasons load: \(forwardTrace)")
        XCUIRemote.shared.press(rtl ? .right : .left, forDuration: 36)
        XCTAssertLessThan(try focusedEpisode(in: app), 25,
                          "One hold must continue through earlier season loading.")
        let backwardTrace = Array(trace(in: app).dropFirst(forwardTrace.count - 1))
        XCTAssertTrue(zip(backwardTrace, backwardTrace.dropFirst()).allSatisfy { $0 > $1 },
                      "Backward focus must not jump forward while earlier seasons load: \(backwardTrace)")
        XCTAssertLessThanOrEqual(try XCTUnwrap(Int(app.staticTexts["episode-row-peak-cells"].label)), 24)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Continuous episode browsing"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFirstEpisodeDoesNotScrollWhenItReceivesFocus() throws {
        continueAfterFailure = false
        let app = launch(arguments: ["--single-season"])
        defer { app.terminate() }
        let first = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Episode 1' AND value == 'S1 · E1'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        let x = first.frame.midX
        XCUIRemote.shared.press(.down)
        if try focusedEpisode(in: app) == 2 { XCUIRemote.shared.press(.left) }
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(try focusedEpisode(in: app), 1)
        XCTAssertEqual(first.frame.midX, x, accuracy: 2, "First-card entry must not change row alignment.")
        XCUIRemote.shared.press(.right, forDuration: 4)
        XCUIRemote.shared.press(.left, forDuration: 8)
        waitForFocusedCardToSettle(in: app)
        XCTAssertEqual(try focusedEpisode(in: app), 1)
        XCTAssertEqual(first.frame.midX, x, accuracy: 2, "Returning to the first episode must keep the same gutter.")
        let capture = XCUIScreen.main.screenshot()
        try assertFocusedEpisodeLabelIsVisible(first.frame, in: capture, appFrame: app.frame)
        let screenshot = XCTAttachment(screenshot: capture)
        screenshot.name = "Focused episode scrim"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testInitiallyLeadingEpisodeDoesNotShiftWhenFocused() throws {
        continueAfterFailure = false
        let app = launch()
        defer { app.terminate() }
        let first = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Episode 36' AND value == 'S2 · E12'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        let x = first.frame.midX
        XCUIRemote.shared.press(.down)
        if try focusedEpisode(in: app) == 37 { XCUIRemote.shared.press(.left) }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(try focusedEpisode(in: app), 36)
        XCTAssertEqual(first.frame.midX, x, accuracy: 2,
                       "The initially leading episode must already have its native focus clearance.")
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.left)
        XCTAssertEqual(try focusedEpisode(in: app), 36)
        XCTAssertEqual(first.frame.midX, x, accuracy: 2)
    }

    func testLongSeasonReusesNativeCellsDuringHeldBrowsing() throws {
        continueAfterFailure = false
        let app = launch(arguments: ["--long-season"])
        defer { app.terminate() }
        XCTAssertEqual(app.staticTexts["episode-row-count"].label, "1000")
        XCUIRemote.shared.press(.down)
        let start = try focusedEpisode(in: app)
        XCTAssertGreaterThanOrEqual(start, 500)
        XCUIRemote.shared.press(.right, forDuration: 8)
        waitForFocusedCardToSettle(in: app)
        let last = try focusedEpisode(in: app)
        XCTAssertGreaterThan(last, start + 12)
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(app.buttons["Browse episodes"].hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.down)
        let returned = try focusedEpisode(in: app)
        XCTAssertLessThan(abs(returned - last), 5,
                          "Native Down may select a column-aligned card, but must retain the browsed viewport.")
        XCTAssertGreaterThan(returned, start + 12)
        XCTAssertLessThanOrEqual(try XCTUnwrap(Int(app.staticTexts["episode-row-peak-cells"].label)), 24,
                                 "A large season must not create every native artwork cell.")
    }

    private func trace(in app: XCUIApplication) -> [Int] {
        app.staticTexts["episode-row-trace"].label.split(separator: ",").compactMap { Int($0) }
    }

    private func assertFocusedEpisodeLabelIsVisible(
        _ cell: CGRect, in screenshot: XCUIScreenshot, appFrame: CGRect
    ) throws {
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let scale = CGFloat(image.width) / appFrame.width
        // The fixture has no white artwork. Sample only the lower-left image
        // interior, excluding the native focus rim and the caption below it.
        let region = CGRect(
            x: (cell.minX + 10 - appFrame.minX) * scale,
            y: (cell.minY + cell.height * 0.5 - appFrame.minY) * scale,
            width: cell.width * 0.35 * scale, height: cell.height * 0.22 * scale
        ).integral
        let crop = try XCTUnwrap(image.cropping(to: region))
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let whitePixels = try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return stride(from: 0, to: bytes.count, by: 4).filter {
                bytes[$0] > 220 && bytes[$0 + 1] > 220 && bytes[$0 + 2] > 220
            }.count
        }
        XCTAssertGreaterThan(whitePixels, 30,
                             "Panel glass must not hide the native focused artwork and its episode label.")
    }

    private func waitForFocusedCardToSettle(in app: XCUIApplication) {
        let collection = app.collectionViews.firstMatch
        let focused = collection.cells.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            focused.exists && collection.frame.insetBy(dx: -1, dy: -1).contains(focused.frame)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "The focused card must settle inside the row's viewport.")
    }

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--episode-row-fixture"] + arguments
        app.launch()
        let ready = app.staticTexts["episode-row-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15))
        XCTAssertEqual(XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Ready'"), object: ready)
        ], timeout: 10), .completed)
        return app
    }

    private func focusedEpisode(in app: XCUIApplication) throws -> Int {
        let focused = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true AND label BEGINSWITH 'Episode '")).firstMatch
        XCTAssertTrue(focused.exists, app.debugDescription)
        return try XCTUnwrap(Int(focused.label.dropFirst("Episode ".count)))
    }
}
