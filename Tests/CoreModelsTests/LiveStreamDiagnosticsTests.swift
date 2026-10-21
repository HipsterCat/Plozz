import XCTest

@testable import CoreModels

final class LiveStreamDiagnosticsTests: XCTestCase {
    func testAccessLogFoldsEveryVariantEvent() {
        var facts = PlaybackDiagnostics.LiveStreamFacts()
        facts.apply(accessLog: [
            .init(playbackType: "LIVE", startupTime: 1.25, mediaRequests: 4, bytesTransferred: 4_000, downloadOverdue: 0),
            .init(playbackType: "LIVE", startupTime: -1, mediaRequests: 10, bytesTransferred: 6_000, downloadOverdue: 2),
        ])
        XCTAssertEqual(facts.playlistType, "LIVE")
        XCTAssertEqual(facts.startupSeconds, 1.25)
        XCTAssertEqual(facts.variantSwitches, 1)
        XCTAssertEqual(facts.segmentRequests, 14)
        XCTAssertEqual(facts.bytesTransferred, 10_000)
        XCTAssertEqual(facts.overdueSegments, 2)
    }

    func testUnknownCountersDoNotGoNegative() {
        var facts = PlaybackDiagnostics.LiveStreamFacts()
        facts.apply(accessLog: [
            .init(playbackType: "", startupTime: -1, mediaRequests: -1, bytesTransferred: -1, downloadOverdue: -1),
        ])
        XCTAssertNil(facts.playlistType)
        XCTAssertNil(facts.startupSeconds)
        XCTAssertEqual(facts.segmentRequests, 0)
        XCTAssertEqual(facts.bytesTransferred, 0)
    }

    func testWindowAndErrorText() {
        let facts = PlaybackDiagnostics.LiveStreamFacts(
            windowSeconds: 7_200, errorCount: 3, lastErrorStatus: 404
        )
        XCTAssertEqual(facts.windowText, "2:00:00")
        XCTAssertEqual(facts.errorsText, "3 · last 404")
        XCTAssertNil(PlaybackDiagnostics.LiveStreamFacts(windowSeconds: 0).windowText)
    }
}
