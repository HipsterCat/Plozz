import XCTest
import UIKit

@MainActor
final class SystemDirectionalFocusTests: XCTestCase {
    func testFeaturedCardsSettleAfterHeldDirectionalNavigation() throws {
        try exerciseFeaturedDirections(bright: false)
    }

    func testBrightFeaturedCornersStayCoveredAfterHeldDirectionalNavigation() throws {
        try exerciseFeaturedDirections(bright: true)
    }

    private func exerciseFeaturedDirections(bright: Bool) throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--focus-navigation-fixture", "--featured-rails"]
            + (bright ? ["--white-artwork"] : [])
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Navigation fixture ready"].waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.down)
        let seeAll = app.buttons["See all"].firstMatch
        if seeAll.exists, seeAll.hasFocus { XCUIRemote.shared.press(.down) }
        try Self.assertFocus("Row 0 Item 0", in: app)
        XCUIRemote.shared.press(.right)
        Thread.sleep(forTimeInterval: 1)
        XCUIRemote.shared.press(.left)
        Thread.sleep(forTimeInterval: 1)
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "featured-after-slow-navigation"
        initial.lifetime = .keepAlways
        add(initial)
        let restingGaps = try Self.featuredArtworkTopGaps(in: app, bright: bright)
        XCTAssertTrue(restingGaps.allSatisfy { $0 > 8 },
                      "Untouched and previously focused cards must both rest below the raised first card: \(restingGaps)")
        for _ in 0..<3 {
            XCUIRemote.shared.press(.right, forDuration: 1.2)
            XCUIRemote.shared.press(.left, forDuration: 2.5)
        }
        try Self.assertFocus("Row 0 Item 0", in: app)
        Thread.sleep(forTimeInterval: 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "featured-after-held-directional-navigation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let finalGaps = try Self.featuredArtworkTopGaps(in: app, bright: bright)
        for (baseline, final) in zip(restingGaps, finalGaps) {
            XCTAssertEqual(final, baseline, accuracy: 1, "Previously focused cards must return to their resting painted size.")
        }
        XCUIRemote.shared.press(.right)
        try Self.assertFocus("Row 0 Item 1", in: app)
        XCTAssertTrue(app.staticTexts["Preview candidate: Row 0 Item 1"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Selected Row 0 Item 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Preview candidate: None"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.down)
        let nextRow = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND hasFocus == true", "Row 1 Item "
        )).firstMatch
        XCTAssertTrue(nextRow.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Preview candidate: \(nextRow.label)"].waitForExistence(timeout: 3))
        #else
        throw XCTSkip("This regression uses an isolated simulator fixture.")
        #endif
    }

    private static func featuredArtworkTopGaps(in app: XCUIApplication, bright: Bool) throws -> [CGFloat] {
        let image = app.screenshot().image
        let bitmap = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: bitmap.width, height: bitmap.height,
                bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        }
        let scale = CGFloat(bitmap.width) / app.frame.width
        func isArtwork(x: Int, y: Int) -> Bool {
            let offset = (y * bitmap.width + x) * 4
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            return bright ? min(red, green, blue) > 245 : blue > 140 && blue > 2 * red && blue * 2 > green * 3
        }
        let tops = try (0..<3).map { index -> CGFloat in
            let card = app.buttons.matching(NSPredicate(format: "label == %@", "Row 0 Item \(index)")).firstMatch
            XCTAssertTrue(card.exists)
            if index > 0 {
                for x in [Int(card.frame.minX * scale) + 2, Int(card.frame.maxX * scale) - 2] {
                    for y in [Int(card.frame.minY * scale) + 2, Int(card.frame.maxY * scale) - 2] {
                        XCTAssertFalse(isArtwork(x: x, y: y), "Unfocused card \(index) must retain rounded corners.")
                    }
                }
                if bright {
                    let frame = CGRect(
                        x: card.frame.minX * scale, y: card.frame.minY * scale,
                        width: card.frame.width * scale, height: card.frame.height * scale
                    ).integral
                    let band = Int(28 * scale)
                    var excess = 0
                    for y in (Int(frame.maxY) - band)..<Int(frame.maxY) {
                        let reference = Int(pixels[(y * bitmap.width + Int(frame.midX)) * 4])
                        for x in Array(Int(frame.minX)..<(Int(frame.minX) + band))
                            + Array((Int(frame.maxX) - band)..<Int(frame.maxX)) {
                            let outsideX = x < Int(frame.midX)
                                ? Int(frame.minX - 4 * scale) : Int(frame.maxX + 4 * scale)
                            let background = Int(pixels[(y * bitmap.width + outsideX) * 4])
                            // Rounded-edge antialiasing may blend with the page, but not the white backing.
                            excess = max(excess, Int(pixels[(y * bitmap.width + x) * 4]) - max(reference, background))
                        }
                    }
                    XCTAssertLessThanOrEqual(excess, 4,
                        "Bright poster \(index) must keep its scrim through the corners after actual remote defocus.")
                }
            }
            let x = min(bitmap.width - 1, max(0, Int(card.frame.midX * scale)))
            let y = try XCTUnwrap((0..<bitmap.height).first { y in
                isArtwork(x: x, y: y)
            }, "Expected the fixture's solid \(bright ? "white" : "blue") artwork for card \(index).")
            return CGFloat(y) / scale
        }
        return tops.dropFirst().map { $0 - tops[0] }
    }

