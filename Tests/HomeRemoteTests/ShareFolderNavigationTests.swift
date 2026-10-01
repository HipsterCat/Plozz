import XCTest
import UIKit

@MainActor
final class ShareFolderNavigationTests: XCTestCase {
    func testRepeatedDownAdvancesThroughLargeFolderAndRecordsNativeHitches() throws {
        guard #available(tvOS 26.0, *) else { throw XCTSkip("Native hitch metrics require tvOS 26.") }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--share-folder-fixture"]
        let reusing = ProcessInfo.processInfo.environment["PLOZZ_FOLDER_REUSE_FIXTURE"] == "1"
        if reusing {
            XCTAssertEqual(app.state, .runningForeground)
        } else {
            app.launch()
        }
        defer { if !reusing { app.terminate() } }
        XCTAssertTrue(app.buttons["Use This Folder"].waitForExistence(timeout: 15))
        for _ in 0..<12 {
            if focusedIndex(in: app) != nil { break }
            XCUIRemote.shared.press(.down)
        }
        Thread.sleep(forTimeInterval: 0.7)
        let startIndex = try XCTUnwrap(focusedIndex(in: app))
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        var count = 0
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            startMeasuring()
            for _ in 0..<8 {
                print("PLZFOLDER down \(count) epoch=\(Date().timeIntervalSince1970)")
                XCUIRemote.shared.press(.down)
                count += 1
                Thread.sleep(forTimeInterval: 0.35)
            }
            stopMeasuring()
        }
        let image = app.screenshot().image
        let screenshot = XCTAttachment(image: image)
        screenshot.name = "Scrolled folder focus and horizontal overflow"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(focusedIndex(in: app), startIndex + count)
        let focused = app.descendants(matching: .any).matching(NSPredicate(
            format: "hasFocus == true AND identifier BEGINSWITH 'share-location:'"
        )).firstMatch
        let frame = focused.frame
        for x in [frame.minX + 27, frame.maxX - 27] {
            try assertWhitePixel(image, at: CGPoint(x: x, y: frame.midY))
        }
        XCUIRemote.shared.press(.select)
        let selected = String(format: "%04d", startIndex + count)
        XCTAssertTrue(app.staticTexts["/Movies/Movie%20\(selected)%20%282026%29"]
            .waitForExistence(timeout: 5), app.debugDescription)
        let confirmation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasFocus == true"), object: app.buttons["Use This Folder"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [confirmation], timeout: 5), .completed,
                       "Opening the selected folder must restore its primary confirmation action.")
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(app.buttons["Up one level"].hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["/Movies"].waitForExistence(timeout: 5))
    }

    private func focusedIndex(in app: XCUIApplication) -> Int? {
        let element = app.descendants(matching: .any).matching(NSPredicate(
            format: "hasFocus == true AND label BEGINSWITH 'Movie '"
        )).firstMatch
        guard element.exists else { return nil }
        return Int(element.label.dropFirst(6).prefix(4))
    }

    private func assertWhitePixel(_ image: UIImage, at point: CGPoint) throws {
        let bitmap = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(bitmap.width) / image.size.width
        let pixel = try XCTUnwrap(bitmap.cropping(to: CGRect(
            x: floor(point.x * scale), y: floor(point.y * scale), width: 1, height: 1
        )))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        XCTAssertTrue(rgba.prefix(3).allSatisfy { $0 > 235 },
                      "The focused card must extend beyond both content edges, not be clipped to its label.")
    }
}
