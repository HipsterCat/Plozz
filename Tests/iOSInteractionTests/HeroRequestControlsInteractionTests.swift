import XCTest

@MainActor
final class HeroRequestControlsInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDown() async throws {
        if let app, app.state == .runningForeground {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        app = nil
        try await super.tearDown()
    }

    func testEveryRequestStateRetainsAContainerAndMonochromeInk() throws {
        for options in [[], ["--light"], ["--reduced"], ["--light", "--reduced"]] {
            launch(options)
            for id in [
                "seasons", "movie", "submitting", "requested", "downloading", "loading-seasons",
                "pending-seasons", "submitting-seasons", "failed-seasons", "processing-seasons"
            ] {
                let button = app.buttons["hero-\(id)"]
                for _ in 0..<5 where !button.isHittable { app.swipeUp() }
                XCTAssertTrue(button.waitForExistence(timeout: 5), id)
                XCTAssertGreaterThanOrEqual(button.frame.height, 48, id)
                XCTAssertGreaterThanOrEqual(button.frame.width, 44, id)
                let screenshot = app.screenshot()
                let bytes = try pixels(screenshot.image, frame: button.frame)
                let coloredPixels = stride(from: 0, to: bytes.count, by: 4).filter {
                    Int(bytes[$0 + 2]) - Int(bytes[$0]) > 40
                }.count
                XCTAssertLessThan(coloredPixels, 10, "\(id) must not fall back to blue link text.")
                let backdrop = try pixels(screenshot.image, frame: CGRect(
                    x: app.frame.minX + 2, y: button.frame.midY, width: 14, height: 14
                ))
                let minimumContrast = button.isEnabled ? 20 : 2
                let surfacePixels = stride(from: 0, to: bytes.count, by: 4).filter {
                    abs(Int(bytes[$0]) - Int(backdrop[0])) > minimumContrast
                }.count
                XCTAssertGreaterThan(Double(surfacePixels) / Double(bytes.count / 4), 0.45,
                                     "\(id) \(options) must render a container, not just text.")
                if id == "submitting" {
                    let spinner = try pixels(screenshot.image, frame: CGRect(
                        x: button.frame.midX - 16, y: button.frame.midY - 16, width: 32, height: 32
                    ))
                    let values = stride(from: 0, to: spinner.count, by: 4).map { Int(spinner[$0]) }
                    XCTAssertGreaterThan(try XCTUnwrap(values.max()) - XCTUnwrap(values.min()), 50,
                                         "The request spinner must contrast with its primary surface.")
                }
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "\(id)-\(options.joined(separator: "-"))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            app.terminate()
        }
    }

    func testSeasonButtonOpensSharedSheetAndRequestsOnlySelectedMissingSeasons() {
        launch([])
        app.buttons["hero-seasons"].tap()
        XCTAssertTrue(app.navigationBars["Seasons"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Request Season 1"].exists)
        XCTAssertFalse(app.buttons["Request Season 2"].exists)
        XCTAssertTrue(app.buttons["Request Season 3"].exists)
        app.buttons["Request Season 3"].tap()
        XCTAssertTrue(app.buttons["Request Season 3"].waitForNonExistence(timeout: 5))
        app.buttons["Close"].tap()
        scrollToResult()
        XCTAssertEqual(app.staticTexts["requested-seasons"].label, "3")

        app.swipeDown()
        app.swipeDown()
        app.buttons["hero-seasons"].tap()
        let allMissing = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Request All Missing")).firstMatch
        XCTAssertTrue(allMissing.waitForExistence(timeout: 5))
        allMissing.tap()
        XCTAssertTrue(app.buttons["Request Season 1"].waitForNonExistence(timeout: 5))
        app.buttons["Close"].tap()
        scrollToResult()
        XCTAssertEqual(app.staticTexts["requested-seasons"].label, "1")
    }

    func testLoadingFailureRetriesInsideTheSheetAndSubmissionDisablesRequests() {
        launch(["--failed-seasons"])
        app.buttons["hero-seasons"].tap()
        XCTAssertTrue(app.navigationBars["Seasons"].waitForExistence(timeout: 5))
        let retry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Retry Season Status")).firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(app.buttons["Request Season 1"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        app.terminate()

        launch(["--submitting-seasons"])
        app.buttons["hero-seasons"].tap()
        XCTAssertTrue(app.navigationBars["Seasons"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Request Season 1"].isEnabled)
        XCTAssertFalse(app.buttons["Request Season 3"].isEnabled)
    }

    func testAdministratorConfirmationAndErrorsStayInTheSheet() {
        launch(["--confirm-request", "--request-fails"])
        app.buttons["hero-seasons"].tap()
        XCTAssertTrue(app.navigationBars["Seasons"].waitForExistence(timeout: 5))
        app.buttons["Request Season 1"].tap()
        XCTAssertTrue(app.alerts["Request as Administrator?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Request Season 1"].exists)
        app.buttons["Request Season 1"].tap()
        app.alerts.buttons["Request as Administrator"].tap()
        XCTAssertTrue(app.alerts.staticTexts["Fixture request failed"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Seasons"].exists)
        XCTAssertTrue(app.buttons["Request Season 1"].exists, "Failure must not mark a season requested.")
    }

    private func launch(_ options: [String]) {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--hero-request-controls-fixture"] + options
        app.launch()
        XCTAssertTrue(app.buttons["hero-seasons"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func scrollToResult() {
        for _ in 0..<5 where !app.staticTexts["requested-seasons"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["requested-seasons"].isHittable)
    }

    private func pixels(_ image: UIImage, frame: CGRect) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(cgImage.width) / app.frame.width
        let cropFrame = frame.insetBy(dx: 6, dy: 6)
        let crop = try XCTUnwrap(cgImage.cropping(to: CGRect(
            x: cropFrame.minX * scale, y: cropFrame.minY * scale,
            width: cropFrame.width * scale, height: cropFrame.height * scale
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
