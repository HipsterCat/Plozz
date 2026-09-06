import Foundation
import XCTest
@testable import FeatureLiveTVCore

@MainActor
final class LiveTVPrototypeModelTests: XCTestCase {
    func testNoGuideCatalogRemainsSearchableAndFavoritable() throws {
        let model = LiveTVPrototypeModel(scenario: .noGuide)

        XCTAssertEqual(model.channels.count, 30)
        XCTAssertEqual(model.channel(id: model.channels[0].id), model.channels[0])
        XCTAssertEqual(model.categories, model.categories.sorted())
        XCTAssertTrue(model.channels.allSatisfy {
            model.currentProgram(for: $0.id) == nil
                && model.programs(for: $0.id, from: model.now).isEmpty
        })

        model.query = "quiet channel"
        let channel = try XCTUnwrap(model.visibleChannels.first)
        XCTAssertEqual(channel.name, "Quiet Channel")
        XCTAssertFalse(model.favoriteIDs.contains(channel.id))

        model.toggleFavorite(channel.id)
        model.favoritesOnly = true

        XCTAssertEqual(model.visibleChannels.map(\.id), [channel.id])
    }

    func testGuideCoverageMatchesScenariosAndIncludesEveryPlozzChannel() {
        let model = LiveTVPrototypeModel(scenario: .noGuide)
        let coveredCount = {
            model.channels.filter {
                model.currentProgram(for: $0.id) != nil
            }.count
        }

        XCTAssertEqual(coveredCount(), 0)
        model.scenario = .failedGuide
        XCTAssertEqual(coveredCount(), 0)

        model.scenario = .mixedGuide
        let mixedCount = coveredCount()
        XCTAssertGreaterThan(mixedCount, 10)
        XCTAssertLessThan(mixedCount, 20)
        XCTAssertTrue(
            model.channels
                .filter { $0.source == .plozz }
                .allSatisfy { model.currentProgram(for: $0.id) != nil }
        )

        model.scenario = .fullGuide
        XCTAssertEqual(coveredCount(), 30)
        model.scenario = .staleGuide
        XCTAssertEqual(coveredCount(), 30)
    }

    func testProgramsUseStableAbsoluteSlotsAndBoundedRequests() throws {
        let model = LiveTVPrototypeModel(scenario: .fullGuide)
        let channel = try XCTUnwrap(model.channels.first)
        let requestedStart = Date(timeIntervalSince1970: 1_788_719_777)
        let first = model.programs(for: channel.id, from: requestedStart, hours: 3)

        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(first.allSatisfy {
            [1_800.0, 3_600.0].contains($0.end.timeIntervalSince($0.start))
        })
        XCTAssertTrue(first.allSatisfy {
            Int($0.start.timeIntervalSince1970).isMultiple(of: 1_800)
        })
        XCTAssertLessThanOrEqual(
            model.programs(for: channel.id, from: requestedStart, hours: 100).count,
            49
        )

        model.advanceClock(by: 7_200)
        let second = model.programs(for: channel.id, from: requestedStart, hours: 3)
        XCTAssertEqual(second, first)
        let freshModel = LiveTVPrototypeModel(scenario: .fullGuide)
        XCTAssertEqual(
            freshModel.programs(for: channel.id, from: requestedStart, hours: 3),
            first
        )

        let program = try XCTUnwrap(first.first)
        XCTAssertEqual(program.progress(at: program.start.addingTimeInterval(-1)), 0)
        XCTAssertEqual(program.progress(at: program.end.addingTimeInterval(1)), 1)
        XCTAssertEqual(
            program.progress(at: program.start.addingTimeInterval(program.end.timeIntervalSince(program.start) / 2)),
            0.5,
            accuracy: 0.000_001
        )
    }

