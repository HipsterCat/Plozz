import XCTest
@testable import CoreModels

final class SeriesDownloadSeasonsTests: XCTestCase {
    private func librarySeason(_ number: Int?, id: String? = nil) -> MediaItem {
        var item = MediaItem(id: id ?? "library-\(number ?? -1)", title: "Library Season", kind: .season)
        item.seasonNumber = number
        return item
    }

    private func episode(_ id: String, season: Int?) -> MediaItem {
        var item = MediaItem(id: id, title: "Episode", kind: .episode)
        item.seasonNumber = season
        return item
    }

    private func state(_ number: Int, _ status: MediaAvailabilityStatus) -> MediaSeasonRequestState {
        .init(number: number, title: "Season \(number)", status: status)
    }

    private func english(_ resource: LocalizedStringResource) -> String {
        var copy = resource
        copy.locale = Locale(identifier: "en")
        return String(localized: copy)
    }

    private func english(_ title: SeriesDownloadSeasonTitle) -> String {
        switch title {
        case .content(let value): value
        case .localized(let resource): english(resource)
        }
    }

    func testProviderSeasonNamesRemainContentEvenWhenTheyMatchAppCopy() {
        var season = librarySeason(1, id: "season")
        season.title = "Specials"
        let list = SeriesDownloadSeasons(
            librarySeasons: [season], looseEpisodes: [], requestAvailability: nil
        )
        XCTAssertEqual(list.rows.first?.title, .content("Specials"))
    }

    func testTwentySeasonsAppearOnceAcrossLibraryAndRequests() {
        let availability = MediaRequestAvailability(
            status: .partiallyAvailable,
            seasons: (1...20).map { state($0, $0 <= 3 ? .available : .unknown) }
        )
        let list = SeriesDownloadSeasons(
            librarySeasons: [librarySeason(1), librarySeason(2), librarySeason(3)],
            looseEpisodes: [],
            requestAvailability: availability
        )
        XCTAssertEqual(list.rows.count, 20)
        XCTAssertEqual(Set(list.rows.map(\.id)).count, 20)
        XCTAssertEqual(list.rows.compactMap(\.number), Array(1...20))
        XCTAssertEqual(list.rows.filter(\.hasLibraryContent).count, 3)
        XCTAssertEqual(list.requestableSeasonNumbers, Array(4...20))
    }

    func testOneThreeAndAllTwentyRequestsStayOnTheirOwnRows() {
        for requested in [[7], [2, 7, 14], Array(1...20)] {
            let availability = MediaRequestAvailability(
                status: .pending,
                seasons: (1...20).map { state($0, requested.contains($0) ? .pending : .unknown) }
            )
            let list = SeriesDownloadSeasons(
                librarySeasons: [], looseEpisodes: [], requestAvailability: availability
            )
            XCTAssertEqual(list.rows.count, 20)
            XCTAssertEqual(list.rows.filter { $0.requestState?.isInFlight == true }.count, requested.count)
            XCTAssertEqual(list.requestableSeasonNumbers.count, 20 - requested.count)
        }
    }

    func testRequestRowIdentitySurvivesArrivalInTheLibrary() {
        let availability = MediaRequestAvailability(status: .pending, seasons: [state(7, .pending)])
        let before = SeriesDownloadSeasons(
            librarySeasons: [], looseEpisodes: [], requestAvailability: availability
        )
        let after = SeriesDownloadSeasons(
            librarySeasons: [librarySeason(7)], looseEpisodes: [], requestAvailability: availability
        )
        XCTAssertEqual(before.rows.map(\.id), after.rows.map(\.id))
        XCTAssertEqual(after.rows.count, 1)
        XCTAssertTrue(after.rows[0].hasLibraryContent)
        XCTAssertFalse(after.rows[0].canRequest)
        XCTAssertEqual(english(after.rows[0].statusTitle), "Partially in Library · Requested")
    }

    func testLocalContentNeedsEpisodeCoverageBeforeOfferingMissingRequests() {
        let list = SeriesDownloadSeasons(
            librarySeasons: [librarySeason(1)],
            looseEpisodes: [episode("episode-2", season: 2)],
            requestAvailability: .init(status: .unknown, seasons: [state(1, .unknown), state(2, .deleted)])
        )
        XCTAssertEqual(list.rows.map { $0.requestState?.coverageStatus }, [.partiallyAvailable, .partiallyAvailable])
        XCTAssertEqual(list.rows.map { $0.requestState?.status }, [.unknown, .deleted])
        XCTAssertTrue(list.requestableSeasonNumbers.isEmpty)
        XCTAssertTrue(list.requestAvailability?.requestableMissingSeasonNumbers.isEmpty == true)
        XCTAssertEqual(list.requestAvailability?.requestableSeasonNumbers, [1, 2])
    }

