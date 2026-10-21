import XCTest
import UIKit

@MainActor
final class ServerAddressNavigationInteractionTests: XCTestCase {
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
        }
        app.terminate()
        app = nil
        super.tearDown()
    }

    func testSingleSignInOpensAddressEditorDirectly() {
        launch(multiple: false)
        activate(app.buttons["manageServerAddresses"])
        XCTAssertTrue(app.staticTexts["Signed in as Alice"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Original server address"].exists)
        XCTAssertTrue(app.staticTexts["https://media.example.test"].exists)
        XCTAssertTrue(app.staticTexts["Jellyfin"].exists)
        XCTAssertFalse(app.buttons["Alice"].exists)
        #if os(tvOS)
        XCTAssertTrue(app.buttons["closeServerAddresses"].hasFocus, app.debugDescription)
        #else
        app.buttons["Copy address"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Copied"].exists)
        #endif
        capture("single-sign-in-editor")
        #if os(tvOS)
        XCUIRemote.shared.press(.menu)
        #else
        app.buttons["closeServerAddresses"].tap()
        #endif
        XCTAssertTrue(app.buttons["manageServerAddresses"].waitForExistence(timeout: 5))
    }

    func testMultipleSignInsAreChosenOnlyAfterTheExplicitAddressAction() {
        launch(multiple: true)
        XCTAssertFalse(app.buttons["Alice"].exists)
        XCTAssertFalse(app.buttons["Bob"].exists)
        capture("address-management-entry")
        activate(app.buttons["manageServerAddresses"])
        let bob = app.buttons["Bob"].firstMatch
        XCTAssertTrue(bob.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(
            app.sheets["Choose a sign-in"].exists || app.staticTexts["Choose a sign-in"].exists,
            app.debugDescription
        )
        capture("sign-in-chooser")
        activate(bob)
        XCTAssertTrue(app.staticTexts["Signed in as Bob"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Signed in as Alice"].exists)
        capture("selected-sign-in-editor")
    }

    func testLongPlexAddressAndConfirmedRemoval() {
        launch(multiple: false, arguments: ["--plex-addresses"])
        activate(app.buttons["manageServerAddresses"])
        XCTAssertTrue(app.staticTexts["Plex"].waitForExistence(timeout: 5), app.debugDescription)
        let original = app.staticTexts["https://192-168-68-71.0123456789abcdef0123456789abcdef.plex.direct:32400"]
        let alternate = app.staticTexts["https://media.example.test/plex"]
        XCTAssertTrue(original.exists)
        XCTAssertTrue(alternate.exists)
        capture("plex-addresses")
        activate(app.buttons["Remove"].firstMatch)
        let dialog = app.sheets["Remove this address?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), app.debugDescription)
        #if os(tvOS)
        let cancel = dialog.buttons["Cancel"].firstMatch
        waitForFocus(cancel)
        activate(cancel)
        #else
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(dismissRegion.waitForExistence(timeout: 5), app.debugDescription)
        dismissRegion.tap()
        #endif
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alternate.exists)
        #if os(tvOS)
        waitForFocus(app.buttons["Remove"].firstMatch)
        #endif
        activate(app.buttons["Remove"].firstMatch)
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), app.debugDescription)
        activate(dialog.buttons["Remove"].firstMatch, movingRight: true)
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: alternate)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        XCTAssertTrue(original.exists)
    }

    func testLightAppearance() {
        launch(multiple: false, arguments: ["--light-addresses"])
        activate(app.buttons["manageServerAddresses"])
        XCTAssertTrue(app.staticTexts["Signed in as Alice"].waitForExistence(timeout: 5))
        capture("light-addresses")
    }

    #if os(iOS)
    func testEnabledAddressActionKeepsItsIconReadableAcrossThemes() throws {
        for light in [false, true] {
            launch(multiple: false, arguments: light ? ["--light-addresses"] : [])
            activate(app.buttons["manageServerAddresses"])
            let field = app.textFields["serverAddressInput"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            let add = app.buttons["Verify and add address"]
            XCTAssertFalse(add.isEnabled)
            field.tap()
            field.typeText("https://media.example.test")
            XCTAssertTrue(add.isEnabled)
            for _ in 0..<6 {
                if add.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(add.isHittable)
            capture(light ? "enabled-action-light" : "enabled-action-dark")
            let icon = add.images["plus"]
            XCTAssertTrue(icon.exists, app.debugDescription)
            try assertIconContrast(icon)
            app.terminate()
        }
    }

    func testLargeTextAndInvalidAddressFeedback() {
        launch(multiple: false, arguments: ["--large-address-text"])
        activate(app.buttons["manageServerAddresses"])
        XCTAssertTrue(app.staticTexts["Signed in as Alice"].waitForExistence(timeout: 5))
        capture("large-text-addresses")
        let field = app.textFields["serverAddressInput"]
        for _ in 0..<6 {
            if field.isHittable { break }
            app.swipeUp()
        }
        field.tap()
        field.typeText("ftp://media.example.test")
        let add = app.buttons["Verify and add address"]
        for _ in 0..<6 {
            if add.isHittable { break }
            app.swipeUp()
        }
        add.tap()
        XCTAssertTrue(app.staticTexts["serverAddressError"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func assertIconContrast(_ icon: XCUIElement) throws {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let scale = CGFloat(image.width) / app.frame.width
        let region = icon.frame.insetBy(dx: -2, dy: -2)
            .applying(CGAffineTransform(scaleX: scale, y: scale)).integral
        let crop = try XCTUnwrap(image.cropping(to: region))
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        try pixels.withUnsafeMutableBytes {
            let context = try XCTUnwrap(CGContext(
                data: $0.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        func luminance(at offset: Int) -> Double {
            let channels = (0..<3).map { channel -> Double in
                let value = Double(pixels[offset + channel]) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        let background = luminance(at: 0)
        let readable = stride(from: 0, to: pixels.count, by: 4).filter { offset in
            let ink = luminance(at: offset)
            return (max(ink, background) + 0.05) / (min(ink, background) + 0.05) >= 3
        }.count
        XCTAssertGreaterThan(
            readable, crop.width * crop.height / 20,
            "The enabled plus glyph must have at least 3:1 contrast against its own button surface."
        )
    }
    #endif

    private func launch(multiple: Bool, arguments: [String] = []) {
        app.launchArguments = ["--server-address-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments += arguments
        if multiple { app.launchArguments.append("--multiple-address-signins") }
        app.launch()
        XCTAssertTrue(app.buttons["manageServerAddresses"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func activate(_ target: XCUIElement, movingRight: Bool = false) {
        #if os(tvOS)
        for _ in 0..<8 {
            if target.hasFocus { break }
            XCUIRemote.shared.press(movingRight ? .right : .down)
        }
        XCTAssertTrue(target.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        #else
        target.tap()
        #endif
    }

    #if os(tvOS)
    private func waitForFocus(_ target: XCUIElement) {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed, app.debugDescription)
    }
    #endif

    private func capture(_ name: String) {
        // Let native sheet and focus animations finish before retaining visual evidence.
        Thread.sleep(forTimeInterval: 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "server-addresses-\(name)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
