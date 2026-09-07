import Foundation
import XCTest
@testable import FeatureLiveTVCore

@MainActor
final class LiveTVPrototypeImportModelTests: XCTestCase {
    func testChannelsPublishBeforeGuideAndGuideFailureDoesNotRemoveThem() async {
        let model = LiveTVPrototypeModel(channels: [])
        let channels = LiveTVPrototypeCatalog.channels
        let loader = ImportLoaderStub(channels: channels, guideFails: true) { @MainActor in
            XCTAssertEqual(model.channels, channels)
        }
        let imports = LiveTVPrototypeImportModel(loader: loader)
        await imports.reload(into: model)
        XCTAssertEqual(imports.playlistPhase, .loaded)
        XCTAssertEqual(imports.guidePhase, .failed)
        XCTAssertFalse(imports.isLoading)
        XCTAssertEqual(imports.entryCount, channels.count)
        XCTAssertEqual(model.channels, channels)
        XCTAssertTrue(model.channels.allSatisfy { model.currentProgram(for: $0.id) == nil })
    }

    func testSuccessfulGuideImportUsesActualProgramsAndReportsCoverage() async {
        let channels = LiveTVPrototypeCatalog.channels
        let now = Date()
        let program = LiveTVPrototypeProgram(
            id: "real-program", channelID: channels[0].id, title: "Actual schedule",
            subtitle: "", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(3_600)
        )
        let loader = ImportLoaderStub(channels: channels, programs: [program])
        let model = LiveTVPrototypeModel(now: now, channels: [])
        let imports = LiveTVPrototypeImportModel(loader: loader)
        await imports.reload(into: model)
        XCTAssertEqual(imports.guidePhase, .loaded)
        XCTAssertEqual(imports.matchedChannelCount, 1)
        XCTAssertEqual(imports.programCount, 1)
        XCTAssertEqual(imports.coverageStart, program.start)
        XCTAssertEqual(imports.coverageEnd, program.end)
        XCTAssertEqual(model.currentProgram(for: channels[0].id), program)
        XCTAssertNotNil(imports.lastGuideRefresh)
    }

    func testPlaylistFailurePreservesExistingChannelsAndDoesNotAttemptGuide() async {
        let channels = LiveTVPrototypeCatalog.channels
        let loader = ImportLoaderStub(channels: channels, playlistFails: true)
        let model = LiveTVPrototypeModel(channels: channels)
        model.toggleFavorite(channels[0].id)
        let imports = LiveTVPrototypeImportModel(loader: loader)
        await imports.reload(into: model)
        XCTAssertEqual(imports.playlistPhase, .failed)
        XCTAssertEqual(model.channels, channels)
        XCTAssertTrue(model.favoriteIDs.contains(channels[0].id))
        XCTAssertFalse(imports.isLoading)
        let guideLoads = await loader.guideLoads
        XCTAssertEqual(guideLoads, 0)
    }

    func testStressCopiesAreNotSubmittedAsAdditionalGuideMatches() async {
        let channels = LiveTVPrototypeCatalog.channels
        let loader = ImportLoaderStub(channels: channels)
        let model = LiveTVPrototypeModel(isLargeCatalog: true, channels: [])
        let imports = LiveTVPrototypeImportModel(loader: loader)
        await imports.reload(into: model)
        XCTAssertEqual(model.channels.count, 5_000)
        let submittedChannels = await loader.submittedChannelCount
        XCTAssertEqual(submittedChannels, channels.count)
    }

    func testLateOrCancelledRefreshCannotOverwriteANewerImport() async {
        for cancelFirst in [false, true] {
            let started = expectation(description: "First playlist is suspended")
            let old = LiveTVPrototypeCatalog.channels[0]
            let fresh = LiveTVPrototypeCatalog.channels[1]
            let loader = OverlappingImportLoader(old: old, fresh: fresh, started: started)
            let model = LiveTVPrototypeModel(channels: [])
            let imports = LiveTVPrototypeImportModel(loader: loader)
            let first = Task { await imports.reload(into: model) }
            await fulfillment(of: [started], timeout: 2)
            if cancelFirst { first.cancel() }
            await imports.reload(into: model)
            await loader.finishFirst()
            await first.value
            XCTAssertEqual(model.channels, [fresh])
            XCTAssertEqual(imports.playlistPhase, .loaded)
            XCTAssertEqual(imports.guidePhase, .loaded)
            XCTAssertFalse(imports.isLoading)
        }
    }
}

private actor OverlappingImportLoader: LiveTVSourceLoading {
    let old: LiveTVPrototypeChannel
    let fresh: LiveTVPrototypeChannel
    let started: XCTestExpectation
    private var callCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    init(old: LiveTVPrototypeChannel, fresh: LiveTVPrototypeChannel, started: XCTestExpectation) {
        self.old = old
        self.fresh = fresh
        self.started = started
    }

    func loadPlaylist(from url: URL) async throws -> LiveTVPlaylistImport {
        callCount += 1
        let first = callCount == 1
        if first {
            await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        return LiveTVPlaylistImport(channels: [first ? old : fresh], entryCount: 1, skippedEntryCount: 0)
    }

    func finishFirst() {
        continuation?.resume()
        continuation = nil
    }

    func loadGuide(
        from url: URL, channels: [LiveTVPrototypeChannel], now: Date
    ) async throws -> LiveTVGuideImport {
        LiveTVGuideImport(
            programs: [], matchedChannelCount: 0, guideChannelCount: 0, programCount: 0,
            coverageStart: nil, coverageEnd: nil
        )
    }
}

private actor ImportLoaderStub: LiveTVSourceLoading {
    enum Failure: Error { case unavailable }
    let channels: [LiveTVPrototypeChannel]
    let programs: [LiveTVPrototypeProgram]
    let playlistFails: Bool
    let guideFails: Bool
    let beforeGuide: @Sendable () async -> Void
    private(set) var guideLoads = 0
    private(set) var submittedChannelCount = 0

    init(
        channels: [LiveTVPrototypeChannel], programs: [LiveTVPrototypeProgram] = [],
        playlistFails: Bool = false, guideFails: Bool = false,
        beforeGuide: @escaping @Sendable () async -> Void = {}
    ) {
        self.channels = channels
        self.programs = programs
        self.playlistFails = playlistFails
        self.guideFails = guideFails
        self.beforeGuide = beforeGuide
    }

    func loadPlaylist(from url: URL) async throws -> LiveTVPlaylistImport {
        if playlistFails { throw Failure.unavailable }
        return LiveTVPlaylistImport(channels: channels, entryCount: channels.count, skippedEntryCount: 0)
    }

    func loadGuide(
        from url: URL, channels: [LiveTVPrototypeChannel], now: Date
    ) async throws -> LiveTVGuideImport {
        guideLoads += 1
        submittedChannelCount = channels.count
        await beforeGuide()
        if guideFails { throw Failure.unavailable }
        return LiveTVGuideImport(
            programs: programs, matchedChannelCount: Set(programs.map(\.channelID)).count,
            guideChannelCount: Set(programs.map(\.channelID)).count, programCount: programs.count,
            coverageStart: programs.map(\.start).min(), coverageEnd: programs.map(\.end).max()
        )
    }
}