    func testRemoteDirectionsDoNotRestoreThePreviousCardOrHero() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        try FocusStyleSettingsCaptureTests.withFocusStyle("Default") { _ in
            for borderless in [false, true] {
                add(try Self.exerciseDirections(in: app, borderless: borderless))
            }
        }
        #else
        throw XCTSkip("This regression uses an isolated simulator fixture.")
        #endif
    }

    static func exerciseDirections(in app: XCUIApplication, borderless: Bool) throws -> XCTAttachment {
        app.launchArguments = ["--focus-navigation-fixture"] + (borderless ? ["--borderless"] : [])
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Navigation fixture ready"].waitForExistence(timeout: 15))
        let hero = app.buttons["navigation-hero"]
        XCTAssertTrue(hero.hasFocus)
        XCUIRemote.shared.press(.down)
        try assertFocus("Row 0 Item 0", in: app)
        XCUIRemote.shared.press(.right)
        try assertFocus("Row 0 Item 1", in: app)
        XCUIRemote.shared.press(.right)
        try assertFocus("Row 0 Item 2", in: app)
        XCUIRemote.shared.press(.left)
        try assertFocus("Row 0 Item 1", in: app)
        for index in 2...6 {
            XCUIRemote.shared.press(.right)
            try assertFocus("Row 0 Item \(index)", in: app)
        }
        for index in stride(from: 5, through: 0, by: -1) {
            XCUIRemote.shared.press(.left)
            try assertFocus("Row 0 Item \(index)", in: app)
        }
        XCUIRemote.shared.press(.right)
        try assertFocus("Row 0 Item 1", in: app)
        XCUIRemote.shared.press(.down)
        try assertFocus("Row 1 Item 1", in: app)
        XCUIRemote.shared.press(.right)
        try assertFocus("Row 1 Item 2", in: app)
        XCUIRemote.shared.press(.up)
        try assertFocus("Row 0 Item 2", in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "native-directions-\(borderless ? "borderless" : "framed")"
        screenshot.lifetime = .keepAlways
        return screenshot
    }

    private static func assertFocus(_ label: String, in app: XCUIApplication) throws {
        // System / highlight styles may put focus on an inner container rather
        // than the Button whose accessibility label is the title.
        let focused = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let predicate = NSPredicate { _, _ in
            focused.exists && (focused.label == label || focused.staticTexts[label].exists
                || focused.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", label)).count > 0)
        }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 3),
            .completed,
            "Expected \(label). \(app.debugDescription)"
        )
        Thread.sleep(forTimeInterval: 0.35)
        let still = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let stillOnTarget = still.exists && (still.label == label || still.staticTexts[label].exists
            || still.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", label)).count > 0)
        XCTAssertTrue(stillOnTarget, "Focus bounced away from \(label). \(app.debugDescription)")
    }
}
