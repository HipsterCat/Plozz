import XCTest
@testable import FeatureLiveTVCore

@MainActor
final class LiveTVPreviewControllerTests: XCTestCase {
    func testSearchSuppressesNavigationUntilTheReturningGuideOwnsFocus() {
        let preview = LiveTVPreviewController(model: LiveTVPrototypeModel())
        XCTAssertFalse(preview.suppressesNavigation(isActive: true))
        XCTAssertTrue(preview.suppressesNavigation(isActive: true, isSearching: true))

        preview.requestBrowsingFocus()
        XCTAssertTrue(preview.suppressesNavigation(isActive: true, isSearching: true))
        XCTAssertTrue(preview.suppressesNavigation(isActive: true, isSearching: false))
        let oldRequest = preview.focusRestoreRequest
        preview.requestBrowsingFocus()
        preview.completeGuideFocusRestore(oldRequest)
        XCTAssertTrue(preview.suppressesNavigation(isActive: true))
        preview.completeGuideFocusRestore(preview.focusRestoreRequest)
        XCTAssertFalse(preview.suppressesNavigation(isActive: true))
    }

    func testSearchKeepsNavigationSuppressedAfterAnInSearchFocusHandoff() {
        let preview = LiveTVPreviewController(model: LiveTVPrototypeModel())
        preview.requestBrowsingFocus()
        preview.completeGuideFocusRestore(preview.focusRestoreRequest)
        XCTAssertTrue(preview.suppressesNavigation(isActive: true, isSearching: true))
        XCTAssertFalse(preview.suppressesNavigation(isActive: true, isSearching: false))
    }

    func testInactiveLiveTVCannotSuppressAnotherDestinationsNavigation() {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        preview.watch(model.channels[0].id)
        XCTAssertTrue(preview.suppressesNavigation(isActive: true))
        XCTAssertFalse(preview.suppressesNavigation(isActive: false, isSearching: true))
        preview.returnToGuide()
        XCTAssertFalse(preview.suppressesNavigation(isActive: false, isSearching: true))
        preview.stop()
        XCTAssertFalse(preview.suppressesNavigation(isActive: false, isSearching: true))
    }

    func testPreviewWaitsForCommitAndOnlyLatestChannelWins() throws {
        let model = LiveTVPrototypeModel(scenario: .noGuide)
        let preview = LiveTVPreviewController(model: model)
        let first = model.channels[0].id
        let second = model.channels[1].id

        preview.focus(first)
        let stale = try XCTUnwrap(preview.pendingRequest)
        XCTAssertNil(model.playingChannelID)
        XCTAssertEqual(LiveTVPreviewController.settlingDelay, .milliseconds(600))
        preview.focus(second)
        XCTAssertFalse(preview.commitPreview(stale))
        XCTAssertNil(model.playingChannelID)
        XCTAssertTrue(preview.commitPreview(try XCTUnwrap(preview.pendingRequest)))
        XCTAssertEqual(model.playingChannelID, second)
        XCTAssertFalse(preview.isExpanded)
    }

    func testReturningToSameChannelDoesNotAcceptItsOldRequest() throws {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        preview.focus(model.channels[0].id)
        let stale = try XCTUnwrap(preview.pendingRequest)
        preview.focus(model.channels[1].id)
        preview.focus(model.channels[0].id)
        XCTAssertNotEqual(stale, preview.pendingRequest)
        preview.commitPreview(stale)
        XCTAssertNil(model.playingChannelID)
    }

    func testHorizontalProgramFocusDoesNotRestartDebounceOrTune() throws {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        let id = model.channels[0].id
        preview.focus(id)
        let request = try XCTUnwrap(preview.pendingRequest)
        preview.focus(id)
        XCTAssertEqual(preview.pendingRequest, request)
        preview.commitPreview(request)
        preview.focus(id)
        XCTAssertNil(preview.pendingRequest)
        XCTAssertNil(model.previousChannelID)
    }

    func testWatchAndReturnKeepChannelAndIgnoreBrowsingFocus() throws {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        let id = model.channels[0].id
        preview.focus(id)
        preview.commitPreview(try XCTUnwrap(preview.pendingRequest))
        preview.watch(id)
        XCTAssertTrue(preview.isExpanded)
        XCTAssertNil(model.previousChannelID)
        preview.focus(model.channels[1].id)
        XCTAssertNil(preview.pendingRequest)
        preview.returnToGuide()
        XCTAssertFalse(preview.isExpanded)
        XCTAssertEqual(model.playingChannelID, id)
        XCTAssertEqual(preview.focusRestoreRequest, 1)
        XCTAssertFalse(preview.followsFocus)
        preview.setFollowsFocus(true)
        preview.commitPreview(try XCTUnwrap(preview.pendingRequest))
        XCTAssertEqual(model.playingChannelID, model.channels[1].id)
    }

