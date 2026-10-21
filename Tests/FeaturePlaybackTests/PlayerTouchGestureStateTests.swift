import XCTest
@testable import FeaturePlayback

@MainActor
final class PlayerTouchGestureStateTests: XCTestCase {
    func testRepeatedTapsAccumulateFromTheirTargetDespiteStalePlaybackClock() {
        let state = PlayerTouchGestureState()
        defer { state.cancel() }
        for count in 1...7 {
            XCTAssertEqual(state.seek(by: 10, from: 50, within: 0...200), 50 + Double(count * 10))
            XCTAssertEqual(state.skip?.seconds, Double(count * 10))
            XCTAssertEqual(state.skip?.pulse, count)
        }
    }

    func testConfiguredIntervalsAndDirectionChangesAreIndependent() {
        let state = PlayerTouchGestureState()
        defer { state.cancel() }
        XCTAssertEqual(state.seek(by: 5, from: 100, within: 0...300), 105)
        XCTAssertEqual(state.seek(by: 5, from: 100, within: 0...300), 110)
        XCTAssertEqual(state.skip?.seconds, 10)
        XCTAssertEqual(state.seek(by: -30, from: 100, within: 0...300), 80)
        XCTAssertEqual(state.skip?.seconds, -30)
        XCTAssertEqual(state.seek(by: -30, from: 100, within: 0...300), 50)
        XCTAssertEqual(state.skip?.seconds, -60)
    }

    func testBoundariesNeverAdvertiseASeekBeyondThePlayableRange() {
        let state = PlayerTouchGestureState()
        defer { state.cancel() }
        XCTAssertEqual(state.seek(by: 30, from: 95, within: 0...99), 99)
        XCTAssertEqual(state.skip?.seconds, 4)
        XCTAssertNil(state.seek(by: 30, from: 95, within: 0...99))
        XCTAssertEqual(state.skip?.seconds, 4)
        state.clearSkip()
        XCTAssertEqual(state.seek(by: -30, from: 3, within: 0...99), 0)
        XCTAssertEqual(state.skip?.seconds, -3)
    }

    func testLiveWindowIsNotAssumedToStartAtZeroAndCanMove() {
        let state = PlayerTouchGestureState()
        defer { state.cancel() }
        XCTAssertEqual(state.seek(by: -30, from: 1090, within: 1006...1100), 1060)
        XCTAssertEqual(state.seek(by: -30, from: 1091, within: 1012...1106), 1030)
        XCTAssertEqual(state.seek(by: -30, from: 1092, within: 1018...1112), 1018)
        XCTAssertEqual(state.skip?.seconds, -72)
    }

    func testNewBurstUsesCurrentPositionAndBoostCancelsSkipFeedback() {
        let state = PlayerTouchGestureState()
        defer { state.cancel() }
        _ = state.seek(by: 10, from: 20, within: 0...100)
        state.clearSkip()
        XCTAssertEqual(state.seek(by: 10, from: 60, within: 0...100), 70)
        XCTAssertEqual(state.skip?.seconds, 10)
        state.showBoost(rate: 2)
        XCTAssertNil(state.skip)
        XCTAssertEqual(state.boostRate, 2)
        XCTAssertTrue(state.isActive)
        state.cancel()
        XCTAssertFalse(state.isActive)
    }

    func testUnavailableTimelineCannotStartASeek() {
        let state = PlayerTouchGestureState()
        XCTAssertNil(state.seek(by: 10, from: .nan, within: 0...100))
        XCTAssertNil(state.seek(by: .infinity, from: 20, within: 0...100))
        XCTAssertNil(state.seek(by: 10, from: 20, within: 0...0))
        XCTAssertNil(state.skip)
    }

    func testFeedbackExpiresAndReleaseDoesNotRemainAnActiveGesture() async throws {
        let state = PlayerTouchGestureState()
        defer { state.cancel() }
        _ = state.seek(by: 10, from: 20, within: 0...100)
        try await Task.sleep(for: .milliseconds(1400))
        XCTAssertNil(state.skip)
        XCTAssertFalse(state.isActive)
        state.isPinching = true
        XCTAssertTrue(state.isActive)
        state.cancel()
        XCTAssertFalse(state.isActive)
    }
}
