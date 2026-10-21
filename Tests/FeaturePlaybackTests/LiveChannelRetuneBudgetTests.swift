import XCTest
@testable import FeaturePlayback

final class LiveChannelRetuneBudgetTests: XCTestCase {
    private func exhaustedBudget() -> LiveChannelRetuneBudget {
        var budget = LiveChannelRetuneBudget()
        for time in [0.0, 20, 40] { budget.recordAttempt(uptime: time) }
        return budget
    }

    func testHealthyPlaybackRestoresBudgetAtFiveMinutesNotBefore() {
        var budget = exhaustedBudget()
        for tick in 0..<300 {
            budget.observeHealthyPlayback(position: Double(tick), uptime: 40 + Double(tick))
            XCTAssertTrue(budget.isExhausted)
        }
        budget.observeHealthyPlayback(position: 300, uptime: 340)
        XCTAssertEqual(budget.attempts, 0)
        budget.recordAttempt(uptime: 340)
        XCTAssertEqual(budget.attempts, 1)
        XCTAssertEqual(budget.delayBeforeNextAttempt(uptime: 345), 15)
    }

    func testElapsedTimeAndFrozenPlayheadCannotRestoreBudget() {
        var budget = exhaustedBudget()
        for tick in 0...3_600 {
            budget.observeHealthyPlayback(position: 100, uptime: 40 + Double(tick))
        }
        XCTAssertTrue(budget.isExhausted)
        budget.observeHealthyPlayback(position: 101, uptime: 7_200)
        XCTAssertTrue(budget.isExhausted)
    }

    func testNormalCoarseClockPublicationStillRestoresBudget() {
        var budget = exhaustedBudget()
        for tick in 0...1_200 {
            budget.observeHealthyPlayback(position: Double(tick / 4), uptime: 40 + Double(tick) / 4)
        }
        XCTAssertFalse(budget.isExhausted)
    }

    func testInterruptedProgressMustStartANewHealthyWindow() {
        var budget = exhaustedBudget()
        for tick in 0..<300 {
            budget.observeHealthyPlayback(position: Double(tick), uptime: 40 + Double(tick))
        }
        budget.interruptHealthyPlayback()
        for tick in 300..<600 {
            budget.observeHealthyPlayback(position: Double(tick), uptime: 40 + Double(tick))
            XCTAssertTrue(budget.isExhausted)
        }
        budget.observeHealthyPlayback(position: 600, uptime: 640)
        XCTAssertFalse(budget.isExhausted)
    }

    func testLongObservationGapOrClockDiscontinuityCannotCountAsHealthyPlayback() {
        for (position, time) in [(300.0, 1_000.0), (0, 340), (300, 10), (.nan, 340), (300, .infinity)] {
            var budget = exhaustedBudget()
            for tick in 0..<300 {
                budget.observeHealthyPlayback(position: Double(tick), uptime: 40 + Double(tick))
            }
            budget.observeHealthyPlayback(position: position, uptime: time)
            budget.observeHealthyPlayback(position: 301, uptime: 341)
            XCTAssertTrue(budget.isExhausted)
        }
    }

    func testNewAttemptDiscardsEarlierHealthyCredit() {
        var budget = LiveChannelRetuneBudget()
        budget.recordAttempt(uptime: 0)
        for tick in 0..<300 {
            budget.observeHealthyPlayback(position: Double(tick), uptime: Double(tick))
        }
        budget.recordAttempt(uptime: 300)
        budget.observeHealthyPlayback(position: 300, uptime: 300)
        XCTAssertEqual(budget.attempts, 2)
        budget.recordAttempt(uptime: 320)
        XCTAssertTrue(budget.isExhausted)
    }
}
