#if os(tvOS)
import SwiftUI
import XCTest
@testable import AppShell

@MainActor
final class TVProfileForegroundStateTests: XCTestCase {
    func testOnlyARealBackgroundAfterBrowsingLocks() {
        let state = TVProfileForegroundState()
        XCTAssertFalse(state.shouldLock(after: .inactive))
        XCTAssertFalse(state.shouldLock(after: .background))
        XCTAssertFalse(state.shouldLock(after: .active))
        XCTAssertFalse(state.shouldLock(after: .inactive))
        XCTAssertFalse(state.shouldLock(after: .active), "Control Center does not lock.")
        XCTAssertFalse(state.shouldLock(after: .inactive))
        XCTAssertTrue(state.shouldLock(after: .background))
        XCTAssertFalse(state.shouldLock(after: .background))
        XCTAssertFalse(state.shouldLock(after: .active))
        XCTAssertTrue(state.shouldLock(after: .background), "A direct background transition also locks.")
    }

    func testOpenPlayerSurvivesSuspensionButClosingItRestoresTheBrowsingGate() {
        let state = TVProfileForegroundState()
        let player = UUID()
        state.setPlayback(true, id: player)
        XCTAssertFalse(state.shouldLock(after: .active))
        XCTAssertFalse(state.shouldLock(after: .inactive))
        state.setPlayback(false, id: player)
        XCTAssertFalse(state.shouldLock(after: .background), "Suspension must not revoke the captured player exemption.")
        XCTAssertFalse(state.shouldLock(after: .active))
        XCTAssertFalse(state.shouldLock(after: .inactive))
        XCTAssertTrue(state.shouldLock(after: .background))
    }

    func testMultiplePlayersBalanceTheirOwnPresence() {
        let state = TVProfileForegroundState()
        let first = UUID(), second = UUID()
        state.setPlayback(true, id: first)
        state.setPlayback(true, id: second)
        state.setPlayback(false, id: first)
        XCTAssertFalse(state.shouldLock(after: .active))
        XCTAssertFalse(state.shouldLock(after: .background))
        state.setPlayback(false, id: second)
        XCTAssertFalse(state.shouldLock(after: .active))
        XCTAssertTrue(state.shouldLock(after: .background))
    }

    func testExternalHandoffExemptsOnlyItsOwnDeparture() {
        let state = TVProfileForegroundState()
        XCTAssertFalse(state.shouldLock(after: .active))
        XCTAssertFalse(state.shouldLock(after: .inactive, leavingForExternalPlayer: true))
        XCTAssertFalse(state.shouldLock(after: .background))
        XCTAssertFalse(state.shouldLock(after: .active))
        XCTAssertFalse(state.shouldLock(after: .inactive))
        XCTAssertTrue(state.shouldLock(after: .background))
    }
}
#endif