    func testSelectingAnotherChannelCancelsPendingPreview() throws {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        preview.focus(model.channels[0].id)
        let stale = try XCTUnwrap(preview.pendingRequest)
        preview.watch(model.channels[1].id)
        preview.commitPreview(stale)
        XCTAssertTrue(preview.isExpanded)
        XCTAssertEqual(model.playingChannelID, model.channels[1].id)
    }

    func testControlsSheetsAndInactiveSceneInvalidatePendingPreview() throws {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        preview.focus(model.channels[0].id)
        let stale = try XCTUnwrap(preview.pendingRequest)
        preview.setBrowsingActive(false)
        preview.commitPreview(stale)
        XCTAssertNil(model.playingChannelID)
        preview.focus(model.channels[1].id)
        XCTAssertNil(preview.pendingRequest)
        preview.setBrowsingActive(true)
        preview.commitPreview(try XCTUnwrap(preview.pendingRequest))
        XCTAssertEqual(model.playingChannelID, model.channels[1].id)
    }

    func testFilteringOutPendingChannelPreventsTune() throws {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        preview.focus(model.channels[0].id)
        let request = try XCTUnwrap(preview.pendingRequest)
        model.query = "no-matching-channel"
        preview.commitPreview(request)
        XCTAssertNil(model.playingChannelID)
        XCTAssertFalse(model.tuneFailed)
    }

    func testNoGuideStillPreviewsAndStoppingInvalidatesRequests() throws {
        let model = LiveTVPrototypeModel(scenario: .noGuide)
        let preview = LiveTVPreviewController(model: model)
        let channel = model.channels[0]
        XCTAssertNil(model.currentProgram(for: channel.id))
        XCTAssertFalse(channel.category.isEmpty)
        preview.focus(channel.id)
        preview.commitPreview(try XCTUnwrap(preview.pendingRequest))
        XCTAssertEqual(model.playingChannelID, channel.id)
        preview.focus(model.channels[1].id)
        let stale = try XCTUnwrap(preview.pendingRequest)
        preview.stop()
        preview.commitPreview(stale)
        XCTAssertNil(model.playingChannelID)
        XCTAssertFalse(preview.isExpanded)
    }

