import XCTest
@testable import CoreModels

final class SeasonEpisodeListTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_783_368_000)

    private var series: MediaItem {
        var item = MediaItem(id: "show", title: "Show", kind: .series, providerIDs: ["Tmdb": "100"])
        item.sourceAccountID = "server-a"
        return item
    }

    private func owned(_ number: Int, id: String? = nil, tmdbID: Int? = nil) -> MediaItem {
        var item = MediaItem(
            id: id ?? "episode-\(number)", title: "Episode \(number)", kind: .episode,
            seasonNumber: 8, episodeNumber: number, seriesID: "show"
        )
        item.sourceAccountID = "server-a"
        if let tmdbID { item.providerIDs["Tmdb"] = String(tmdbID) }
        return item
    }

    private func metadata(_ number: Int, date: Date? = Date(timeIntervalSince1970: 0)) -> SeasonEpisodeMetadata {
        .init(id: 1000 + number, seasonNumber: 8, episodeNumber: number, title: "Episode \(number)", airDate: date)
    }

    private func list(
        _ library: [MediaItem],
        _ episodes: [SeasonEpisodeMetadata]?,
        series suppliedSeries: MediaItem? = nil
    ) -> SeasonEpisodeList {
        SeasonEpisodeList(
            series: suppliedSeries ?? series, seasonNumber: 8, libraryEpisodes: library,
            roster: episodes.map { SeasonEpisodeRoster(seriesTMDbID: 100, seasonNumber: 8, episodes: $0) },
            now: now
        )
    }

    func testSevenOfTenIncludesTheThreeMissingEpisodesInOrder() {
        let result = list((4...10).map { owned($0) }, (1...10).map { metadata($0) })
        XCTAssertEqual(result.rows.compactMap(\.episodeNumber), Array(1...10))
        XCTAssertEqual(result.coverage?.inLibrary, 7)
        XCTAssertEqual(result.coverage?.total, 10)
        XCTAssertEqual(result.coverage?.missing, 3)
        XCTAssertTrue(result.rows.prefix(3).allSatisfy { $0.libraryEpisodes.isEmpty })
        XCTAssertEqual(result.rows[3].libraryEpisodes[0].id, "episode-4")
    }

    func testMetadataNeverProvidesADownloadableItem() {
        let result = list([], [metadata(1), metadata(2, date: now.addingTimeInterval(86400 * 3))])
        XCTAssertTrue(result.rows.allSatisfy { $0.libraryEpisodes.isEmpty })
        XCTAssertEqual(result.rows.map(\.availability), [.missing, .unaired])
        XCTAssertEqual(result.coverage?.unaired, 1)
    }

    func testCoverageIncludesEpisodesSplitAcrossLibraryVersions() {
        let firstVersion = (1...5).map { owned($0, id: "version-a-\($0)") }
        let secondVersion = (6...10).map { owned($0, id: "version-b-\($0)") }
        let result = list(firstVersion + secondVersion, (1...10).map { metadata($0) })
        XCTAssertEqual(result.coverage?.inLibrary, 10)
        XCTAssertEqual(result.coverage?.missing, 0)
        XCTAssertFalse(result.coverage?.hasUnavailableEpisodes == true)
        XCTAssertEqual(result.rows.count, 10)
        XCTAssertEqual(
            SeasonEpisodeList.downloadableEpisodes(from: firstVersion, for: series).count, 5
        )
    }

    func testLibraryPresenceWinsEvenBeforeTheScheduledAirDate() {
        let result = list([owned(1)], [metadata(1, date: now.addingTimeInterval(86400 * 3))])
        XCTAssertEqual(result.rows[0].availability, .inLibrary)
        XCTAssertFalse(result.coverage?.hasUnavailableEpisodes == true)
    }

    func testUnknownAirDateIsNotCalledMissingOrUnaired() {
        let result = list([], [metadata(1, date: nil)])
        XCTAssertEqual(result.rows[0].availability, .releaseDateUnknown)
        XCTAssertEqual(result.coverage?.missing, 0)
        XCTAssertEqual(result.coverage?.unaired, 0)
    }

    func testSparseMetadataDoesNotInventNumberingGaps() {
        let result = list([owned(1)], [metadata(1), metadata(3), metadata(9)])
        XCTAssertEqual(result.rows.compactMap(\.episodeNumber), [1, 3, 9])
        XCTAssertEqual(result.coverage?.total, 3)
    }

    func testIdentityIsStableWhenAnEpisodeArrives() {
        let before = list([], [metadata(1)])
        let after = list([owned(1)], [metadata(1)])
        XCTAssertEqual(before.rows[0].id, after.rows[0].id)
    }

    func testExplicitEpisodeIdentityDoesNotReplaceCuratedLibraryNumbering() {
        let result = list([owned(42, tmdbID: 1001)], [metadata(1)])
        XCTAssertEqual(result.rows[0].libraryEpisodes[0].episodeNumber, 42)
        XCTAssertTrue(result.hasNumberingConflict)
        XCTAssertNil(result.coverage)
    }

    func testExplicitIdentityCanFillAnAbsentEpisodeNumber() {
        var episode = owned(1, tmdbID: 1001)
        episode.episodeNumber = nil
        let result = list([episode], [metadata(1)])
        XCTAssertEqual(result.rows[0].episodeNumber, 1)
        XCTAssertEqual(result.coverage?.inLibrary, 1)
    }

    func testCombinedFileCoversOnlyTheExplicitServerEpisodeRange() {
        var combined = owned(1, id: "combined", tmdbID: 1001)
        combined.episodeNumberEnd = 2
        let result = list([combined], [metadata(1), metadata(2), metadata(3)])
        XCTAssertEqual(result.coverage?.inLibrary, 2)
        XCTAssertEqual(result.coverage?.missing, 1)
        XCTAssertEqual(result.rows[0].libraryEpisodes[0].id, "combined")
        XCTAssertEqual(result.rows[1].libraryEpisodes[0].id, "combined")
        XCTAssertEqual(
            SeasonEpisodeList.downloadableEpisodes(from: result.rows.flatMap(\.libraryEpisodes), for: series).count,
            1
        )
    }

    func testCombinedRangeCannotBeInferredFromTheFileTitle() {
        var episode = owned(1)
        episode.title = "Episodes 1 and 2"
        let result = list([episode], [metadata(1), metadata(2)])
        XCTAssertEqual(result.coverage?.inLibrary, 1)
    }

    func testInvalidOrUnmatchedCombinedRangesDoNotProduceFalseCoverage() {
        for end in [0, 10, Int.max] {
            var episode = owned(1)
            episode.episodeNumberEnd = end
            let result = list([episode], [metadata(1), metadata(2)])
            XCTAssertTrue(result.hasNumberingConflict)
            XCTAssertNil(result.coverage)
            XCTAssertEqual(result.rows.count, 1)
        }
    }

    func testCombinedEpisodeRangeSurvivesCodableRoundTrip() throws {
        var episode = owned(1)
        episode.episodeNumberEnd = 2
        let restored = try JSONDecoder().decode(MediaItem.self, from: JSONEncoder().encode(episode))
        XCTAssertEqual(restored.episodeNumberEnd, 2)
    }

    func testConflictingEpisodeIdentityDoesNotFallBackToANumberMatch() {
        let result = list([owned(1, tmdbID: 999)], [metadata(1), metadata(2)])
        XCTAssertTrue(result.hasNumberingConflict)
        XCTAssertNil(result.coverage)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].libraryEpisodes[0].id, "episode-1")
    }

    func testUnknownAndAlternateNumberingRetainLibraryWithoutFalseMissingRows() {
        var unknown = owned(1)
        unknown.episodeNumber = nil
        for episode in [unknown, owned(1087)] {
            let result = list([episode], [metadata(1), metadata(2)])
            XCTAssertTrue(result.hasNumberingConflict)
            XCTAssertNil(result.coverage)
            XCTAssertEqual(result.rows.count, 1)
            XCTAssertFalse(result.rows.contains { $0.availability == .missing })
        }
    }

    func testDuplicatesDoNotInflateCountsAndDistinctVersionsRemainDownloadable() {
        let first = owned(1, id: "version-a")
        let second = owned(1, id: "version-b")
        let result = list([first, first, second], [metadata(1), metadata(1)])
        XCTAssertEqual(result.coverage?.total, 1)
        XCTAssertEqual(result.coverage?.inLibrary, 1)
        XCTAssertEqual(result.rows[0].libraryEpisodes.map(\.id), ["version-a", "version-b"])
    }

    func testWrongSourceOrSeriesCannotSatisfyCoverage() {
        var foreignSource = owned(1)
        foreignSource.sourceAccountID = "server-b"
        var foreignSeries = owned(1)
        foreignSeries.seriesID = "other-show"
        for foreign in [foreignSource, foreignSeries] {
            let result = list([foreign], [metadata(1)])
            XCTAssertEqual(result.coverage?.inLibrary, 0)
            XCTAssertTrue(result.rows[0].libraryEpisodes.isEmpty)
        }
    }

    func testMissingMetadataKeepsLibraryWithoutInventingATotal() {
        let result = list([owned(4), owned(10)], nil)
        XCTAssertNil(result.coverage)
        XCTAssertEqual(result.rows.compactMap(\.episodeNumber), [4, 10])
    }

    func testConflictingMetadataCannotClaimACompleteRoster() {
        let duplicate = SeasonEpisodeMetadata(id: 2001, seasonNumber: 8, episodeNumber: 1)
        let result = list([owned(1)], [metadata(1), duplicate])
        XCTAssertTrue(result.hasNumberingConflict)
        XCTAssertNil(result.coverage)
    }

    func testWrongSeriesMetadataIsIgnored() {
        var different = series
        different.providerIDs["Tmdb"] = "200"
        let result = list([owned(1)], [metadata(1), metadata(2)], series: different)
        XCTAssertNil(result.coverage)
        XCTAssertEqual(result.rows.count, 1)
    }

    func testUnprovenOrSyntheticEpisodesCannotBecomeDownloads() {
        var unproven = owned(1)
        unproven.locallyValidatedPlayableSource = false
        var upcoming = owned(2)
        upcoming.scheduledAirDate = now.addingTimeInterval(86400)
        let result = list([unproven, upcoming], [metadata(1), metadata(2)])
        XCTAssertEqual(result.coverage?.inLibrary, 0)
        XCTAssertTrue(result.rows.allSatisfy { $0.libraryEpisodes.isEmpty })
    }

    func testCalendarDayReleaseUsesTheSameDayInEastAndWestTimeZones() throws {
        let date = try XCTUnwrap(MediaItem.calendarDayReleaseDate(from: "2026-09-07"))
        for offset in [-7 * 3600, 9 * 3600] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: offset))
            let localDay = date.addingTimeInterval(TimeInterval(-offset))
            XCTAssertEqual(
                SeasonEpisodeAvailability.scheduled(airDate: date, now: localDay.addingTimeInterval(-1), calendar: calendar),
                .unaired
            )
            XCTAssertEqual(
                SeasonEpisodeAvailability.scheduled(airDate: date, now: localDay.addingTimeInterval(43200), calendar: calendar),
                .airingToday
            )
            XCTAssertEqual(
                SeasonEpisodeAvailability.scheduled(airDate: date, now: localDay.addingTimeInterval(86400), calendar: calendar),
                .missing
            )
        }
    }

    func testExactAirTimesKeepTheExistingGracePeriod() {
        XCTAssertEqual(
            SeasonEpisodeAvailability.scheduled(airDate: now, hasTime: true, now: now.addingTimeInterval(3600)),
            .recentlyReleased
        )
        XCTAssertEqual(
            SeasonEpisodeAvailability.scheduled(airDate: now, hasTime: true, now: now.addingTimeInterval(21600)),
            .missing
        )
    }
}
