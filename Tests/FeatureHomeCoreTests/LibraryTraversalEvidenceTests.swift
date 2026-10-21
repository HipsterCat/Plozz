import XCTest
@testable import FeatureHomeCore

final class LibraryTraversalEvidenceTests: XCTestCase {
    func testExactRapidRoundTripIsAccepted() throws {
        let (before, after) = roundTrip(rows: 18)
        let evidence = try validate(before, after, .stepped(path: (0...18).map { $0 * 6 }))
        XCTAssertEqual(evidence.transitions, 36)
        XCTAssertEqual(evidence.deepestRow, 18)
    }

    func testClampedAndDroppedRapidInputsAreRejected() {
        for rows in [0, 6, 17] {
            let (before, after) = roundTrip(rows: rows)
            XCTAssertThrowsError(try validate(before, after, .stepped(path: (0...18).map { $0 * 6 })))
        }
    }

    func testHeldTraversalRequiresMovementButAllowsDifferentRepeatThroughput() throws {
        let (before, after) = roundTrip(rows: 0)
        XCTAssertThrowsError(try validate(before, after, .held(minimumRows: 18)))
        for rows in [18, 24, 30] {
            let (before, after) = roundTrip(rows: rows)
            let evidence = try validate(before, after, .held(minimumRows: 18))
            XCTAssertEqual(evidence.deepestRow, rows)
        }
    }

    func testChangedGridOrGenerationCannotReuseCalibration() {
        let (before, after) = roundTrip(rows: 18)
        let replacement = LibraryTraversalRecorder().snapshot(generation: 1, columns: 6, total: 1_000)
        XCTAssertThrowsError(try validate(before, replacement, .idle))
        let changed = LibraryTraversalSnapshot(
            identity: after.identity, generation: 2, columns: after.columns, total: after.total,
            sequence: after.sequence, focusedIndex: after.focusedIndex, events: after.events
        )
        XCTAssertThrowsError(try validate(before, changed, .held(minimumRows: 18)))
    }

    func testHistoryOverflowFailsClosed() {
        let (before, after) = roundTrip(rows: 18, capacity: 4)
        XCTAssertThrowsError(try validate(before, after, .held(minimumRows: 18))) {
            XCTAssertEqual($0 as? LibraryTraversalValidation.Failure, .incompleteHistory)
        }
    }

    func testPreAndPostWindowFocusActivityIsExcluded() throws {
        var recorder = initializedRecorder()
        let before = snapshot(recorder)
        recorder.record(from: 0, to: 6, loaded: true, uptime: 8)
        recorder.record(from: 6, to: 0, loaded: true, uptime: 9)
        recorder.record(from: 0, to: 6, loaded: true, uptime: 31)
        recorder.record(from: 6, to: 0, loaded: true, uptime: 32)
        let evidence = try validate(before, snapshot(recorder), .idle)
        XCTAssertEqual(evidence.transitions, 0)
    }

    func testUnloadedCardsAndGridExcursionsAreRejected() {
        for unloaded in [false, true] {
            var recorder = initializedRecorder()
            let before = snapshot(recorder)
            recorder.record(from: 0, to: unloaded ? 6 : nil, loaded: false, uptime: 11)
            recorder.record(from: unloaded ? 6 : nil, to: 0, loaded: true, uptime: 12)
            XCTAssertThrowsError(try validate(before, snapshot(recorder), .held(minimumRows: 1))) {
                XCTAssertEqual($0 as? LibraryTraversalValidation.Failure, .invalidFocus)
            }
        }
    }

    func testSidewaysMovesAndUnfinishedReturnsAreRejected() {
        var recorder = initializedRecorder()
        let before = snapshot(recorder)
        recorder.record(from: 0, to: 1, loaded: true, uptime: 11)
        recorder.record(from: 1, to: 0, loaded: true, uptime: 12)
        XCTAssertThrowsError(try validate(before, snapshot(recorder), .held(minimumRows: 1)))
        recorder.record(from: 0, to: 6, loaded: true, uptime: 13)
        XCTAssertThrowsError(try validate(before, snapshot(recorder), .held(minimumRows: 1)))
    }

    func testNonfiniteOrOutOfOrderTimestampsAreRejected() {
        for invalid in [Double.nan, 9] {
            var recorder = initializedRecorder()
            let before = snapshot(recorder)
            recorder.record(from: 0, to: 6, loaded: true, uptime: 11)
            recorder.record(from: 6, to: 0, loaded: true, uptime: invalid)
            XCTAssertThrowsError(try validate(before, snapshot(recorder), .held(minimumRows: 1)))
        }
    }

    private func initializedRecorder(capacity: Int = 512) -> LibraryTraversalRecorder {
        var recorder = LibraryTraversalRecorder(capacity: capacity)
        recorder.record(from: nil, to: 0, loaded: true, uptime: 0)
        return recorder
    }

    private func snapshot(_ recorder: LibraryTraversalRecorder) -> LibraryTraversalSnapshot {
        recorder.snapshot(generation: 1, columns: 6, total: 1_000)
    }

    private func roundTrip(rows: Int, capacity: Int = 512) -> (LibraryTraversalSnapshot, LibraryTraversalSnapshot) {
        var recorder = initializedRecorder(capacity: capacity)
        let before = snapshot(recorder)
        let down = (0...rows).map { $0 * 6 }
        var from = 0
        for (offset, index) in (Array(down.dropFirst()) + down.dropLast().reversed()).enumerated() {
            recorder.record(from: from, to: index, loaded: true, uptime: 10 + Double(offset) * 0.01)
            from = index
        }
        return (before, snapshot(recorder))
    }

    private func validate(
        _ before: LibraryTraversalSnapshot,
        _ after: LibraryTraversalSnapshot,
        _ mode: LibraryTraversalValidation.Mode
    ) throws -> LibraryTraversalValidation.Evidence {
        try LibraryTraversalValidation.validate(before: before, after: after, start: 10, end: 30, mode: mode)
    }
}
