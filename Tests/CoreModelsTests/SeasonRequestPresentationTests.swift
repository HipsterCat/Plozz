import XCTest
@testable import CoreModels

final class SeasonRequestPresentationTests: XCTestCase {
    func testPendingLabelsCoverOneArbitraryAndAllSeasons() {
        XCTAssertEqual(
            english(presentation(pending: [1], total: 20).title),
            "S1 Requested"
        )
        XCTAssertEqual(
            english(presentation(pending: [2, 7, 14], total: 20).title),
            "3 Seasons Requested"
        )
        XCTAssertEqual(
            english(presentation(pending: Array(1...20), total: 20).title),
            "20 Seasons Requested"
        )
    }

    func testCountsIgnoreSpecialsInvalidAndDuplicateSeasonIDs() {
        let availability = MediaRequestAvailability(
            status: .unknown,
            seasons: [
                season(0, .pending),
                season(-1, .pending),
                season(7, .pending),
                season(7, .pending),
                season(2, .unknown),
                season(2, .unknown),
                season(3, .available)
            ]
        )
        let presentation = SeasonRequestPresentation(availability: availability)

        XCTAssertEqual(english(presentation.title), "S7 Requested")
        XCTAssertEqual(english(presentation.requestAllTitle), "Request All Missing (1)")
        XCTAssertEqual(availability.requestableSeasonNumbers, [2])
    }

    func testProcessingIsTruthfulWithoutDownloadLanguage() {
        let one = SeasonRequestPresentation(
            availability: availability([season(7, .processing)])
        )
        let many = SeasonRequestPresentation(
            availability: availability([season(2, .processing), season(14, .processing)])
        )

        XCTAssertEqual(english(one.title), "S7 Processing")
        XCTAssertEqual(english(many.title), "2 Seasons Processing")
        XCTAssertEqual(one.systemImage, "arrow.triangle.2.circlepath")
        XCTAssertFalse(english(one.title).localizedCaseInsensitiveContains("download"))
    }

    func testPartialAvailabilityCanRetainActiveRequestWorkflow() {
        let partial = MediaSeasonRequestState(
            number: 7,
            title: "Season 7",
            status: .partiallyAvailable,
            requestStatus: .processing
        )
        let presentation = SeasonRequestPresentation(
            availability: availability([partial])
        )

        XCTAssertTrue(partial.isInFlight)
        XCTAssertFalse(partial.isRequestable)
        XCTAssertEqual(english(partial.statusTitle), "Partially Available · Processing")
        XCTAssertEqual(english(presentation.title), "S7 Processing")
        XCTAssertTrue(presentation.hasActiveRequests)
    }

    func testMixedActiveStatesAndFailuresExposeCounts() {
        let mixed = SeasonRequestPresentation(
            availability: availability([
                season(2, .pending),
                season(7, .processing),
                season(14, .pending, failed: true)
            ])
        )

        XCTAssertTrue(mixed.hasActiveRequests)
        XCTAssertTrue(mixed.hasFailures)
        XCTAssertEqual(english(mixed.title), "S14 Request Failed")
        XCTAssertEqual(mixed.systemImage, "exclamationmark.triangle.fill")
        XCTAssertEqual(
            mixed.detail.map { english($0) },
            "1 Requested, 1 Processing, 1 Failed"
        )
    }

    func testNormalSubmittingAndNoMissingPresentation() {
        let missing = SeasonRequestPresentation(
            availability: availability([season(1, .unknown)])
        )
        let submitting = SeasonRequestPresentation(
            availability: availability([season(1, .unknown)]),
            isSubmitting: true
        )
        let complete = SeasonRequestPresentation(
            availability: availability([season(1, .available)])
        )

        XCTAssertEqual(english(missing.title), "Request Seasons")
        XCTAssertEqual(missing.systemImage, "plus.circle")
        XCTAssertEqual(english(submitting.title), "Requesting…")
        XCTAssertEqual(english(complete.title), "Season Requests")
    }

