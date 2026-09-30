import XCTest

@MainActor
final class PhysicalSubtitleInputTests: XCTestCase {
    func testObserveExistingSubtitleEditor() throws {
        guard ProcessInfo.processInfo.environment["PLOZZ_SUBTITLE_EXISTING_APP"] == "1" else {
            throw XCTSkip("Requires an explicitly selected physical TV and its already-running Plozz app.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz")
        XCTAssertEqual(app.state, .runningForeground, "Do not relaunch or replace the current playback session.")
        guard app.state == .runningForeground else { return }
        let exercise = ProcessInfo.processInfo.environment["PLOZZ_SUBTITLE_EXERCISE_INPUT"] == "1"
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Text Size,")).firstMatch
        if exercise {
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in row.exists && row.hasFocus }, object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 120), .completed,
                           "Open the affected Text Size row while the physical runner is attached.")
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Existing Plozz accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Existing Plozz subtitle editor"
        image.lifetime = .keepAlways
        add(image)
        guard exercise else { return }
        XCTAssertTrue(row.exists && row.hasFocus, "Leave the affected Text Size row selected before this test.")
        guard row.exists && row.hasFocus else { return }
        func value() throws -> Int {
            let label = row.label
            let pattern = try NSRegularExpression(pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*%"#)
            let match = try XCTUnwrap(pattern.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)))
            let range = try XCTUnwrap(Range(match.range(at: 1), in: label))
            let number = try XCTUnwrap(Int(label[range]), "Use a whole-percentage Text Size so the test can restore it.")
            return try XCTUnwrap((20...400).contains(number) ? number : nil)
        }
        func capture(_ name: String) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = name
            tree.lifetime = .keepAlways
            add(tree)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = name
            image.lifetime = .keepAlways
            add(image)
        }
        let initial = try value()
        let delta = initial >= 28 ? -1 : 1
        let firstDirection: XCUIRemote.Button = delta < 0 ? .left : .right
        let returnDirection: XCUIRemote.Button = delta < 0 ? .right : .left
        for index in 1...8 {
            XCUIRemote.shared.press(firstDirection)
            guard row.hasFocus else {
                capture("Focus escaped on first-direction click \(index)")
                XCTFail("Text Size lost focus on first-direction click \(index).")
                return
            }
            XCTAssertEqual(try value(), initial + delta * index)
        }
        for index in 1...8 {
            XCUIRemote.shared.press(returnDirection)
            guard row.hasFocus else {
                capture("Focus escaped on return-direction click \(index)")
                XCTFail("Text Size lost focus on return-direction click \(index).")
                return
            }
            XCTAssertEqual(try value(), initial + delta * (8 - index))
        }
        let holdDirection: XCUIRemote.Button = initial >= 40 ? .left : .right
        XCUIRemote.shared.press(holdDirection, forDuration: 1.5)
        capture("After holding a direction in real playback")
        XCTAssertTrue(row.hasFocus)
        guard row.hasFocus else { return }
        let afterHold = try value()
        if holdDirection == .left {
            XCTAssertLessThan(afterHold, initial - 2)
        } else {
            XCTAssertGreaterThan(afterHold, initial + 2)
        }
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(try value(), afterHold)
        let restoreDirection: XCUIRemote.Button = afterHold < initial ? .right : .left
        for _ in 0..<abs(initial - afterHold) {
            XCUIRemote.shared.press(restoreDirection)
            guard row.hasFocus else {
                capture("Focus escaped while restoring Text Size")
                XCTFail("Text Size lost focus while restoring its original value.")
                return
            }
        }
        XCTAssertEqual(try value(), initial)
    }
}