    func testPartialProcessingAndFailuresKeepTheirWorkflow() {
        let failed = MediaSeasonRequestState(
            number: 2, title: "Season 2", status: .unknown, requestStatus: .failed
        )
        let list = SeriesDownloadSeasons(
            librarySeasons: [librarySeason(1), librarySeason(2)], looseEpisodes: [],
            requestAvailability: .init(status: .processing, seasons: [state(1, .processing), failed])
        )
        XCTAssertEqual(english(list.rows[0].statusTitle), "Partially in Library · Processing")
        XCTAssertEqual(english(list.rows[1].statusTitle), "Partially in Library · Request Failed")
        XCTAssertTrue(list.rows[0].requestState?.isInFlight == true)
        XCTAssertFalse(list.rows[1].canRequest)
    }

    func testSpecialsAndUnnumberedLibraryEntriesAreNotDiscardedOrGuessed() {
        let list = SeriesDownloadSeasons(
            librarySeasons: [librarySeason(0), librarySeason(nil, id: "unknown-a"), librarySeason(nil, id: "unknown-b")],
            looseEpisodes: [],
            requestAvailability: .init(status: .unknown, seasons: [state(0, .unknown), state(1, .unknown)])
        )
        XCTAssertEqual(list.rows.count, 4)
        XCTAssertEqual(list.rows.filter { $0.number == nil }.count, 2)
        XCTAssertEqual(list.rows.first { $0.number == 0 }?.canRequest, false)
        XCTAssertEqual(list.requestableSeasonNumbers, [1])
    }

    func testDuplicateMetadataMergesWithoutLosingDistinctLibraryEntries() {
        let first = librarySeason(1, id: "season-version-a")
        let second = librarySeason(1, id: "season-version-b")
        let list = SeriesDownloadSeasons(
            librarySeasons: [first, first, second],
            looseEpisodes: [],
            requestAvailability: .init(status: .pending, seasons: [state(1, .unknown), state(1, .pending)])
        )
        XCTAssertEqual(list.rows.count, 1)
        XCTAssertEqual(list.rows[0].librarySeasons.map(\.id), [first.id, second.id])
        XCTAssertTrue(list.rows[0].requestState?.isInFlight == true)
    }

    func testLooseEpisodesJoinTheirSeasonAndUnnumberedEpisodesRemainAccessible() {
        let known = episode("known", season: 1)
        let unknown = episode("unknown", season: nil)
        let list = SeriesDownloadSeasons(
            librarySeasons: [librarySeason(1)],
            looseEpisodes: [known, known, unknown, episode("special", season: 0)],
            requestAvailability: .init(status: .available, seasons: [state(1, .available)])
        )
        XCTAssertEqual(list.rows.count, 2)
        XCTAssertEqual(list.rows.first { $0.number == 1 }?.looseEpisodes.map(\.id), ["known"])
        XCTAssertEqual(list.unassignedEpisodes.map(\.id), ["unknown"])
        XCTAssertEqual(english(list.rows[0].title), "Specials")
    }

    func testProviderLocalIDsDoNotDiscardDifferentLibrarySources() {
        var first = librarySeason(1, id: "same-provider-id")
        first.sourceAccountID = "server-a"
        var second = first
        second.sourceAccountID = "server-b"
        let list = SeriesDownloadSeasons(
            librarySeasons: [first, second], looseEpisodes: [], requestAvailability: nil
        )
        XCTAssertEqual(list.rows.count, 1)
        XCTAssertEqual(list.rows[0].librarySeasons.count, 2)
        XCTAssertEqual(Set(list.rows[0].librarySeasons.map(\.stablePresentationID)).count, 2)
    }

