import CoreModels
import FeatureLiveTVCore
import Foundation
@testable import ProviderIPTV
import XCTest

@MainActor
final class IPTVLiveTVImportTests: XCTestCase {
    func testLegacyDiscoveryUpdatesTheActiveGuideWithoutReloadAndRespectsFailuresAndAuthorization() async throws {
        for outcome in ["guide", "empty", "failed", "revoked", "cancelled"] {
            IPTVFixture.state.reset()
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            addTeardownBlock { try FileManager.default.removeItem(at: root) }
            let body = "#EXTINF:-1 tvg-id=\"news\",News\nhttps://provider.test/live/1.ts\n"
            IPTVFixture.state.handler = { _ in (200, [:], Data(("#EXTM3U\n" + body).utf8)) }
            let credential = try IPTVCredential(
                mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test/list")),
                discoversPlaylistGuides: false
            )
            let session = try await IPTVProvider.signIn(
                credential: credential, name: "Fixture", deviceID: "fixture",
                cacheDirectory: root, configuration: IPTVFixture.configuration()
            )
            do {
                let saved = try IPTVCatalog(
                    url: root.appendingPathComponent(credential.identity.uuidString + ".sqlite"), key: credential.catalogKey
                )
                try saved.execute("DELETE FROM state WHERE key = 'playlist-v5'")
                try saved.setState("playlist-v4", String(Date().timeIntervalSince1970))
            }
            let provider = try IPTVProvider(
                context: .init(session: session, accountID: "account", credentialRevision: .init(),
                               localMediaContext: .init(accountID: "account", profileID: "fixture", profileNamespace: nil)),
                cacheDirectory: root, configuration: IPTVFixture.configuration(),
                guideLoader: { _, _, channels, from, to in
                    channels.map {
                        .init(id: $0.id, channelID: $0.id, title: "Recovered", startDate: from, endDate: to)
                    }
                }
            )
            addTeardownBlock { await provider.teardown() }
            let entered = expectation(description: "Legacy discovery refresh \(outcome)")
            let gate = DispatchSemaphore(value: 0)
            defer { gate.signal() }
            IPTVFixture.state.handler = { request in
                if request.url?.path == "/guide.xml" { return (200, [:], Data("<tv/>".utf8)) }
                entered.fulfill()
                guard gate.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
                if outcome == "failed" { return (503, [:], Data()) }
                let header = outcome == "empty" ? "#EXTM3U" : "#EXTM3U tvg-url=\"https://provider.test/guide.xml\""
                return (200, [:], Data((header + "\n" + body).utf8))
            }
            let imports = LiveTVPrototypeImportModel(
                configuration: .init(servers: [.init(id: "source", name: "Fixture", accountID: "account")]),
                serverProviderResolver: { _ in
                    .init(accountID: "account", authorizationID: "fixture", kind: .iptv, provider: provider)
                }
            )
            let model = LiveTVPrototypeModel(channels: [])
            let load = Task { await imports.reload(into: model, forceServerRefresh: false) }
            await fulfillment(of: [entered], timeout: 3)
            let deadline = ContinuousClock.now + .seconds(3)
            while (model.channels.isEmpty || imports.catalogPhase != .loaded), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(model.channels.map(\.name), ["News"])
            XCTAssertEqual(imports.catalogPhase, .loaded, "Guide discovery must not block saved channels.")
            XCTAssertFalse(imports.isLoading)
            XCTAssertEqual(imports.serverSources.first?.availability?.supportsGuide, false)
            let savedIDs = model.channels.map(\.id)
            if outcome == "revoked" {
                try imports.setServerProviderResolver({ _ in nil }, into: model)
            } else if outcome == "cancelled" {
                load.cancel()
                await load.value
            }
            gate.signal()
            await load.value
            if outcome == "revoked" {
                XCTAssertTrue(model.channels.isEmpty)
                XCTAssertEqual(imports.serverSources.first?.failure, .accountUnavailable)
            } else {
                XCTAssertEqual(model.channels.map(\.id), savedIDs)
                XCTAssertEqual(imports.serverSources.first?.phase, .loaded)
                XCTAssertEqual(imports.serverSources.first?.availability?.supportsGuide, outcome == "guide")
            }
            XCTAssertEqual(imports.programCount, outcome == "guide" ? 1 : 0)
            if outcome == "guide" {
                XCTAssertEqual(imports.serverSources.first?.guidePhase, .loaded)
            } else if outcome == "failed" {
                XCTAssertEqual(imports.serverSources.first?.guidePhase, .failed)
                XCTAssertNotNil(imports.serverSources.first?.guideFailure)
            }
            XCTAssertEqual(IPTVFixture.state.requests.filter { $0.url?.path == "/list" }.count, 2)
            XCTAssertEqual(
                IPTVFixture.state.requests.filter { $0.url?.path == "/guide.xml" }.count, outcome == "guide" ? 1 : 0
            )
            await provider.teardown()
        }
        IPTVFixture.state.reset()
    }