    func testRequestAllExcludesAvailableActivePartialAndFailed() {
        let presentation = SeasonRequestPresentation(
            availability: availability([
                season(1, .unknown),
                season(2, .deleted),
                season(3, .available),
                season(4, .pending),
                season(5, .processing),
                season(6, .partiallyAvailable),
                season(7, .unknown, failed: true),
                MediaSeasonRequestState(
                    number: 8,
                    title: "Season 8",
                    status: .unknown,
                    requestStatus: .declined
                ),
                MediaSeasonRequestState(
                    number: 9,
                    title: "Season 9",
                    status: .unknown,
                    requestStatus: .completed
                )
            ])
        )

        XCTAssertEqual(english(presentation.requestAllTitle), "Request All Missing (2)")
    }

    func testDeclinedWorkflowIsDistinctAndBlocked() {
        let declined = MediaSeasonRequestState(
            number: 7,
            title: "Season 7",
            status: .partiallyAvailable,
            requestStatus: .declined
        )
        let presentation = SeasonRequestPresentation(
            availability: availability([declined])
        )

        XCTAssertFalse(declined.isInFlight)
        XCTAssertFalse(declined.isRequestable)
        XCTAssertEqual(english(declined.statusTitle), "Partially Available · Request Declined")
        XCTAssertEqual(english(presentation.title), "S7 Request Declined")
        XCTAssertTrue(presentation.hasFailures)
    }

    func testPerSeasonStatusPresentation() {
        let cases: [(MediaSeasonRequestState, String, String)] = [
            (season(1, .pending), "Requested", "clock"),
            (season(2, .processing), "Processing", "arrow.triangle.2.circlepath"),
            (season(3, .available), "Available", "checkmark.circle.fill"),
            (season(4, .partiallyAvailable), "Partially Available", "circle.lefthalf.filled"),
            (season(5, .processing, failed: true), "Request Failed", "exclamationmark.triangle.fill"),
            (
                MediaSeasonRequestState(
                    number: 6,
                    title: "Season 6",
                    status: .unknown,
                    requestStatus: .declined
                ),
                "Request Declined",
                "exclamationmark.triangle.fill"
            ),
            (
                MediaSeasonRequestState(
                    number: 7,
                    title: "Season 7",
                    status: .unknown,
                    requestStatus: .completed
                ),
                "Request Completed",
                "checkmark.circle"
            )
        ]

        for (season, title, image) in cases {
            XCTAssertEqual(english(season.statusTitle), title)
            XCTAssertEqual(season.statusSystemImage, image)
        }
    }

    func testRepeatedMarkingRequestedPreservesEarlierRequestsAndSiblings() {
        let initial = availability((1...20).map { season($0, .unknown) })
        let first = initial.markingRequested([2, 2, 0, -1])
        let second = first.markingRequested([7, 14, 14])

        XCTAssertEqual(
            second.seasons.filter(\.isInFlight).map(\.number),
            [2, 7, 14]
        )
        XCTAssertEqual(second.requestableSeasonNumbers.count, 17)
        XCTAssertEqual(second.seasons.count, 20)
    }

    func testLibraryPresenceDoesNotOverwriteRequestServiceEligibility() {
        let initial = availability([
            season(1, .unknown),
            season(2, .deleted),
            season(3, .pending),
            season(4, .processing),
            season(5, .available),
            season(6, .partiallyAvailable),
            season(7, .unknown, failed: true)
        ])

        let updated = initial.markingPresentInLibrary([1, 2, 3, 4, 5, 6, 7, 0, -1])

        XCTAssertEqual(updated.seasons.map(\.status), initial.seasons.map(\.status))
        XCTAssertEqual(updated.seasons.map(\.coverageStatus), [
            .partiallyAvailable,
            .partiallyAvailable,
            .partiallyAvailable,
            .partiallyAvailable,
            .available,
            .partiallyAvailable,
            .partiallyAvailable
        ])
        XCTAssertEqual(updated.seasons.map(\.requestFailed), [
            false, false, false, false, false, false, true
        ])
        XCTAssertEqual(
            english(updated.seasons[6].statusTitle),
            "Partially Available · Request Failed"
        )
        XCTAssertEqual(updated.requestableSeasonNumbers, [1, 2])
        XCTAssertEqual(updated.requestableMissingSeasonNumbers, [])
        XCTAssertFalse(updated.seasons[5].isRequestable)
    }

    func testLibraryPresenceCanBeRemovedWithoutChangingServerState() {
        let initial = availability([season(1, .unknown), season(2, .partiallyAvailable)])
        let updated = initial.markingPresentInLibrary([1, 2]).markingPresentInLibrary([])

        XCTAssertEqual(updated.seasons.map(\.coverageStatus), [.unknown, .partiallyAvailable])
        XCTAssertEqual(updated.requestableMissingSeasonNumbers, [1])
    }

