import XCTest

@MainActor
final class PlozzChannelIdentityCaptureTests: XCTestCase {
    func testNativeBylineThemes() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        var referenceFrame: CGRect?
        for theme in ["dark", "light", "black"] {
            let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
            app.launchArguments = ["--channel-identity-fixture"]
            app.launchEnvironment["PLOZZ_CHANNEL_IDENTITY_THEME"] = theme
            app.launch()
            defer { app.terminate() }
            let program = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "The Evening Feature")
            ).firstMatch
            XCTAssertTrue(program.waitForExistence(timeout: 10), app.debugDescription)
            let focused = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasFocus == true"), object: program
            )
            XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed)
            XCTAssertTrue(app.buttons["live-tv-channel-channels-4"].exists, "Include a long channel name.")
            if let referenceFrame { XCTAssertEqual(program.frame, referenceFrame) }
            else { referenceFrame = program.frame }
            Thread.sleep(forTimeInterval: 0.7)
            let screenshot = app.screenshot()
            let image = try XCTUnwrap(screenshot.image.cgImage)
            XCTAssertEqual(image.width, 3840)
            XCTAssertEqual(image.height, 2160)
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "byline-\(theme)-native-guide"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        #else
        throw XCTSkip("Design comparisons use the task-owned Apple TV simulator.")
        #endif
    }
}