    func testMissingWholeGuideIsFetchedOncePerRefreshWithoutLosingSavedRowsOrOtherSources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            IPTVFixture.state.reset()
            try? FileManager.default.removeItem(at: root)
        }
        let count = 4_001
        let firstPlaylist = "#EXTM3U tvg-url=\"https://provider.test/first.xml\"\n"
            + (0..<count).map {
                "#EXTINF:-1 tvg-id=\"station-\($0)\",Channel \($0)\nhttps://provider.test/live/\($0).ts\n"
            }.joined()
        let secondPlaylist = """
        #EXTM3U tvg-url="https://provider.test/second.xml"
        #EXTINF:-1,Other source
        https://provider.test/other.ts

        """
        func configureResponses(failing: Bool) {
            IPTVFixture.state.handler = { request in
                switch request.url?.path {
                case "/first": return (200, [:], Data(firstPlaylist.utf8))
                case "/second": return (200, [:], Data(secondPlaylist.utf8))
                case "/first.xml" where failing: return (404, ["Content-Type": "text/html"], Data())
                case "/first.xml", "/second.xml":
                    return (200, ["Cache-Control": "no-store"], Data("<tv/>".utf8))
                default:
                    XCTFail("Guide refresh must not open playback")
                    throw URLError(.badURL)
                }
            }
        }
        configureResponses(failing: false)
        var contexts: [String: LiveTVAuthorizedServerProvider] = [:]
        for id in ["first", "second"] {
            let credential = try IPTVCredential(
                mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test/\(id)"))
            )
            let session = try await IPTVProvider.signIn(
                credential: credential, name: id, deviceID: "fixture",
                cacheDirectory: root, configuration: IPTVFixture.configuration()
            )
            let provider = try IPTVProvider(
                context: .init(session: session, accountID: id, credentialRevision: .init(),
                               localMediaContext: .init(accountID: id, profileID: "fixture", profileNamespace: nil)),
                cacheDirectory: root, configuration: IPTVFixture.configuration(),
                guideLoader: { _, _, channels, from, to in
                    channels.map {
                        .init(id: $0.id, channelID: $0.id, title: "Saved listing", startDate: from, endDate: to)
                    }
                }
            )
            addTeardownBlock { await provider.teardown() }
            contexts[id] = .init(accountID: id, authorizationID: id, kind: .iptv, provider: provider)
        }
        let authorized = contexts
        let imports = LiveTVPrototypeImportModel(
            configuration: .init(servers: [
                .init(id: "first", name: "First", accountID: "first"),
                .init(id: "second", name: "Second", accountID: "second")
            ]),
            serverProviderResolver: { authorized[$0] }
        )
        let now = Date(timeIntervalSince1970: 100)
        let model = LiveTVPrototypeModel(now: now, channels: [])
        await imports.reload(into: model, forceServerRefresh: false)
        XCTAssertEqual(model.channels.count, count + 1)
        XCTAssertEqual(imports.programCount, count + 1)
        for expectedRequests in 1...2 {
            if expectedRequests == 1 {
                IPTVFixture.state.reset()
                configureResponses(failing: true)
            }
            await imports.reloadServerGuides(
                channelIDs: model.channels.map(\.id), from: now, to: now.addingTimeInterval(3_600),
                into: model, force: true
            )
            XCTAssertEqual(IPTVFixture.state.requests.filter { $0.url?.path == "/first.xml" }.count, expectedRequests)
            XCTAssertEqual(IPTVFixture.state.requests.filter { $0.url?.path == "/second.xml" }.count, expectedRequests)
            XCTAssertEqual(imports.serverSources.first { $0.id == "first" }?.guideFailure, .guideUnavailable)
            XCTAssertEqual(imports.serverSources.first { $0.id == "second" }?.guidePhase, .loaded)
            XCTAssertEqual(imports.serverGuideWindows.filter { $0.sourceID == "first" && $0.phase == .failed }.count, 3)
            XCTAssertEqual(imports.programCount, count + 1, "Ordinary guide failure must preserve last-good listings")
            XCTAssertEqual(model.channels.count, count + 1)
        }
        configureResponses(failing: false)
        await imports.reloadServerGuides(
            channelIDs: model.channels.map(\.id), from: now, to: now.addingTimeInterval(3_600),
            into: model, force: true
        )
        XCTAssertEqual(IPTVFixture.state.requests.filter { $0.url?.path == "/first.xml" }.count, 5)
        XCTAssertTrue(imports.serverSources.allSatisfy { $0.guidePhase == .loaded && $0.guideFailure == nil })
        for context in contexts.values {
            if let provider = context.provider as? IPTVProvider { await provider.teardown() }
        }
    }

    func testExpiredPlaylistPublishesSavedChannelsWithoutWaitingForRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            IPTVFixture.state.reset()
            try? FileManager.default.removeItem(at: root)
        }
        let body = Data("#EXTM3U\n#EXTINF:-1,News\nhttps://provider.test/live/1.ts\n".utf8)
        IPTVFixture.state.handler = { _ in (200, [:], body) }
        let credential = try IPTVCredential(
            mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test/list"))
        )
        let session = try await IPTVProvider.signIn(
            credential: credential, name: "Fixture", deviceID: "fixture",
            cacheDirectory: root, configuration: IPTVFixture.configuration()
        )
        do {
            let saved = try IPTVCatalog(
                url: root.appendingPathComponent(credential.identity.uuidString + ".sqlite"), key: credential.catalogKey
            )
            try saved.setState("playlist-v5", String(Date().addingTimeInterval(-3_600).timeIntervalSince1970))
        }
        let provider = try IPTVProvider(
            context: .init(session: session, accountID: "account", credentialRevision: .init(),
                           localMediaContext: .init(accountID: "account", profileID: "fixture", profileNamespace: nil)),
            cacheDirectory: root, configuration: IPTVFixture.configuration()
        )
        let started = expectation(description: "Automatic playlist refresh started")
        let published = expectation(description: "Saved guide exits loading while the provider is delayed")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        IPTVFixture.state.handler = { _ in
            started.fulfill()
            guard gate.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
            return (200, [:], body)
        }
        var configuration = LiveTVSourcesConfiguration()
        configuration.servers = [.init(id: "server", name: "Fixture", accountID: "account")]
        let imports = LiveTVPrototypeImportModel(
            configuration: configuration,
            serverProviderResolver: { _ in
                .init(accountID: "account", authorizationID: "fixture", kind: .iptv, provider: provider)
            }
        )
        let model = LiveTVPrototypeModel(channels: [])
        let load = Task { @MainActor in
            await imports.reload(into: model, forceServerRefresh: false)
            XCTAssertEqual(model.channels.map(\.name), ["News"])
            XCTAssertEqual(imports.catalogPhase, .loaded)
            XCTAssertFalse(imports.isLoading)
            XCTAssertEqual(imports.serverSources.first?.availability?.supportsGuide, false)
            published.fulfill()
        }
        await fulfillment(of: [started, published], timeout: 1)
        await provider.teardown()
        gate.signal()
        await load.value
        XCTAssertEqual(IPTVFixture.state.requests.count, 2, "Opening Live TV must coalesce its stale reads")
    }

    func testAutomaticGuideEnrollmentReusesImportButExplicitRefreshFetchesAgain() async throws {
        PerformanceDiagnostics.shared.start()
        defer { PerformanceDiagnostics.shared.stop() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            IPTVFixture.state.reset()
            try? FileManager.default.removeItem(at: root)
        }
        IPTVFixture.state.handler = { _ in
            (200, [:], Data("#EXTM3U\n#EXTINF:-1,News\nhttps://provider.test/live/1.ts\n".utf8))
        }
        let credential = try IPTVCredential(
            mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test/list"))
        )
        let session = try await IPTVProvider.signIn(
            credential: credential, name: "Fixture", deviceID: "fixture",
            cacheDirectory: root, configuration: IPTVFixture.configuration()
        )
        let imported = try XCTUnwrap(PerformanceDiagnostics.shared.snapshot())
        let records = imported.recent + imported.slow
        let importRecord = try XCTUnwrap(records.first { $0.operation == .playlistImport })
        let commitRecord = try XCTUnwrap(records.first { $0.operation == .playlistCommit })
        XCTAssertEqual(importRecord.outcome, .succeeded)
        XCTAssertEqual(importRecord.provider, .iptv)
        XCTAssertEqual(importRecord.metrics.items, 1)
        XCTAssertEqual(importRecord.metrics.requests, 1)
        XCTAssertGreaterThan(importRecord.metrics.bytes ?? 0, 0)
        XCTAssertEqual(commitRecord.outcome, .succeeded)
        XCTAssertEqual(commitRecord.metrics.rows, 1)
        XCTAssertTrue(imported.active.isEmpty)
        let provider = try IPTVProvider(
            context: .init(session: session, accountID: "account", credentialRevision: .init(),
                           localMediaContext: .init(accountID: "account", profileID: "fixture", profileNamespace: nil)),
            cacheDirectory: root, configuration: IPTVFixture.configuration()
        )
        let source = LiveTVServerSource(id: "server", name: "Fixture", accountID: "account")
        var configuration = LiveTVSourcesConfiguration()
        configuration.servers = [source]
        let imports = LiveTVPrototypeImportModel(
            configuration: configuration,
            serverProviderResolver: { _ in
                .init(accountID: "account", authorizationID: "fixture", kind: .iptv, provider: provider)
            }
        )
        let model = LiveTVPrototypeModel(channels: [])
        await imports.reload(into: model, forceServerRefresh: false)
        let refreshed = try XCTUnwrap(PerformanceDiagnostics.shared.snapshot())
        let refreshRecord = try XCTUnwrap(
            (refreshed.recent + refreshed.slow).first { $0.operation == .liveTVRefresh }
        )
        XCTAssertEqual(refreshRecord.outcome, .succeeded)
        XCTAssertEqual(refreshRecord.metrics.accounts, 1)
        XCTAssertEqual(refreshRecord.metrics.items, 1)
        XCTAssertEqual(model.channels.count, 1)
        XCTAssertEqual(IPTVFixture.state.requests.count, 1, "Automatic guide loading must not reimport the account.")
        XCTAssertEqual(imports.serverSources.first?.availability?.supportsGuide, false)
        XCTAssertEqual(imports.serverSources.first?.guidePhase, .idle)
        XCTAssertTrue(imports.serverGuideWindows.isEmpty)
        XCTAssertFalse(imports.isLoading)
        let channel = try XCTUnwrap(model.channels.first)
        let end = model.now.addingTimeInterval(21_600)
        XCTAssertEqual(imports.gapState(for: channel), .disabled)
        XCTAssertEqual(imports.gapState(for: channel, from: model.now, to: end), .disabled)
        XCTAssertEqual(imports.gapState(for: channel).title, "No program guide available")
        for force in [false, true] {
            await imports.reloadServerGuides(
                channelIDs: [channel.id], from: model.now, to: end, into: model, force: force
            )
            XCTAssertTrue(imports.serverGuideWindows.isEmpty, "Browsing must not start a nonexistent guide request.")
            XCTAssertEqual(imports.gapState(for: channel), .disabled)
        }
        await imports.reloadServers(into: model, forceRefresh: false)
        XCTAssertEqual(IPTVFixture.state.requests.count, 1)
        await imports.reload(into: model)
        XCTAssertEqual(IPTVFixture.state.requests.count, 2, "An explicit refresh must still bypass the cache.")
        await provider.teardown()
    }

    func testPlaylistAccountLoadsLargeLiveLineupWithoutAMovieLibrary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("channels.m3u")
        var playlist = """
        #EXTM3U
        #EXTINF:-1 tvg-name="News24 City" group-title="Italy",News24 City
        https://dc3.telesveva.com:4433/news24.mp4
        #EXTINF:-1 tvg-name="Tv Uno" group-title="Italy",Tv Uno
        http://ftp.tiscali.it/francescovernata/TVUNO/monoscopioTvUNOint-1.wmv

        """
        for index in 0..<2_078 {
            playlist += "#EXTINF:-1,Channel \(index)\nhttps://provider.example/live/\(index).m3u8\n"
        }
        try Data(playlist.utf8).write(to: file)
        let credential = try IPTVCredential(
            mode: .file, address: XCTUnwrap(URL(string: "https://imported-playlist.invalid"))
        )
        PerformanceDiagnostics.shared.start()
        defer { PerformanceDiagnostics.shared.stop() }
        let session = try await IPTVProvider.importFile(
            file, credential: credential, name: "Playlist", deviceID: "fixture", cacheDirectory: root
        )
        let snapshot = try XCTUnwrap(PerformanceDiagnostics.shared.snapshot())
        let imported = try XCTUnwrap((snapshot.recent + snapshot.slow).first { $0.operation == .playlistImport })
        XCTAssertEqual(imported.outcome, .succeeded)
        XCTAssertEqual(imported.metrics.items, 2_080)
        XCTAssertEqual(imported.metrics.requests, 0, "A local file import must not be reported as network fetching.")
        XCTAssertEqual(imported.metrics.bytes, playlist.utf8.count)
        let provider = try IPTVProvider(
            context: .init(
                session: session, accountID: "iptv-account", credentialRevision: .init(),
                localMediaContext: .init(accountID: "iptv-account", profileID: "viewer", profileNamespace: nil)
            ),
            cacheDirectory: root
        )
        do {
            let libraries = try await provider.libraries()
            XCTAssertTrue(libraries.isEmpty, "A live playlist must not trigger movie-library setup")
            let context = LiveTVAuthorizedServerProvider(
                accountID: "iptv-account", authorizationID: "viewer-authorization", kind: .iptv, provider: provider
            )
            var configuration = LiveTVSourcesConfiguration()
            let enrollment = LiveTVServerEnrollmentCoordinator()
            let added = await enrollment.refresh(
                choices: [.init(id: context.accountID, name: "Playlist", userName: "IPTV", kind: .iptv)],
                resolver: { $0 == context.accountID ? context : nil },
                configuration: { configuration }, suppressedAccountIDs: { [] },
                apply: { configuration = $0 }
            )
            XCTAssertEqual(added.count, 1)
            let imports = LiveTVPrototypeImportModel(
                configuration: configuration,
                serverProviderResolver: { $0 == context.accountID ? context : nil }
            )
            let model = LiveTVPrototypeModel(channels: [])
            await imports.reload(into: model)
            XCTAssertEqual(imports.catalogPhase, .loaded)
            XCTAssertNil(imports.serverSources.first?.failure)
            XCTAssertEqual(model.channels.count, 2_080)
            XCTAssertEqual(model.visibleChannels.count, 2_080)
            XCTAssertEqual(imports.serverChannelReferences.count, 2_080)
            XCTAssertTrue(model.channels.allSatisfy { $0.source == .iptv && $0.streamURL == nil })
            XCTAssertEqual(imports.serverSources.first?.availability?.supportsGuide, false)
            XCTAssertTrue(imports.serverGuideWindows.isEmpty)
            XCTAssertTrue(model.channels.allSatisfy { imports.gapState(for: $0) == .disabled })
            let channel = try XCTUnwrap(model.channels.first { $0.name == "Channel 0" })
            let reference = try XCTUnwrap(imports.serverChannelReferences[channel.id])
            let lease = try await provider.openLiveTVChannel(id: reference.channelID)
            if case .authenticatedHTTP(let locator) = lease.playbackSource {
                XCTAssertEqual(locator.accountID, context.accountID)
                XCTAssertEqual(locator.itemID, reference.channelID)
                XCTAssertEqual(locator.deliveryMode, .hls)
            } else {
                XCTFail("IPTV account channels must use their authenticated provider")
            }
            await lease.close()
            try imports.setServerProviderResolver({ _ in nil }, into: model)
            XCTAssertTrue(model.channels.isEmpty, "Revoking the active profile must still remove its channels")
            XCTAssertEqual(imports.serverSources.first?.failure, .accountUnavailable)
        } catch {
            await provider.teardown()
            throw error
        }
        await provider.teardown()
    }
}
