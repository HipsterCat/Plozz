import XCTest
import CoreModels
@testable import FeatureHomeCore

/// An episode's preference key is its SERIES', so a per-file id stored there can
/// only ever match the one episode it was saved from.
final class DetailPlaybackSelectionTests: XCTestCase {
    func testPlayPlaceholderIsOnlyForAnUnresolvedOwnedContainer() {
        let show = MediaItem(id: "show", title: "Show", kind: .series)
        XCTAssertTrue(DetailPlaybackSelection.showsPlayPlaceholder(
            for: show, hasPlayTarget: false, childrenLoaded: false, seasonLoadState: nil
        ))
        XCTAssertTrue(DetailPlaybackSelection.showsPlayPlaceholder(
            for: show, hasPlayTarget: false, childrenLoaded: true, seasonLoadState: .notLoaded
        ))
        XCTAssertFalse(DetailPlaybackSelection.showsPlayPlaceholder(
            for: show, hasPlayTarget: true, childrenLoaded: false, seasonLoadState: .notLoaded
        ))
        for state in [SeasonLoadState?.none, .some(.loaded([])), .some(.failed)] {
            XCTAssertFalse(DetailPlaybackSelection.showsPlayPlaceholder(
                for: show, hasPlayTarget: false, childrenLoaded: true, seasonLoadState: state
            ))
        }
        var external = show
        external.locallyValidatedPlayableSource = false
        XCTAssertFalse(DetailPlaybackSelection.showsPlayPlaceholder(
            for: external, hasPlayTarget: false, childrenLoaded: false, seasonLoadState: nil
        ))
        let movie = MediaItem(id: "movie", title: "Movie", kind: .movie)
        XCTAssertFalse(DetailPlaybackSelection.showsPlayPlaceholder(
            for: movie, hasPlayTarget: true, childrenLoaded: false, seasonLoadState: nil
        ))
    }

    func testEpisodeMetadataEnrichmentKeepsTheContinueWatchingProgress() {
        let resume = MediaItem(
            id: "episode", title: "Episode", kind: .episode,
            runtime: 3_000, resumePosition: 867, playedPercentage: 0.289,
            sourceAccountID: "plex"
        )
        var loaded = resume
        loaded.resumePosition = nil
        loaded.playedPercentage = nil
        loaded.overview = "Full episode overview"
        let enriched = DetailPlaybackSelection.applyingResumeItem(resume, to: loaded)
        XCTAssertEqual(enriched.overview, "Full episode overview")
        XCTAssertEqual(enriched.resumePosition, 867)
        XCTAssertEqual(enriched.resumeProgressFraction, 0.289)
    }

    func testContinueWatchingLookupIsScopedToTheSelectedSourceAndTitle() {
        let show = MediaItem(id: "show", title: "Show", kind: .series, sourceAccountID: "plex")
        let episode = MediaItem(
            id: "episode", title: "Episode", kind: .episode,
            seriesID: show.id, sourceAccountID: "plex"
        )
        var otherAccount = episode
        otherAccount.sourceAccountID = "other"
        var otherSeries = episode
        otherSeries.seriesID = "other-show"
        var external = episode
        external.locallyValidatedPlayableSource = false
        XCTAssertNil(DetailPlaybackSelection.resumeItem(for: show, in: [otherAccount, otherSeries, external]))
        XCTAssertEqual(DetailPlaybackSelection.resumeItem(for: show, in: [episode])?.id, episode.id)
    }

    func testAnEpisodeIgnoresAStoredFileIDAndUsesTheRememberedKind() {
        // The bug this guards: picking a version on episode 3 stored that file's
        // id under the series key, so replaying episode 3 returned it while every
        // other episode matched the remembered shape — one show behaving two ways.
        var hevc = MediaVersion(id: "ep3-hevc", height: 1080)
        hevc.videoCodec = "hevc"
        var av1 = MediaVersion(id: "ep3-av1", height: 1080)
        av1.videoCodec = "av1"

        let store = VersionPreferenceStore(
            defaults: UserDefaults(suiteName: "plozz.tests.episode-id-\(UUID().uuidString)")!
        )
        // A stale explicit pick, plus the shape the viewer actually wants.
        store.setPreferredVersionID("ep3-hevc", forTitle: "series-1")
        store.setPreferredVersionDescriptor(
            MediaVersionDescriptor(version: av1),
            forTitle: "series-1"
        )

        var episode = MediaItem(id: "ep3", title: "Episode 3", kind: .episode)
        episode.seriesID = "series-1"

        XCTAssertEqual(
            DetailPlaybackSelection.preferredVersionID(
                for: episode,
                versions: [hevc, av1],
                versionOverride: nil,
                preferences: store,
                capabilities: .detected()
            ),
            "ep3-av1"
        )
    }

    func testAMovieStillHonoursItsExactFile() {
        // The id remains right where the key IS the item's own: same title, same
        // files, and the viewer picked that one.
        var small = MediaVersion(id: "movie-1080", height: 1080)
        small.videoCodec = "h264"
        var large = MediaVersion(id: "movie-2160", height: 2160)
        large.videoCodec = "hevc"

        let store = VersionPreferenceStore(
            defaults: UserDefaults(suiteName: "plozz.tests.movie-id-\(UUID().uuidString)")!
        )
        store.setPreferredVersionID("movie-1080", forTitle: "movie-1")

        let movie = MediaItem(id: "movie-1", title: "A Film", kind: .movie)

        XCTAssertEqual(
            DetailPlaybackSelection.preferredVersionID(
                for: movie,
                versions: [small, large],
                versionOverride: nil,
                preferences: store,
                capabilities: .detected()
            ),
            "movie-1080"
        )
    }
}
