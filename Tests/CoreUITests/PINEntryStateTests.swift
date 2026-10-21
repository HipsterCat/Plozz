import XCTest
@testable import CoreUI

@MainActor
final class PINEntryStateTests: XCTestCase {
    func testCancellingDuringFourthDigitHoldPreventsSubmissionAndAllowsRetry() async throws {
        let entry = PINEntryState()
        for digit in "1234" {
            entry.appendDigit(String(digit)) { _ in XCTFail("A cancelled PIN must never be submitted.") }
        }
        XCTAssertEqual(entry.pin, "1234")
        XCTAssertTrue(entry.isCommitting)
        entry.reset()
        XCTAssertEqual(entry.pin, "")
        XCTAssertFalse(entry.isCommitting)
        try await Task.sleep(for: .milliseconds(300))

        let submitted = expectation(description: "A fresh PIN is submitted")
        submitted.assertForOverFulfill = true
        for digit in "5678" {
            entry.appendDigit(String(digit)) { pin in
                XCTAssertEqual(pin, "5678")
                XCTAssertEqual(entry.pin, "")
                XCTAssertFalse(entry.isCommitting)
                submitted.fulfill()
            }
        }
        await fulfillment(of: [submitted], timeout: 2)
    }

    func testCancelledTaskCannotResetANewerEntry() async {
        let entry = PINEntryState()
        for digit in "1234" {
            entry.appendDigit(String(digit)) { _ in XCTFail("The old task must not submit.") }
        }
        entry.reset()
        let submitted = expectation(description: "Only the replacement PIN is submitted")
        for digit in "5678" {
            entry.appendDigit(String(digit)) { pin in
                XCTAssertEqual(pin, "5678")
                submitted.fulfill()
            }
        }
        await Task.yield()
        XCTAssertEqual(entry.pin, "5678")
        XCTAssertTrue(entry.isCommitting)
        await fulfillment(of: [submitted], timeout: 2)
    }

    func testPartialEntryResetAndCompletedHoldIgnoreExtraInput() async {
        let entry = PINEntryState()
        entry.appendDigit("9") { _ in XCTFail("A partial PIN cannot submit.") }
        entry.reset()
        let submitted = expectation(description: "Complete PIN is submitted once")
        for digit in "1234" {
            entry.appendDigit(String(digit)) { pin in
                XCTAssertEqual(pin, "1234")
                submitted.fulfill()
            }
        }
        entry.appendDigit("5") { _ in XCTFail("An extra digit cannot schedule another submission.") }
        entry.deleteDigit()
        XCTAssertEqual(entry.pin, "1234")
        await fulfillment(of: [submitted], timeout: 2)
    }
}