    func testTouchBrowsingCanKeepAutoplayOffUntilExplicitSelection() {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model, followsFocus: false)
        preview.focus(model.channels[0].id)
        XCTAssertNil(preview.pendingRequest)
        XCTAssertNil(model.playingChannelID)
        preview.watch(model.channels[0].id)
        XCTAssertTrue(preview.isExpanded)
        XCTAssertEqual(model.playingChannelID, model.channels[0].id)
    }

    func testLeavingTheDestinationStopsFullScreenWithoutChangingPreviewPreference() {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        preview.watch(model.channels[0].id)
        preview.stop()
        preview.setBrowsingActive(false)
        XCTAssertNil(model.playingChannelID)
        XCTAssertFalse(preview.isExpanded)
        XCTAssertFalse(preview.followsFocus)
        preview.focus(model.channels[1].id)
        XCTAssertNil(preview.pendingRequest)
    }

    func testReturningToDestinationCanPreviewTheRememberedChannelWithoutAcceptingOldWork() throws {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        let channelID = model.channels[0].id
        preview.focus(channelID)
        let oldRequest = try XCTUnwrap(preview.pendingRequest)
        preview.stop()
        preview.setBrowsingActive(false)
        preview.focus(channelID)
        XCTAssertFalse(preview.commitPreview(oldRequest))
        XCTAssertNil(model.playingChannelID)
        preview.setBrowsingActive(true)
        let newRequest = try XCTUnwrap(preview.pendingRequest)
        XCTAssertNotEqual(oldRequest, newRequest)
        XCTAssertTrue(preview.commitPreview(newRequest))
        XCTAssertEqual(model.playingChannelID, channelID)
    }

    func testFailedSelectionKeepsCurrentPreviewWithoutExpanding() throws {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        preview.focus(model.channels[0].id)
        preview.commitPreview(try XCTUnwrap(preview.pendingRequest))
        model.simulateTunerBusy = true
        preview.watch(model.channels[1].id)
        XCTAssertTrue(model.tuneFailed)
        XCTAssertFalse(preview.isExpanded)
        XCTAssertEqual(model.playingChannelID, model.channels[0].id)
    }

    func testReturningGuideGatesControlsUntilItsOwnFocusRequestCompletes() {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        let channelID = model.channels[0].id
        preview.watch(channelID)
        preview.returnToGuide()
        let first = preview.focusRestoreRequest
        XCTAssertTrue(preview.isRestoringGuideFocus)
        XCTAssertFalse(preview.isExpanded)
        XCTAssertEqual(model.playingChannelID, channelID)
        preview.watch(channelID)
        preview.returnToGuide()
        preview.completeGuideFocusRestore(first)
        XCTAssertTrue(preview.isRestoringGuideFocus)
        preview.completeGuideFocusRestore(preview.focusRestoreRequest)
        XCTAssertFalse(preview.isRestoringGuideFocus)
        XCTAssertEqual(model.playingChannelID, channelID)
    }

    func testStoppingAndTouchReturnCannotLeaveFocusRestorationLatched() {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        let channelID = model.channels[0].id
        preview.watch(channelID)
        preview.returnToGuide()
        preview.stop()
        XCTAssertFalse(preview.isRestoringGuideFocus)
        preview.watch(channelID)
        preview.returnToGuide(restoresFocus: false)
        XCTAssertFalse(preview.isRestoringGuideFocus)
        XCTAssertEqual(model.playingChannelID, channelID)
    }

    func testWatchingKeepsTheEntrySectionThroughRecentPromotionAndTransport() {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        let id = model.channels[0].id
        let origin = LiveTVGuideRowID(channelID: id, section: .favorites)
        preview.watch(id, origin: origin)
        model.recordWatched(id)
        preview.returnToGuide()
        XCTAssertEqual(preview.watchOrigin, origin)
        XCTAssertTrue(preview.restoresPlaybackFocus)
        preview.watch(id, origin: origin)
        let next = model.channels[1].id
        preview.watch(next)
        XCTAssertEqual(preview.watchOrigin, LiveTVGuideRowID(channelID: next, section: .favorites))
        preview.watch(model.channels[6].id)
        XCTAssertEqual(preview.watchOrigin?.section, .channels)
    }

    func testSidebarEntryHasABoundedRequestWithoutExpandingOrRetuning() throws {
        let model = LiveTVPrototypeModel()
        let preview = LiveTVPreviewController(model: model)
        preview.focus(model.channels[0].id)
        XCTAssertNotNil(preview.pendingRequest)
        preview.requestBrowsingFocus()
        XCTAssertNil(preview.pendingRequest)
        XCTAssertTrue(preview.isRestoringGuideFocus)
        XCTAssertFalse(preview.restoresPlaybackFocus)
        XCTAssertFalse(preview.isExpanded)
        XCTAssertNil(model.playingChannelID)
        let first = preview.focusRestoreRequest
        preview.requestBrowsingFocus()
        preview.completeGuideFocusRestore(first)
        XCTAssertTrue(preview.isRestoringGuideFocus)
        preview.completeGuideFocusRestore(preview.focusRestoreRequest)
        XCTAssertFalse(preview.isRestoringGuideFocus)
        let id = model.channels[0].id
        preview.watch(id)
        preview.requestBrowsingFocus()
        XCTAssertTrue(preview.isExpanded)
        preview.returnToGuide()
        XCTAssertTrue(preview.restoresPlaybackFocus)
    }
}