    func testSeerrAvailabilityAloneDoesNotCreateLocalDownloads() {
        let list = SeriesDownloadSeasons(
            librarySeasons: [], looseEpisodes: [],
            requestAvailability: .init(status: .available, seasons: [state(1, .available)])
        )
        XCTAssertEqual(list.rows.count, 1)
        XCTAssertFalse(list.rows[0].hasLibraryContent)
        XCTAssertFalse(list.rows[0].canRequest)
        XCTAssertEqual(english(list.rows[0].statusTitle), "Available on Server")
    }

    func testLibraryAvailabilityDoesNotImplyAnOfflineDownload() {
        let list = SeriesDownloadSeasons(
            librarySeasons: [librarySeason(1)], looseEpisodes: [],
            requestAvailability: .init(status: .available, seasons: [state(1, .available)])
        )
        XCTAssertEqual(english(list.rows[0].statusTitle), "In Library")
        XCTAssertFalse(list.rows[0].canRequest)
    }

    func testPartialLibraryAndServerCoveragePreserveEveryRequestStatus() {
        let cases: [(MediaSeasonRequestStatus?, String, String)] = [
            (nil, "Partially in Library", "Partially Available on Server"),
            (.pending, "Partially in Library · Requested", "Partially Available on Server · Requested"),
            (.processing, "Partially in Library · Processing", "Partially Available on Server · Processing"),
            (.failed, "Partially in Library · Request Failed", "Partially Available on Server · Request Failed"),
            (.declined, "Partially in Library · Request Declined", "Partially Available on Server · Request Declined"),
            (.completed, "Partially in Library", "Partially Available on Server")
        ]
        for (requestStatus, libraryTitle, serverTitle) in cases {
            let availability = MediaRequestAvailability(
                status: .partiallyAvailable,
                seasons: [.init(
                    number: 1, title: "Season 1",
                    status: .partiallyAvailable, requestStatus: requestStatus
                )]
            )
            for hasLibraryContent in [false, true] {
                let list = SeriesDownloadSeasons(
                    librarySeasons: hasLibraryContent ? [librarySeason(1)] : [],
                    looseEpisodes: [], requestAvailability: availability
                )
                XCTAssertEqual(
                    english(list.rows[0].statusTitle),
                    hasLibraryContent ? libraryTitle : serverTitle
                )
                XCTAssertFalse(list.rows[0].canRequest)
                XCTAssertEqual(list.rows[0].requestState?.requestStatus, requestStatus)
            }
        }
    }

    func testMissingPendingAndFailedRowsKeepTheirStatusAndEligibility() {
        let list = SeriesDownloadSeasons(
            librarySeasons: [], looseEpisodes: [],
            requestAvailability: .init(status: .pending, seasons: [
                state(1, .unknown), state(2, .pending), state(3, .processing),
                .init(number: 4, title: "Season 4", status: .unknown, requestFailed: true),
                .init(number: 5, title: "Season 5", status: .unknown, requestStatus: .declined)
            ])
        )
        XCTAssertEqual(list.rows.map { english($0.statusTitle) }, [
            "Missing", "Requested", "Processing", "Request Failed", "Request Declined"
        ])
        XCTAssertEqual(list.requestableSeasonNumbers, [1])
        XCTAssertEqual(list.rows[1].statusSystemImage, "clock")
    }

    func testLoadingAndDisconnectedStatesKeepLibraryRows() {
        let list = SeriesDownloadSeasons(
            librarySeasons: [librarySeason(7)], looseEpisodes: [], requestAvailability: nil
        )
        XCTAssertEqual(list.rows.count, 1)
        XCTAssertNil(list.requestAvailability)
        XCTAssertTrue(list.requestableSeasonNumbers.isEmpty)
        XCTAssertEqual(english(list.rows[0].statusTitle), "In Library")
    }

    func testLibraryOnlySeasonsAndStableOrderingSurviveRefresh() {
        let library = [librarySeason(22), librarySeason(2)]
        let availability = MediaRequestAvailability(
            status: .unknown, seasons: [state(7, .unknown), state(1, .pending)]
        )
        let first = SeriesDownloadSeasons(librarySeasons: library, looseEpisodes: [], requestAvailability: availability)
        var reordered = availability
        reordered.seasons.reverse()
        let second = SeriesDownloadSeasons(
            librarySeasons: Array(library.reversed()), looseEpisodes: [], requestAvailability: reordered
        )
        XCTAssertEqual(first.rows.map(\.id), second.rows.map(\.id))
        XCTAssertEqual(first.rows.compactMap(\.number), [1, 2, 7, 22])
    }
}
