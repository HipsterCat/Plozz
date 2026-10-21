#if DEBUG && canImport(SwiftUI)
import FeatureLiveTVCore
import Foundation
import XCTest
@testable import FeatureLiveTV

@MainActor
final class PrototypeServerGuideRequestTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testRepeatedDeepGuideNeighborhoodLookupStaysBounded() {
        let model = model(count: 100_000)
        let rows = model.guideRowIDs
        let start = ContinuousClock.now
        for index in 99_700..<99_900 {
            let channels = PrototypeServerGuideRequest.nearbyChannelIDs(
                rows: rows, anchorIndex: model.guideRowIndex(near: rows[index]), limit: 48
            )
            XCTAssertEqual(channels.count, 48)
            XCTAssertEqual(channels.first, "channel-\(index - 3)")
        }
        let elapsed = start.duration(to: .now)
        print("Live TV guide neighborhoods: rows=100000 lookups=200 elapsed=\(elapsed)")
        XCTAssertLessThan(elapsed, .milliseconds(100),
                          "Guide movement must not walk the entire lineup on every view update")
    }

    func testFirstMiddleAndLastViewportsStayBounded() throws {
        let rows = rows(count: 100)
        let references = references(for: rows)
        for (anchor, expected) in [(0, 0..<12), (50, 47..<59), (99, 88..<100)] {
            let request = try XCTUnwrap(request(rows: rows, anchorIndex: anchor, references: references))
            XCTAssertEqual(request.channels.map(\.id), expected.map { "channel-\($0)" })
            XCTAssertLessThanOrEqual(request.channels.count, PrototypeServerGuideRequest.rowLimit)
        }
    }

    func testSmallCatalogDoesNotRequestOutsideItsRows() throws {
        let rows = rows(count: 3)
        let request = try XCTUnwrap(request(rows: rows, anchorIndex: 2, references: references(for: rows)))
        XCTAssertEqual(request.channels.map(\.id), rows.map(\.channelID))
    }

    func testOnlyServerChannelsInTheNeighborhoodAreRequested() throws {
        let rows = rows(count: 100)
        let references = references(for: [rows[0], rows[50], rows[99]])
        let request = try XCTUnwrap(request(rows: rows, anchorIndex: 50, references: references))
        XCTAssertEqual(request.channels.map(\.id), ["channel-50"])
        XCTAssertNil(self.request(rows: rows, anchorIndex: 20, references: references))
        XCTAssertNil(self.request(rows: [], references: references))
    }

    func testRepeatedFavoritesAndRecentRowsDoNotDuplicateRequests() throws {
        let rows = [
            LiveTVGuideRowID(channelID: "channel-0", section: .recent),
            LiveTVGuideRowID(channelID: "channel-0", section: .favorites),
            LiveTVGuideRowID(channelID: "channel-0"),
            LiveTVGuideRowID(channelID: "channel-1")
        ]
        let references = references(for: Array(rows.suffix(2)))
        let request = try XCTUnwrap(request(rows: rows, references: references))
        XCTAssertEqual(request.channels.map(\.id), ["channel-0", "channel-1"])
    }

    func testRemovedSectionAnchorKeepsItsChannelNeighborhood() throws {
        let model = model(count: 100)
        let rows = model.guideRowIDs
        let request = try XCTUnwrap(request(
            rows: rows,
            anchorIndex: model.guideRowIndex(near: .init(channelID: "channel-50", section: .favorites)),
            references: references(for: rows)
        ))
        XCTAssertEqual(request.channels.first?.id, "channel-47")
        XCTAssertTrue(request.channels.contains { $0.id == "channel-50" })
    }

    func testAuthorizationAndTimeWindowChangesInvalidateTaskIdentity() throws {
        let rows = rows(count: 1)
        let first = try XCTUnwrap(request(rows: rows, references: references(for: rows)))
        let refreshed = try XCTUnwrap(request(
            rows: rows, references: references(for: rows, authorizationID: "refreshed")
        ))
        let later = try XCTUnwrap(PrototypeServerGuideRequest(
            rows: rows, anchorIndex: nil, references: references(for: rows), enabledSourceIDs: ["source"],
            from: start.addingTimeInterval(86_400), to: start.addingTimeInterval(108_000)
        ))
        XCTAssertNotEqual(first, refreshed)
        XCTAssertNotEqual(first, later)
        XCTAssertEqual(first, request(rows: rows, references: references(for: rows)))
        XCTAssertEqual(first.to.timeIntervalSince(first.from), 21_600)
    }

    func testDisabledServerSourcesAreExcludedWithinTheWindow() throws {
        let rows = rows(count: 100)
        var references = references(for: rows)
        references["channel-1"] = LiveTVServerChannelReference(
            sourceID: "disabled", accountID: "account", authorizationID: "authorization", channelID: "channel-1"
        )
        let value = try XCTUnwrap(request(rows: rows, references: references))
        XCTAssertEqual(value.channels.map(\.id), ["channel-0"] + (2..<12).map { "channel-\($0)" })
        XCTAssertNil(PrototypeServerGuideRequest(
            rows: rows, anchorIndex: nil, references: references, enabledSourceIDs: [],
            from: start, to: start.addingTimeInterval(21_600)
        ))
    }

    func testInvalidAnchorIndicesFallBackToTheFirstWindow() {
        let rows = rows(count: 100)
        for index in [-1, 100, Int.max] {
            XCTAssertEqual(
                PrototypeServerGuideRequest.nearbyChannelIDs(rows: rows, anchorIndex: index, limit: 12),
                (0..<12).map { "channel-\($0)" }
            )
        }
    }

    private func model(count: Int) -> LiveTVPrototypeModel {
        LiveTVPrototypeModel(channels: (0..<count).map { index in
            LiveTVPrototypeChannel(
                id: "channel-\(index)", number: index, name: "Channel \(index)", category: "News",
                symbol: "tv", accent: 0, source: .iptv, tagline: ""
            )
        })
    }

    private func rows(count: Int) -> [LiveTVGuideRowID] {
        (0..<count).map { LiveTVGuideRowID(channelID: "channel-\($0)") }
    }

    private func references(
        for rows: [LiveTVGuideRowID], authorizationID: String = "authorization"
    ) -> [String: LiveTVServerChannelReference] {
        Dictionary(uniqueKeysWithValues: rows.map { row in
            (row.channelID, LiveTVServerChannelReference(
                sourceID: "source", accountID: "account", authorizationID: authorizationID,
                channelID: row.channelID
            ))
        })
    }

    private func request(
        rows: [LiveTVGuideRowID], anchorIndex: Int? = nil,
        references: [String: LiveTVServerChannelReference]
    ) -> PrototypeServerGuideRequest? {
        PrototypeServerGuideRequest(
            rows: rows, anchorIndex: anchorIndex, references: references, enabledSourceIDs: ["source"],
            from: start, to: start.addingTimeInterval(21_600)
        )
    }
}
#endif