@MainActor
final class LiveTVGuideFocusTargetTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testReturnChoosesPlayingProgramRatherThanAnotherBrowsedChannel() throws {
        let model = try makeModel()
        model.tune("playing")
        XCTAssertEqual(
            LiveTVGuideFocusTarget.returningToPlayback(in: model, selectedChannelID: "other"),
            .program(channelID: "playing", programID: "current")
        )
    }

    func testReturnFollowsProgramRolloverWhileWatching() throws {
        let model = try makeModel()
        model.tune("playing")
        model.synchronizeClock(to: now.addingTimeInterval(1_801))
        XCTAssertEqual(
            LiveTVGuideFocusTarget.returningToPlayback(in: model, selectedChannelID: "playing"),
            .program(channelID: "playing", programID: "next")
        )
    }

    func testMissingGuideReturnsToThePlayingChannel() throws {
        let model = try makeModel()
        model.tune("other")
        XCTAssertEqual(
            LiveTVGuideFocusTarget.returningToPlayback(in: model, selectedChannelID: "playing"),
            .channel("other")
        )
    }

    func testReturnHonorsFiltersAndHandlesAnEmptyGuide() throws {
        let model = try makeModel()
        model.tune("playing")
        model.query = "other"
        XCTAssertEqual(
            LiveTVGuideFocusTarget.returningToPlayback(in: model, selectedChannelID: "playing"),
            .channel("other")
        )
        XCTAssertEqual(model.query, "other")
        model.query = "no matching channel"
        XCTAssertNil(LiveTVGuideFocusTarget.returningToPlayback(in: model, selectedChannelID: "playing"))
    }

    func testDuplicateChannelAndProgrammeOccurrencesHaveDistinctFocusIDs() {
        let sections: [LiveTVGuideSection] = [.recent, .favorites, .channels]
        let channels = sections.map { LiveTVGuideFocusTarget.channel("same", section: $0) }
        let programs = sections.map {
            LiveTVGuideFocusTarget.program(channelID: "same", programID: "current", section: $0)
        }
        XCTAssertEqual(Set(channels + programs).count, 6)
        XCTAssertEqual(Set((channels + programs).map(\.rowID)).count, 3)
    }

    func testReturnStaysInEachOriginSectionAfterRecentPromotion() throws {
        let model = try makeModel()
        model.toggleFavorite("playing")
        model.tune("playing")
        model.recordWatched("playing")
        for section in [LiveTVGuideSection.channels, .favorites, .recent] {
            XCTAssertEqual(
                LiveTVGuideFocusTarget.returningToPlayback(
                    in: model, selectedChannelID: "other",
                    originRow: LiveTVGuideRowID(channelID: "playing", section: section)
                ),
                .program(channelID: "playing", programID: "current", section: section)
            )
        }
    }

    func testRemovedShortcutFallsBackToTheSameChannelInMainList() throws {
        let model = try makeModel()
        model.toggleFavorite("playing")
        model.tune("playing")
        model.recordWatched("playing")
        let origin = LiveTVGuideRowID(channelID: "playing", section: .favorites)
        model.toggleFavorite("playing")
        XCTAssertEqual(
            LiveTVGuideFocusTarget.returningToPlayback(in: model, selectedChannelID: "other", originRow: origin),
            .program(channelID: "playing", programID: "current", section: .channels)
        )
        model.synchronizeClock(to: now.addingTimeInterval(1_801))
        XCTAssertEqual(
            LiveTVGuideFocusTarget.returningToPlayback(in: model, selectedChannelID: "other", originRow: origin),
            .program(channelID: "playing", programID: "next", section: .channels)
        )
    }

    func testMissingListingsKeepTheOriginOccurrenceAndFiltersStillApply() throws {
        let model = try makeModel()
        model.toggleFavorite("other")
        model.tune("other")
        model.recordWatched("other")
        let origin = LiveTVGuideRowID(channelID: "other", section: .favorites)
        XCTAssertEqual(
            LiveTVGuideFocusTarget.returningToPlayback(in: model, selectedChannelID: nil, originRow: origin),
            .channel("other", section: .favorites)
        )
        model.query = "playing"
        XCTAssertEqual(
            LiveTVGuideFocusTarget.returningToPlayback(in: model, selectedChannelID: nil, originRow: origin),
            .program(channelID: "playing", programID: "current")
        )
    }

    private func makeModel() throws -> LiveTVPrototypeModel {
        let channels = ["playing", "other"].enumerated().map { number, id in
            LiveTVPrototypeChannel(
                id: id, number: number, name: id, category: "News",
                symbol: "tv", accent: 0, source: .iptv, tagline: ""
            )
        }
        let model = LiveTVPrototypeModel(now: now, channels: channels)
        try model.replacePrograms([
            LiveTVPrototypeProgram(
                id: "current", channelID: "playing", title: "Current show", subtitle: "",
                start: now.addingTimeInterval(-1_800), end: now.addingTimeInterval(1_800)
            ),
            LiveTVPrototypeProgram(
                id: "next", channelID: "playing", title: "Next show", subtitle: "",
                start: now.addingTimeInterval(1_800), end: now.addingTimeInterval(3_600)
            )
        ])
        return model
    }
}
