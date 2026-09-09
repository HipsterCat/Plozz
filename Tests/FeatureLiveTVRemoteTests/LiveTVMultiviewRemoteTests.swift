import XCTest
import UIKit

final class LiveTVMultiviewRemoteTests: XCTestCase {
    @MainActor
    func testProductionRootRetainsThePromotedPlayer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--live-root-fixture"]
        app.launch()
        defer { app.terminate() }
        select(app.buttons["live-tv-channel-channels-1"], in: app)
        select(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "Play channel")
            ).firstMatch,
            in: app
        )
        XCTAssertTrue(
            app.staticTexts["multiview-fixture-player-1"].waitForExistence(timeout: 10),
            app.debugDescription
        )
        select(app.buttons["live-channel-multiview"], in: app)
        assertMetrics("Engines 1 loads 1 stops 0 audible 1", in: app)
        select(app.buttons["live-multiview-add"], in: app)
        select(app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "live-multiview-channel-", "Sports 2"
        )).firstMatch, in: app)
        assertMetrics("Engines 2 loads 2 stops 0 audible 1", in: app)
        selectAudio("Sports 2", in: app)
        select(app.buttons["live-multiview-done"], in: app)
        XCTAssertTrue(app.staticTexts["multiview-fixture-player-2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["multiview-fixture-player-2"].label, "Engine 2 loads 1")
        XCUIRemote.shared.press(.menu)
        assertMetrics("Engines 2 loads 2 stops 1 audible 1", in: app)
        select(app.buttons["live-root-fixture-refresh"], in: app)
        XCTAssertEqual(app.buttons["live-root-fixture-refresh"].value as? String, "1")
        assertMetrics("Engines 2 loads 2 stops 1 audible 1", in: app)
        select(app.buttons["live-root-fixture-leave"], in: app)
        assertMetrics("Engines 2 loads 2 stops 2 audible 0", in: app)
    }

    @MainActor
    func testNativeFullscreenMultiviewLayoutsAndReturnKeepExistingPlayers() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--multiview-fixture"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["multiview-fixture-player-1"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["multiview-fixture-player-1"].label, "Engine 1 loads 1")
        select(app.buttons["live-channel-multiview"], in: app)
        XCTAssertTrue(app.buttons["live-multiview-add"].waitForExistence(timeout: 5))
        assertMetrics("Engines 1 loads 1 stops 0 audible 1", in: app)

        select(app.buttons["live-multiview-add"], in: app)
        select(app.descendants(matching: .any)["live-multiview-channel-sports-2"].firstMatch, in: app)
        assertMetrics("Engines 2 loads 2 stops 0 audible 1", in: app)
        select(app.buttons["Sports 2"], in: app)
        select(app.buttons["live-multiview-layout"], in: app)
        selectMenuItem("Corner", in: app)
        assertCornerLayout(in: app)
        assertMetrics("Engines 2 loads 2 stops 0 audible 1", in: app)
        select(app.buttons["live-multiview-layout"], in: app)
        selectMenuItem("Top left", in: app)
        assertCornerLayout(in: app, topLeft: true)
        selectAudio("Sports 1", in: app)
        XCTAssertEqual(app.buttons["Sports 1"].value as? String, "Audio on")
        selectAudio("Sports 2", in: app)
        XCTAssertEqual(app.buttons["Sports 2"].value as? String, "Audio on")
        select(app.buttons["live-multiview-expand"], in: app)
        select(app.buttons["live-multiview-collapse"], in: app)
        assertMetrics("Engines 2 loads 2 stops 0 audible 1", in: app)

        select(app.buttons["live-multiview-done"], in: app)
        XCTAssertTrue(app.staticTexts["multiview-fixture-player-2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["multiview-fixture-player-2"].label, "Engine 2 loads 1")
    }

    @MainActor
    private func selectAudio(_ channel: String, in app: XCUIApplication) {
        select(app.buttons["live-multiview-audio"], in: app)
        selectMenuItem(channel, identifierPrefix: "live-multiview-listen-", in: app)
        XCTAssertEqual(app.buttons[channel].value as? String, "Audio on", app.debugDescription)
        assertMetrics("Engines 2 loads 2 stops 0 audible 1", in: app)
    }

    @MainActor
    private func assertCornerLayout(
        in app: XCUIApplication, topLeft: Bool = false,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let main = app.buttons["Sports 1"]
        let inset = app.buttons["Sports 2"]
        let matches = NSPredicate { _, _ in
            guard main.exists, inset.exists, inset.frame.width < main.frame.width / 2 else { return false }
            return !topLeft || (inset.frame.midX < main.frame.midX && inset.frame.midY < main.frame.midY)
        }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: matches, object: nil)], timeout: 5),
            .completed, app.debugDescription, file: file, line: line
        )
    }

    @MainActor
    private func selectMenuItem(
        _ title: String, identifierPrefix: String = "", in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        // tvOS exposes Menu actions as focused collection cells, not AX buttons.
        let predicate = identifierPrefix.isEmpty
            ? NSPredicate(format: "label == %@", title)
            : NSPredicate(
                format: "label == %@ AND identifier BEGINSWITH %@", title, identifierPrefix
            )
        let item = app.cells.containing(predicate).firstMatch
        select(item, in: app, file: file, line: line)
    }

    @MainActor
    private func select(
        _ target: XCUIElement, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard target.waitForExistence(timeout: 5) else {
            XCTFail(
                "Missing target: \(target). Native focus: \(nativeFocus(in: app)). \(app.debugDescription)",
                file: file, line: line
            )
            return
        }
        var previousFrame: CGRect?
        var previousMoveWasVertical = false
        for _ in 0..<16 {
            let targetContainsFocus = target.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists
            if target.hasFocus || targetContainsFocus {
                XCUIRemote.shared.press(.select)
                return
            }
            let focused = focusedElement(in: app)
            guard focused.exists else {
                XCTContext.runActivity(named: "Native focus transition") { activity in
                    activity.add(XCTAttachment(string: nativeFocus(in: app)))
                }
                let movingUp = previousFrame.map { target.frame.midY < $0.midY } ?? false
                XCUIRemote.shared.press(movingUp ? .up : .down)
                continue
            }
            if (!target.identifier.isEmpty && focused.identifier == target.identifier) ||
               ((!target.identifier.isEmpty || !target.label.isEmpty) &&
               focused.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier == %@ AND label == %@", target.identifier, target.label
                )
            ).firstMatch.exists) {
                XCUIRemote.shared.press(.select)
                return
            }
            let destination = target.frame
            let origin = focused.frame
            let stalled = previousFrame == origin
            previousFrame = origin
            let below = destination.minY >= origin.maxY - 1
            let above = destination.maxY <= origin.minY + 1
            let horizontalGap = destination.minX >= origin.maxX - 1 || destination.maxX <= origin.minX + 1
            let verticalCenters = !horizontalGap &&
                abs(destination.midY - origin.midY) > abs(destination.midX - origin.midX)
            if (above || below || verticalCenters) && !(stalled && previousMoveWasVertical && horizontalGap) {
                XCUIRemote.shared.press(destination.midY > origin.midY ? .down : .up)
                previousMoveWasVertical = true
            } else {
                XCUIRemote.shared.press(destination.midX > origin.midX ? .right : .left)
                previousMoveWasVertical = false
            }
        }
        let focused = focusedElement(in: app)
        XCTFail(
            "Remote focus cannot reach \(target). Focus: \(focused.exists ? focused.debugDescription : "none"). " +
                "Native focus: \(nativeFocus(in: app)). \(app.debugDescription)",
            file: file, line: line
        )
    }

    @MainActor
    private func focusedElement(in app: XCUIApplication) -> XCUIElement {
        let reported = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).firstMatch
        guard !reported.exists else { return reported }
        let prefix = "focusWindowFrame="
        guard let component = nativeFocus(in: app).components(separatedBy: " | ")
            .first(where: { $0.hasPrefix(prefix) }) else { return reported }
        let frame = NSCoder.cgRect(for: String(component.dropFirst(prefix.count)))
        guard frame.width > 0, frame.height > 0 else { return reported }
        // SwiftUI context-menu panes can own UIKit focus without exposing AX hasFocus.
        return app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "live-multiview-pane-"
        )).allElementsBoundByIndex.first {
            let candidate = $0.frame
            return abs(candidate.midX - frame.midX) < 2 &&
                abs(candidate.midY - frame.midY) < 2
        } ?? reported
    }

    @MainActor
    private func nativeFocus(in app: XCUIApplication) -> String {
        let diagnostics = app.staticTexts["multiview-fixture-focus-diagnostics"]
        guard diagnostics.exists else { return "unavailable" }
        return diagnostics.value as? String ?? "unavailable"
    }

    @MainActor
    private func assertMetrics(
        _ expected: String, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let metrics = app.staticTexts["multiview-fixture-metrics"]
        let matches = NSPredicate { _, _ in metrics.exists && metrics.label == expected }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: matches, object: nil)], timeout: 5),
            .completed, app.debugDescription, file: file, line: line
        )
    }
}
