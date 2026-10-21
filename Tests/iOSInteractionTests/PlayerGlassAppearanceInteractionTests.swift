import UIKit
import XCTest

@MainActor
final class PlayerGlassAppearanceInteractionTests: XCTestCase {
    func testPlayerPanelsFollowSystemLiquidGlassTintAmount() throws {
        XCUIDevice.shared.orientation = .portrait
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        defer { settings.terminate() }
        let tint = settings.sliders["Tint Amount"]
        if !tint.waitForExistence(timeout: 2) {
            let display = settings.buttons.matching(NSPredicate(
                format: "identifier == %@ OR label == %@",
                "com.apple.settings.appearance", "Display & Brightness"
            )).firstMatch
            for _ in 0..<5 where !display.isHittable {
                if display.exists && display.frame.minY < 140 { settings.swipeDown() }
                else { settings.swipeUp() }
            }
            XCTAssertTrue(display.waitForExistence(timeout: 5), settings.debugDescription)
            display.tap()
            let glass = settings.cells.containing(.staticText, identifier: "Liquid Glass").firstMatch
            XCTAssertTrue(glass.waitForExistence(timeout: 5), settings.debugDescription)
            glass.tap()
        }
        guard tint.waitForExistence(timeout: 5) else {
            throw XCTSkip("The system Tint Amount slider requires the iOS 27 Settings UI.")
        }
        let original = try XCTUnwrap(tint.value as? String)
        let originalAmount = try XCTUnwrap(Double(original.replacingOccurrences(of: "%", with: ""))) / 100
        @MainActor func setTint(_ amount: Double) {
            let value = (tint.value as? String)?.replacingOccurrences(of: "%", with: "")
            guard let value, let current = Double(value) else {
                XCTFail("The native tint slider must expose its current value.")
                return
            }
            tint.coordinate(withNormalizedOffset: CGVector(dx: current / 100, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: tint.coordinate(
                    withNormalizedOffset: CGVector(dx: amount, dy: 0.5)
                ), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        defer {
            settings.activate()
            setTint(originalAmount)
            XCTAssertEqual(tint.value as? String, original, "Restore the owned simulator's original preference.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--player-glass-fixture"]
        app.launch()
        defer { app.terminate() }
        var darkPanels: [Double] = []
        for amount in [0.0, 1.0] {
            settings.activate()
            setTint(amount)
            let expected = amount == 0 ? "0%" : "100%"
            #if targetEnvironment(simulator)
            guard tint.value as? String == expected else {
                throw XCTSkip("This simulator's Tint Amount control does not respond to slider adjustment or direct dragging; real preference switching is not verified.")
            }
            #else
            XCTAssertEqual(tint.value as? String, expected)
            #endif
            app.activate()
            for scheme in ["dark", "light"] {
                Thread.sleep(forTimeInterval: 0.8)
                let screenshot = app.screenshot()
                let panel = app.descendants(matching: .any)["appearance-panel"].firstMatch
                let reference = app.descendants(matching: .any)["appearance-reference"].firstMatch
                let actual = luminance(try pixels(screenshot.image, frame: panel.frame, screen: app.frame))
                let native = luminance(try pixels(screenshot.image, frame: reference.frame, screen: app.frame))
                XCTAssertEqual(actual, native, accuracy: 0.03,
                               "The system preference, not Plozz decoration, must determine panel glass.")
                if scheme == "dark" { darkPanels.append(actual) }
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "System tint \(amount), \(scheme), native and player panels"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.buttons["player-playback-options"].tap()
                XCTAssertTrue(app.buttons["Fixture option"].waitForExistence(timeout: 5))
                let menu = XCTAttachment(screenshot: app.screenshot())
                menu.name = "System tint \(amount), \(scheme), native options menu"
                menu.lifetime = .keepAlways
                add(menu)
                app.buttons["Fixture option"].tap()
                app.buttons["appearance-theme"].tap()
            }
        }
        XCTAssertGreaterThan(abs(darkPanels[0] - darkPanels[1]), 0.03,
                             "Changing the real OS tint preference must visibly change the player panel.")
    }

    func testPlayerGlassMatchesNativeCompositorAcrossThemesAndVideo() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--player-glass-fixture"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["appearance-theme"].waitForExistence(timeout: 10))
        for backdrop in ["white", "black"] {
            var samples: [[String: [UInt8]]] = []
            for scheme in ["dark", "light"] {
                Thread.sleep(forTimeInterval: 0.7)
                let screenshot = app.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "Native player \(scheme) over \(backdrop)"
                attachment.lifetime = .keepAlways
                add(attachment)
                var sample: [String: [UInt8]] = [:]
                for name in ["circle", "tab", "native-button", "track", "panel"] {
                    let element = app.descendants(matching: .any)["appearance-\(name)"].firstMatch
                    XCTAssertTrue(element.exists, name)
                    let bytes = try pixels(screenshot.image, frame: element.frame, screen: app.frame)
                    sample[name] = bytes
                }
                let reference = app.descendants(matching: .any)["appearance-reference"].firstMatch
                XCTAssertTrue(reference.exists)
                let native = try pixels(screenshot.image, frame: reference.frame, screen: app.frame)
                let panel = try XCTUnwrap(sample["panel"])
                XCTAssertEqual(luminance(panel), luminance(native), accuracy: 0.05,
                               "Video-card glass must match stock UIKit media glass without extra backing or tint.")
                let circleFrame = app.buttons["appearance-circle"].frame
                let circle = try pixels(screenshot.image, frame: CGRect(
                    x: circleFrame.midX - 40, y: circleFrame.midY - 40, width: 80, height: 80
                ), screen: app.frame)
                let circleReference = app.descendants(matching: .any)["appearance-reference-circle"].firstMatch
                let clear = try pixels(screenshot.image, frame: CGRect(
                    x: circleReference.frame.midX - 40, y: circleReference.frame.midY - 40, width: 80, height: 80
                ), screen: app.frame)
                XCTAssertEqual(luminance(circle), luminance(clear), accuracy: 0.03,
                               "Video controls must use untinted clear glass and white ink, including in Light mode.")
                try assertSingleGroupSurface(app, screenshot: screenshot)
                samples.append(sample)
                app.buttons["appearance-theme"].tap()
            }
            for name in samples[0].keys {
                let first = try XCTUnwrap(samples[0][name])
                let second = try XCTUnwrap(samples[1][name])
                XCTAssertEqual(first.count, second.count)
            }
            if backdrop == "white" { app.buttons["appearance-video"].tap() }
        }
        assertIndependentActions(app)
    }

    func testReducedEffectsGroupingInBothAppearances() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--player-glass-fixture"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["appearance-effects"].waitForExistence(timeout: 10))
        app.buttons["appearance-effects"].tap()
        app.buttons["appearance-video"].tap()
        for appearance in ["dark", "light"] {
            Thread.sleep(forTimeInterval: 0.7)
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Reduced effects group \(appearance)"
            attachment.lifetime = .keepAlways
            add(attachment)
            try assertSingleGroupSurface(app, screenshot: screenshot)
            app.buttons["appearance-theme"].tap()
        }
        assertIndependentActions(app)
    }

    private func assertSingleGroupSurface(_ app: XCUIApplication, screenshot: XCUIScreenshot) throws {
        let group = app.descendants(matching: .any)["appearance-group"].firstMatch.frame
        let reference = app.descendants(matching: .any)["appearance-reference-group"].firstMatch.frame
        let actual = try groupSurface(screenshot, frame: group, screen: app.frame)
        let expected = try groupSurface(screenshot, frame: reference, screen: app.frame)
        XCTAssertEqual(actual.count, expected.count)
        let difference = zip(actual, expected).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
            / Double(max(1, actual.count)) / 255
        XCTAssertLessThan(difference, 0.04,
                          "The mixed UIKit/SwiftUI group must be one capsule, with no nested circular surfaces.")
    }

    private func assertIndependentActions(_ app: XCUIApplication) {
        app.buttons["appearance-group-left"].tap()
        app.buttons["player-playback-options"].tap()
        XCTAssertTrue(app.buttons["Fixture option"].waitForExistence(timeout: 5))
        app.buttons["Fixture option"].tap()
        XCTAssertEqual(app.buttons["appearance-group-left"].value as? String, "1")
        XCTAssertEqual(app.buttons["player-playback-options"].value as? String, "1")
    }

    private func groupSurface(_ screenshot: XCUIScreenshot, frame: CGRect, screen: CGRect) throws -> [UInt8] {
        try pixels(screenshot.image, frame: CGRect(
            x: frame.midX - 36, y: frame.midY - 22, width: 72, height: 16
        ), screen: screen)
    }

    private func luminance(_ bytes: [UInt8]) -> Double {
        stride(from: 0, to: bytes.count, by: 4).reduce(0.0) {
            $0 + Double(bytes[$1]) * 0.2126 + Double(bytes[$1 + 1]) * 0.7152 + Double(bytes[$1 + 2]) * 0.0722
        } / Double(max(1, bytes.count / 4)) / 255
    }

    private func pixels(_ image: UIImage, frame: CGRect, screen: CGRect) throws -> [UInt8] {
        let image = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(image.width) / screen.width
        let frame = frame.insetBy(dx: 5, dy: 5)
        let crop = try XCTUnwrap(image.cropping(to: CGRect(
            x: ((frame.minX - screen.minX) * scale).rounded(),
            y: ((frame.minY - screen.minY) * scale).rounded(),
            width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded()
        )))
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        return bytes
    }
}
