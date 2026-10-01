import XCTest
import notify

@MainActor
final class PhysicalDiagnosticInputTests: XCTestCase {
    func testInspectRecordingStatusWithoutInput() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PLOZZ_CAPTURE_INSPECT_STATUS"] == "1",
              let bundleID = environment["PLOZZ_CAPTURE_BUNDLE_ID"], !bundleID.isEmpty else {
            throw XCTSkip("Explicit existing-app status inspection only.")
        }
        let app = XCUIApplication(bundleIdentifier: bundleID)
        print("PLZCAPTURE inspection.state=\(app.state.rawValue)")
        XCTAssertEqual(app.state, .runningForeground)
        guard app.state == .runningForeground else { return }
        XCTAssertEqual(notify_post(bundleID + ".Diagnostics.preparing"), UInt32(NOTIFY_STATUS_OK))
        defer { notify_post(bundleID + ".Diagnostics.finished") }
        let badge = app.staticTexts["diagnostic-recording-status"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Existing app recording status"
        image.lifetime = .keepAlways
        add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Recording status accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }

    func testPressFocusedControlAfterRecordingConfirmation() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PLOZZ_CAPTURE_EXISTING_APP"] == "1",
              let label = environment["PLOZZ_CAPTURE_FOCUSED_LABEL"], !label.isEmpty,
              let bundleID = environment["PLOZZ_CAPTURE_BUNDLE_ID"], !bundleID.isEmpty else {
            throw XCTSkip("Requires the already-running physical TV app and an explicitly confirmed recorder.")
        }
        let app = XCUIApplication(bundleIdentifier: bundleID)
        XCTAssertEqual(app.state, .runningForeground)
        guard app.state == .runningForeground else { return }
        let target = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Before the single focused-control press"
        before.lifetime = .keepAlways
        add(before)
        XCTAssertTrue(target.exists && target.hasFocus, "Do not move focus or press a different control.")
        guard target.exists && target.hasFocus else { return }

        let notification = "com.thatcube.Plozz.DiagnosticInput.\(UUID().uuidString)"
        let recording = XCTestExpectation(description: "Parent confirms sustained recording")
        var token: Int32 = 0
        let status = notify_register_dispatch(notification, &token, .main) { _ in recording.fulfill() }
        guard status == UInt32(NOTIFY_STATUS_OK) else {
            XCTFail("Cannot register the recording confirmation; no input sent.")
            return
        }
        defer { notify_cancel(token) }
        print("PLZCAPTURE ready notification=\(notification) relaunch=false")
        guard await XCTWaiter.fulfillment(of: [recording], timeout: 120) == .completed else {
            XCTFail("Recording was not confirmed; no input sent.")
            return
        }
        guard app.state == .runningForeground, target.exists && target.hasFocus else {
            XCTFail("The original focused control changed; no input sent.")
            return
        }
        let start = ProcessInfo.processInfo.systemUptime
        print("PLZCAPTURE select.begin epoch=\(Date().timeIntervalSince1970) uptime=\(start)")
        XCUIRemote.shared.press(.select)
        print("PLZCAPTURE select.end elapsed=\(ProcessInfo.processInfo.systemUptime - start)")
        let observation = min(180, max(5, Double(environment["PLOZZ_CAPTURE_OBSERVE_SECONDS"] ?? "") ?? 75))
        try await Task.sleep(for: .seconds(observation))
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "After the single focused-control press"
        after.lifetime = .keepAlways
        add(after)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Result accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        print("PLZCAPTURE observation.complete relaunch=false")
    }
}