    func testFiltersCombineResetAndPreserveSort() {
        let model = LiveTVPrototypeModel()
        model.sort = .name
        model.query = "CINÉMA"
        model.category = "Movies"
        model.source = .jellyfin
        model.favoritesOnly = true

        XCTAssertEqual(model.visibleChannels.map(\.name), ["Cinema Club"])

        model.resetFilters()

        XCTAssertEqual(model.query, "")
        XCTAssertNil(model.category)
        XCTAssertNil(model.source)
        XCTAssertFalse(model.favoritesOnly)
        XCTAssertEqual(model.sort, .name)
        XCTAssertEqual(model.visibleChannels.count, 30)
        XCTAssertEqual(
            model.visibleChannels.map(\.name),
            model.visibleChannels.map(\.name).sorted {
                let locale = Locale(identifier: "en_US_POSIX")
                return $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
                    < $1.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            }
        )
    }

    func testSearchIsDiacriticInsensitiveAndRanksExactNumberFirst() {
        let model = LiveTVPrototypeModel()

        model.query = "cafe"
        XCTAssertEqual(model.visibleChannels.map(\.name), ["Café Society"])

        model.sort = .name
        model.query = "2"
        XCTAssertEqual(model.visibleChannels.first?.number, 2)
        XCTAssertTrue(model.visibleChannels.dropFirst().contains { $0.number == 20 })
    }

    func testLogoMetadataSurvivesCatalogExpansionAndHasSafePublicURLs() throws {
        let model = LiveTVPrototypeModel(channels: LiveTVPrototypeCatalog.channels)
        let original = model.channels
        XCTAssertEqual(original.compactMap(\.logoURL).count, original.count)
        XCTAssertTrue(original.compactMap(\.logoURL).allSatisfy {
            $0.scheme == "https" && $0.user == nil && $0.password == nil
        })
        model.isLargeCatalog = true
        XCTAssertEqual(Array(model.channels.prefix(original.count)), original)
        XCTAssertEqual(model.channels[original.count].logoURL, original[0].logoURL)
        XCTAssertEqual(model.channels[original.count].streamURL, original[0].streamURL)
        let tastemade = try XCTUnwrap(model.channels.first { $0.name == "Tastemade" })
        XCTAssertTrue(tastemade.logoNeedsDarkBackground)
    }

    func testRealChannelsNeverAcquireSyntheticGuidePrograms() {
        let model = LiveTVPrototypeModel(channels: LiveTVPrototypeCatalog.channels)
        XCTAssertTrue(model.usesPublicStreams)
        XCTAssertEqual(Set(model.channels.map(\.id)).count, model.channels.count)
        XCTAssertEqual(model.channels.map(\.number), Array(1...model.channels.count))
        XCTAssertTrue(model.channels.allSatisfy {
            $0.source == .iptv && $0.streamURL?.scheme == "https"
                && $0.streamURL?.user == nil && $0.streamURL?.password == nil
        })
        for scenario in LiveTVPrototypeScenario.allCases {
            model.scenario = scenario
            XCTAssertTrue(model.channels.allSatisfy {
                model.programs(for: $0.id, from: model.now).isEmpty
            })
        }
        model.query = "espanol"
        XCTAssertEqual(model.visibleChannels.map(\.name), ["DW Español"])
    }

    func testPrototypeLaunchPersistenceIsExplicitAndReversible() throws {
        let suite = "LiveTVPrototypeLaunchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(LiveTVPrototypeLaunch.isEnabled(arguments: [], defaults: defaults))
        XCTAssertTrue(LiveTVPrototypeLaunch.isEnabled(arguments: ["--live-tv-prototype"], defaults: defaults))
        XCTAssertFalse(LiveTVPrototypeLaunch.isEnabled(arguments: [], defaults: defaults))
        XCTAssertTrue(LiveTVPrototypeLaunch.isEnabled(arguments: ["--live-tv-prototype-remember"], defaults: defaults))
        XCTAssertTrue(LiveTVPrototypeLaunch.isEnabled(arguments: [], defaults: defaults))
        XCTAssertFalse(LiveTVPrototypeLaunch.isEnabled(
            arguments: ["--live-tv-prototype-off", "--live-tv-prototype-remember", "--live-tv-prototype"],
            defaults: defaults
        ))
        XCTAssertFalse(LiveTVPrototypeLaunch.isEnabled(arguments: [], defaults: defaults))
    }

