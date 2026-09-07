import XCTest
@testable import CoreModels

final class SeasonRequestStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func twentySeasons() -> MediaRequestAvailability {
        MediaRequestAvailability(status: .unknown, seasons: (1...20).map {
            MediaSeasonRequestState(number: $0, title: "Season \($0)", status: .unknown)
        })
    }

    func testAcceptedSelectionsOnlyAffectTheirSeasons() {
        for selected in [[7], [2, 7, 14], Array(1...20)] {
            var state = SeasonRequestState(availability: twentySeasons())
            state.accept(selected, now: now)
            XCTAssertEqual(
                Set(state.availability?.seasons.filter(\.isInFlight).map(\.number) ?? []),
                Set(selected)
            )
            XCTAssertEqual(state.availability?.requestableSeasonNumbers.count, 20 - selected.count)
        }
    }

    func testSeparateSubmissionsAccumulateWithoutDoubleCounting() {
        var state = SeasonRequestState(availability: twentySeasons())
        state.accept([2, 2, 0, -1], now: now)
        state.accept([7, 14], now: now.addingTimeInterval(1))
        XCTAssertEqual(state.availability?.seasons.filter(\.isInFlight).map(\.number), [2, 7, 14])
        XCTAssertEqual(state.availability?.seasons.count, 20)
    }

    func testLaggingReadCannotEraseAcceptedSelection() {
        var state = SeasonRequestState(availability: twentySeasons())
        state.accept([7], now: now)
        state.apply(twentySeasons(), now: now.addingTimeInterval(10))
        XCTAssertEqual(state.availability?.seasons.first { $0.number == 7 }?.status, .pending)
        XCTAssertEqual(state.availability?.requestableSeasonNumbers.count, 19)
    }

    func testOmittedSeasonSurvivesWithinBoundedGrace() {
        var state = SeasonRequestState(availability: twentySeasons())
        state.accept([7], now: now)
        var fetched = twentySeasons()
        fetched.seasons.removeAll { $0.number == 7 }
        state.apply(fetched, now: now.addingTimeInterval(10))
        XCTAssertEqual(state.availability?.seasons.first { $0.number == 7 }?.status, .pending)
        state.apply(fetched, now: now.addingTimeInterval(61))
        XCTAssertFalse(state.availability?.seasons.contains { $0.number == 7 } ?? true)
    }

    func testAuthoritativeCompletionWinsAndUnselectedSeasonsStayMissing() {
        var state = SeasonRequestState(availability: twentySeasons())
        state.accept([2, 7, 14], now: now)
        var fetched = twentySeasons()
        fetched.seasons[1].status = .available
        fetched.seasons[6].status = .processing
        fetched.seasons[13].requestFailed = true
        state.apply(fetched, now: now.addingTimeInterval(1))
        XCTAssertEqual(state.availability?.seasons[1].status, .available)
        XCTAssertEqual(state.availability?.seasons[6].status, .processing)
        XCTAssertEqual(state.availability?.seasons[13].requestFailed, true)
        XCTAssertEqual(state.availability?.requestableSeasonNumbers.count, 17)
    }

    func testConfirmedRequestCanSubsequentlyBeRemoved() {
        var state = SeasonRequestState(availability: twentySeasons())
        state.accept([7], now: now)
        let confirmed = twentySeasons().markingRequested([7])
        state.apply(confirmed, now: now.addingTimeInterval(1))
        state.apply(twentySeasons(), now: now.addingTimeInterval(2))
        XCTAssertEqual(state.availability?.seasons[6].status, .unknown)
    }

    func testResetDropsTitleAndConnectionScopedState() {
        var state = SeasonRequestState(availability: twentySeasons())
        state.accept([7], now: now)
        state.reset()
        XCTAssertNil(state.availability)
        state.apply(twentySeasons(), now: now.addingTimeInterval(1))
        XCTAssertEqual(state.availability?.requestableSeasonNumbers.count, 20)
    }

    func testLibraryPresenceDoesNotEraseUnconfirmedRequest() {
        var state = SeasonRequestState(availability: twentySeasons())
        state.accept([7], now: now)
        state.apply(twentySeasons(), now: now.addingTimeInterval(1), presentInLibrary: [7])
        XCTAssertEqual(state.availability?.seasons[6].isInFlight, true)
        XCTAssertNotEqual(state.availability?.seasons[6].status, .available)
    }

    func testLocallyPartialUntrackedSeasonCanBeAcceptedAndReconciled() {
        var state = SeasonRequestState()
        state.apply(twentySeasons(), now: now, presentInLibrary: [7])
        XCTAssertTrue(state.availability?.seasons[6].isRequestable == true)
        XCTAssertFalse(state.availability?.requestableMissingSeasonNumbers.contains(7) == true)

        state.accept([7], now: now)
        state.apply(twentySeasons(), now: now.addingTimeInterval(10), presentInLibrary: [7])

        XCTAssertEqual(state.availability?.seasons[6].requestStatus, .pending)
        XCTAssertEqual(state.availability?.seasons[6].coverageStatus, .partiallyAvailable)
        XCTAssertFalse(state.availability?.seasons[6].isRequestable == true)
        XCTAssertTrue(state.availability?.seasons[6].isInFlight == true)
    }

    func testSeerrManagedPartialSeasonCannotBeAcceptedAsANewRequest() {
        var fetched = twentySeasons()
        fetched.seasons[6].status = .partiallyAvailable
        var state = SeasonRequestState()
        state.apply(fetched, now: now, presentInLibrary: [7])
        state.accept([7], now: now)

        XCTAssertEqual(state.availability?.seasons[6].status, .partiallyAvailable)
        XCTAssertNil(state.availability?.seasons[6].requestStatus)
        XCTAssertFalse(state.availability?.seasons[6].isInFlight == true)
    }

    func testLookupKeysSeparateServersAndChangedMetadataIdentity() {
        var first = MediaItem(id: "123", title: "First", kind: .series)
        first.sourceAccountID = "server-a"
        first.providerIDs = ["Tmdb": "100"]
        var second = first
        second.sourceAccountID = "server-b"
        XCTAssertNotEqual(SeasonRequestState.itemKey(for: first), SeasonRequestState.itemKey(for: second))
        second = first
        second.providerIDs = ["Tmdb": "200"]
        XCTAssertNotEqual(SeasonRequestState.itemKey(for: first), SeasonRequestState.itemKey(for: second))
    }

    func testAvailableCoverageCannotStayCountedAsActiveOrFailed() {
        for workflow in [MediaSeasonRequestStatus.pending, .processing, .failed] {
            let season = MediaSeasonRequestState(
                number: 7,
                title: "Season 7",
                status: .available,
                requestStatus: workflow
            )
            let presentation = SeasonRequestPresentation(
                availability: MediaRequestAvailability(status: .available, seasons: [season])
            )
            XCTAssertFalse(presentation.hasActiveRequests)
            XCTAssertFalse(presentation.hasFailures)
            XCTAssertFalse(season.isInFlight)
        }
    }

    func testExplicitWorkflowProvidesStatusWithoutCoverageScannerData() {
        let season = MediaSeasonRequestState(
            number: 7, title: "Season 7", status: .unknown, requestStatus: .processing
        )
        XCTAssertEqual(season.statusTitle, "Processing")
        XCTAssertTrue(season.isInFlight)
        XCTAssertFalse(season.isRequestable)
    }

    func testUnavailableAndPartialSeasonListsDoNotImplyCompletion() {
        let empty = SeasonRequestPresentation(
            availability: MediaRequestAvailability(status: .unknown)
        )
        XCTAssertEqual(empty.title, "Seasons Unavailable")
        XCTAssertNotEqual(empty.systemImage, "checkmark.circle")
        let partial = SeasonRequestPresentation(
            availability: MediaRequestAvailability(status: .partiallyAvailable, seasons: [
                MediaSeasonRequestState(number: 7, title: "Season 7", status: .partiallyAvailable)
            ])
        )
        XCTAssertFalse(partial.hasActiveRequests)
        XCTAssertNotEqual(partial.systemImage, "checkmark.circle")
    }
}