    func testCanonicalizationPreservesLocalEvidenceAndAuthoritativeBlocking() {
        let local = season(1, .unknown)
        let present = availability([local]).markingPresentInLibrary([1]).seasons[0]
        let merged = availability([present, season(1, .partiallyAvailable)])

        XCTAssertTrue(merged.canonicalNumberedSeasons[0].isPresentInLibrary)
        XCTAssertFalse(merged.canonicalNumberedSeasons[0].isRequestable)
        XCTAssertTrue(availability([present, local]).canonicalNumberedSeasons[0].isRequestable)
    }

    func testLibraryPresenceDoesNotEraseOptimisticAcceptedRequest() {
        let accepted = availability([season(7, .unknown)])
            .markingRequested([7])

        let overlaid = accepted.markingPresentInLibrary([7])

        XCTAssertEqual(overlaid.seasons.first?.status, .pending)
        XCTAssertTrue(overlaid.seasons.first?.isInFlight == true)
    }

    func testReconciliationPreservesOnlyAcceptedStaleOrOmittedSeasons() {
        let previous = availability([
            season(2, .pending),
            season(7, .pending),
            season(9, .processing)
        ])
        let fetched = availability([
            season(2, .unknown),
            season(9, .unknown),
            season(14, .unknown),
            season(14, .unknown)
        ])

        let reconciled = fetched.reconcilingAccepted([2, 7], previous: previous)

        XCTAssertEqual(reconciled.seasons.map(\.number), [2, 7, 9, 14])
        XCTAssertEqual(reconciled.seasons.map(\.status), [.pending, .pending, .unknown, .unknown])
        XCTAssertEqual(reconciled.seasons[1].title, "Season 7")
    }

    func testReconciliationLetsAuthoritativeFailedAvailableAndDeletedWin() {
        let previous = availability((1...6).map { season($0, .pending) })
        let fetched = availability([
            season(1, .available),
            season(2, .processing),
            season(3, .pending, failed: true),
            season(4, .deleted),
            MediaSeasonRequestState(
                number: 5,
                title: "Season 5",
                status: .unknown,
                requestStatus: .declined
            ),
            MediaSeasonRequestState(
                number: 6,
                title: "Season 6",
                status: .unknown,
                requestStatus: .completed
            )
        ])

        let reconciled = fetched.reconcilingAccepted(
            [1, 2, 3, 4, 5, 6],
            previous: previous
        )

        XCTAssertEqual(reconciled.seasons.map(\.status), [
            .available, .processing, .pending, .deleted, .unknown, .unknown
        ])
        XCTAssertEqual(reconciled.seasons.map(\.requestFailed), [
            false, false, true, false, false, false
        ])
        XCTAssertEqual(reconciled.seasons.map(\.requestStatus), [
            nil, nil, nil, nil, .declined, .completed
        ])
    }

    func testReconciliationCreatesMinimalAcceptedSeasonWithoutPreviousState() {
        let reconciled = availability([])
            .reconcilingAccepted([7, 0, -1], previous: nil)

        XCTAssertEqual(
            reconciled.seasons,
            [
                MediaSeasonRequestState(
                    number: 7,
                    title: "Season 7",
                    status: .pending,
                    requestStatus: .pending
                )
            ]
        )
    }

    private func presentation(pending: [Int], total: Int) -> SeasonRequestPresentation {
        let selected = Set(pending)
        return SeasonRequestPresentation(
            availability: availability((1...total).map {
                season($0, selected.contains($0) ? .pending : .unknown)
            })
        )
    }

    private func availability(
        _ seasons: [MediaSeasonRequestState]
    ) -> MediaRequestAvailability {
        MediaRequestAvailability(status: .partiallyAvailable, seasons: seasons)
    }

    private func season(
        _ number: Int,
        _ status: MediaAvailabilityStatus,
        failed: Bool = false
    ) -> MediaSeasonRequestState {
        MediaSeasonRequestState(
            number: number,
            title: "Season \(number)",
            status: status,
            requestFailed: failed
        )
    }

    private func english(_ resource: LocalizedStringResource) -> String {
        var localized = resource
        localized.locale = Locale(identifier: "en")
        return String(localized: localized)
    }
}