    func testLargeCatalogKeepsBaseIDsAndOffCatalogFavorites() throws {
        let model = LiveTVPrototypeModel()
        let baseIDs = model.channels.map(\.id)
        let baseFavoriteIDs = model.favoriteIDs

        model.isLargeCatalog = true

        XCTAssertEqual(model.channels.count, 5_000)
        XCTAssertEqual(Array(model.channels.prefix(30).map(\.id)), baseIDs)
        XCTAssertTrue(baseFavoriteIDs.isSubset(of: model.favoriteIDs))
        let largeOnlyID = try XCTUnwrap(model.channels.last?.id)
        model.toggleFavorite(largeOnlyID)

        model.isLargeCatalog = false
        XCTAssertTrue(model.favoriteIDs.contains(largeOnlyID))
        XCTAssertEqual(model.channels.count, 30)

        model.isLargeCatalog = true
        model.favoritesOnly = true
        XCTAssertTrue(model.visibleChannels.contains { $0.id == largeOnlyID })
    }

    func testShrinkingCatalogReleasesUnavailableDemoChannel() throws {
        let model = LiveTVPrototypeModel(isLargeCatalog: true)
        let largeOnlyID = try XCTUnwrap(model.channels.last?.id)
        model.tune(largeOnlyID)
        model.togglePause()
        model.advanceClock(by: 30)

        model.isLargeCatalog = false

        XCTAssertNil(model.playingChannelID)
        XCTAssertNil(model.previousChannelID)
        XCTAssertFalse(model.isPaused)
        XCTAssertEqual(model.behindLiveSeconds, 0)
    }

    func testTunePausePreviousBusyAndStopBehavior() throws {
        let model = LiveTVPrototypeModel()
        let first = try XCTUnwrap(model.channels.first?.id)
        let second = try XCTUnwrap(model.channels.dropFirst().first?.id)

        model.tune("not-a-fixture-channel")
        XCTAssertTrue(model.tuneFailed)
        XCTAssertNil(model.playingChannelID)
        model.clearTuneFailure()

        model.tune(first)
        XCTAssertEqual(model.playingChannelID, first)
        XCTAssertNil(model.previousChannelID)

        model.simulateTunerBusy = true
        model.tune(first)
        XCTAssertFalse(model.tuneFailed)
        model.tune(second)
        XCTAssertTrue(model.tuneFailed)
        XCTAssertEqual(model.playingChannelID, first)

        model.simulateTunerBusy = false
        model.tune(second)
        XCTAssertEqual(model.playingChannelID, second)
        XCTAssertEqual(model.previousChannelID, first)

        model.togglePause()
        model.advanceClock(by: 45)
        XCTAssertTrue(model.isPaused)
        XCTAssertEqual(model.behindLiveSeconds, 45)
        model.togglePause()
        model.advanceClock(by: 15)
        XCTAssertEqual(model.behindLiveSeconds, 45)
        model.goLive()
        XCTAssertFalse(model.isPaused)
        XCTAssertEqual(model.behindLiveSeconds, 0)

        model.tunePrevious()
        XCTAssertEqual(model.playingChannelID, first)
        XCTAssertEqual(model.previousChannelID, second)
        model.tunePrevious()
        XCTAssertEqual(model.playingChannelID, second)
        XCTAssertEqual(model.previousChannelID, first)

        model.stop()
        XCTAssertNil(model.playingChannelID)
        XCTAssertNil(model.previousChannelID)
        XCTAssertFalse(model.isPaused)
        XCTAssertEqual(model.behindLiveSeconds, 0)
        XCTAssertFalse(model.tuneFailed)
    }
}
