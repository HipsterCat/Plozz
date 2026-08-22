import CoreModels
import Foundation
import XCTest

@testable import ProviderKinoPubDemo

/// The demo synthesises the season/episode graph the catalogue does not carry,
/// and the whole graph is addressed by id alone. These pin that down, because
/// the failure mode — a series page that opens onto nothing — is silent.
final class KinoPubDemoProviderTests: XCTestCase {
    private func makeProvider() -> KinoPubDemoProvider {
        let server = MediaServer(
            id: "test",
            name: "kino.pub",
            baseURL: URL(string: "https://example.invalid")!,
            provider: .jellyfin
        )
        let session = UserSession(
            server: server,
            userID: "demo",
            userName: "Демо",
            deviceID: "test-device",
            accessToken: "test"
        )
        return KinoPubDemoProvider(session: session, accountID: KinoPubDemo.accountID)
    }

    private func firstSeries() throws -> MediaItem {
        let all = KinoPubDemoCatalog.bundled.items.filter { $0.mediaKind == .series }
        let raw = try XCTUnwrap(all.first, "the demo catalogue has no series at all")
        return raw.mediaItem(accountID: KinoPubDemo.accountID, resume: nil)
    }

    // MARK: - Ids

    func testRefRoundTripsThroughItsStringForm() {
        let cases: [KinoPubDemoRef] = [
            .title("52759"),
            .season("52759", 2),
            .episode("52759", 2, 7),
        ]
        for ref in cases {
            switch (ref, KinoPubDemoRef(ref.id)) {
            case (.title(let a), .title(let b)):
                XCTAssertEqual(a, b)
            case (.season(let a, let n), .season(let b, let m)):
                XCTAssertEqual(a, b); XCTAssertEqual(n, m)
            case (.episode(let a, let s, let n), .episode(let b, let t, let m)):
                XCTAssertEqual(a, b); XCTAssertEqual(s, t); XCTAssertEqual(n, m)
            default:
                XCTFail("\(ref.id) did not parse back to the same case")
            }
        }
    }

    func testAPlainCatalogueIdStaysATitle() {
        guard case .title(let id) = KinoPubDemoRef("52759") else {
            return XCTFail("a bare id must read as a title")
        }
        XCTAssertEqual(id, "52759")
    }

    // MARK: - The graph

    func testASeriesHasSeasons() async throws {
        let provider = makeProvider()
        let series = try firstSeries()
        let seasons = try await provider.children(of: series.id)

        XCTAssertFalse(seasons.isEmpty, "a series must open onto its seasons")
        XCTAssertTrue(seasons.allSatisfy { $0.kind == .season })
        XCTAssertEqual(seasons.map(\.seasonNumber), Array(1...seasons.count))
        XCTAssertTrue(seasons.allSatisfy { $0.seriesID == series.id })
    }

    func testASeasonHasEpisodes() async throws {
        let provider = makeProvider()
        let series = try firstSeries()
        let seasons = try await provider.children(of: series.id)
        let season = try XCTUnwrap(seasons.first)
        let episodes = try await provider.children(of: season.id)

        XCTAssertFalse(episodes.isEmpty, "a season must open onto its episodes")
        XCTAssertTrue(episodes.allSatisfy { $0.kind == .episode })
        XCTAssertEqual(episodes.map(\.episodeNumber), Array(1...episodes.count))
        XCTAssertTrue(episodes.allSatisfy { $0.seasonID == season.id })
        XCTAssertTrue(episodes.allSatisfy { $0.seriesID == series.id })
        XCTAssertTrue(episodes.allSatisfy { $0.parentTitle == series.title })
    }

    func testAnEpisodeIsALeaf() async throws {
        let provider = makeProvider()
        let series = try firstSeries()
        let seasons = try await provider.children(of: series.id)
        let season = try XCTUnwrap(seasons.first)
        let episodes = try await provider.children(of: season.id)
        let episode = try XCTUnwrap(episodes.first)

        let below = try await provider.children(of: episode.id)
        XCTAssertTrue(below.isEmpty, "an episode has nothing under it")
    }

    func testEpisodeCountsAreStableAcrossCalls() async throws {
        let provider = makeProvider()
        let series = try firstSeries()
        let seasons = try await provider.children(of: series.id)
        for season in seasons {
            let first = try await provider.children(of: season.id).count
            let second = try await provider.children(of: season.id).count
            XCTAssertEqual(first, second, "episode counts must not shuffle between calls")
            XCTAssertTrue((8...12).contains(first), "unexpected episode count \(first)")
        }
    }

    // MARK: - Resolving any level by id alone

    func testEveryLevelResolvesFromItsIdWithNothingElseHeld() async throws {
        let provider = makeProvider()
        let series = try firstSeries()
        let seasons = try await provider.children(of: series.id)
        let season = try XCTUnwrap(seasons.first)
        let episodes = try await provider.children(of: season.id)
        let episode = try XCTUnwrap(episodes.first)

        // A restored navigation stack hands back ids and nothing else.
        let resolvedSeries = try await provider.item(id: series.id)
        let resolvedSeason = try await provider.item(id: season.id)
        let resolvedEpisode = try await provider.item(id: episode.id)

        XCTAssertEqual(resolvedSeries.kind, .series)
        XCTAssertEqual(resolvedSeason.kind, .season)
        XCTAssertEqual(resolvedSeason.seasonNumber, season.seasonNumber)
        XCTAssertEqual(resolvedEpisode.kind, .episode)
        XCTAssertEqual(resolvedEpisode.episodeNumber, episode.episodeNumber)
        XCTAssertEqual(resolvedEpisode.title, episode.title)
    }

    func testAnUnknownIdIsReportedAsNotFound() async {
        let provider = makeProvider()
        do {
            _ = try await provider.item(id: "no-such-title:s:3")
            XCTFail("expected a notFound")
        } catch KinoPubDemoError.notFound {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Home

    func testHomeRailsAreNotEmpty() async throws {
        let provider = makeProvider()
        let resumed = try await provider.continueWatching(limit: 10)
        let latest = try await provider.latest(limit: 10)

        XCTAssertFalse(resumed.isEmpty)
        XCTAssertFalse(latest.isEmpty)
        XCTAssertTrue(
            resumed.contains { ($0.resumePosition ?? 0) > 0 },
            "Continue Watching without a single resume position renders no progress bars"
        )
    }
}
