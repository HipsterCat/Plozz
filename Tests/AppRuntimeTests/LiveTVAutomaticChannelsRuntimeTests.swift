#if DEBUG
import CoreModels
import CoreSecureStore
import FeatureAuthCore
import FeatureLiveTVCore
import XCTest
@testable import AppRuntime
@testable import FeatureSyncCloud
@testable import TestSupportPerformance

@MainActor
final class LiveTVAutomaticChannelsRuntimeTests: XCTestCase {
    func testPerformanceConfigurationMatrix() async throws {
        try PerformanceProbe.requireEnabled()
        for providers in [1, 4] {
            for channels in [false, true] {
                for liveTV in [false, true] {
                    for cloud in [false, true] {
                        try await measureConfiguration(providers: providers, channels: channels, liveTV: liveTV, cloud: cloud)
                    }
                }
            }
        }
    }

    private func measureConfiguration(providers: Int, channels: Bool, liveTV: Bool, cloud: Bool) async throws {
        let extras = (0..<(providers - 1)).map { index in
            AutomaticRuntimeProvider(kind: index.isMultiple(of: 2) ? .plex : .jellyfin,
                                     serverID: "extra-\(index)", itemCount: 500)
        }
        let fixture = try Fixture(extraProviders: extras, itemCount: 500)
        defer { fixture.close() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: folder) }
            catch { XCTFail("Could not remove owned matrix fixture: \(error)") }
        }
        SyncSetupFeatureFlag(defaults: fixture.defaults).isEnabled = cloud
        try fixture.settings.setEnabled(channels)
        let runtime = fixture.runtime()
        await runtime.refresh(accounts: fixture.accounts)
        XCTAssertNil(runtime.issue)
        XCTAssertNil(runtime.automaticChannelsIssue)
        XCTAssertEqual(runtime.automaticChannelsEnabled, channels)
        XCTAssertEqual(fixture.accounts.activeAccountIDs.count, providers)
        if channels { XCTAssertGreaterThan(runtime.automaticChannelCount, 0) }

        let sources = LiveTVSourcesStore(secureStore: fixture.secrets, namespace: fixture.suite)
        let cache = LiveTVIndexedCache(
            url: folder.appendingPathComponent("guide.sqlite"), namespace: fixture.suite,
            authorizationScope: "performance", secureStore: fixture.secrets,
            importedFilesURL: folder.appendingPathComponent("imports")
        )
        if liveTV {
            try sources.save(.init(playlists: [
                .init(id: "source", name: "Fixture", playlistURL: URL(string: "https://fixture.invalid/list.m3u")!)
            ]))
            let playlist = try LiveTVPlaylistParser().parse("#EXTM3U\n" + (0..<1_000).map {
                "#EXTINF:-1 tvg-id=\"\($0)\",Channel \($0)\nhttps://fixture.invalid/live/\($0).m3u8\n"
            }.joined())
            let imported = try await cache.reconcile(playlist, sourceID: "source")
            XCTAssertEqual(imported.playlist.channels.count, 1_000)
        }
        let absentCatalogRevision = UUID()
        var identityCaptures = 0
        let bridge = LiveTVPortableSyncBridge(
            profiles: fixture.profiles, directory: folder, defaults: fixture.defaults,
            followsMainSync: true, sourceStore: { _ in sources },
            definitions: { _ in fixture.definitions }, snapshots: fixture.snapshots,
            guideCache: { _ in liveTV ? cache : nil },
            captureIdentityHints: { _ in
                identityCaptures += 1
                guard liveTV else { return nil }
                return try await cache.portableSyncIdentityHints(
                    configuration: sources.load(), channelIDs: []
                )
            },
            captureIdentityRevision: { _ in
                guard liveTV else { return absentCatalogRevision }
                return try await cache.portableSyncRevision(configuration: sources.load())
            }
        )
        bridge.refreshParticipation()
        let sourceBridge = LiveTVSourceSyncBridge(
            profiles: fixture.profiles, defaults: fixture.defaults, store: { _ in sources }, cache: { _ in cache }
        )
        var records: [String: Data] = [:]
        var sourceRecords: [String: Data] = [:]
        var ledger = SyncLedger()
        let persistence = CloudSyncPersistenceState()
        var writes = 0
        var sequence: UInt64 = 0
        let id = "runtime-p\(providers)-c\(channels ? 1 : 0)-l\(liveTV ? 1 : 0)-s\(cloud ? 1 : 0)"
        try await PerformanceProbe.measure(self, scenario: id) {
            var requestsBefore = 0
            for provider in [fixture.provider] + extras { requestsBefore += await provider.requests.count }
            let writesBefore = writes
            let capturesBefore = identityCaptures
            for _ in 0..<10 {
                for accountID in fixture.accounts.activeAccountIDs {
                    XCTAssertNotNil(fixture.accounts.provider(forAccountID: accountID))
                }
                await runtime.refresh(accounts: fixture.accounts)
                if liveTV { XCTAssertEqual(try sources.load().playlists.count, 1) }
                if cloud {
                    records = await bridge.capture(fallback: records)
                    XCTAssertNotEqual(bridge.statuses[fixture.profiles.activeProfileID], .unavailable)
                    sequence += 1
                    sourceRecords = try await sourceBridge.capture(.init(
                        sequence: sequence, authority: LiveTVPortableSyncPreferenceStore.storageEpoch(defaults: fixture.defaults),
                        records: sourceRecords,
                        localCaptureDigests: ledger.entries.compactMapValues(\.localCaptureDigest)
                    ))
                    _ = ledger.reconcileLocal(desired: records.merging(sourceRecords) { _, new in new }, now: 1)
                    _ = persistence.writeIfChanged(ledger: ledger, engineRevision: nil) { writes += 1 }
                }
            }
            var requestsAfter = 0
            for provider in [fixture.provider] + extras { requestsAfter += await provider.requests.count }
            XCTAssertEqual(requestsAfter, requestsBefore, "Settled runtime refresh must not rediscover provider catalogues.")
            XCTAssertLessThanOrEqual(writes - writesBefore, 1)
            if writesBefore > 0 {
                XCTAssertEqual(writes, writesBefore, "After warmup, unchanged combined state must not persist again.")
                XCTAssertEqual(identityCaptures, capturesBefore, "Warm captures must reuse the production unchanged-state path.")
            }
            if cloud {
                XCTAssertGreaterThan(identityCaptures, 0, "The initial portable export must actually run.")
            }
            return ["providers": providers, "automaticChannels": channels ? 1 : 0,
                    "liveTV": liveTV ? 1 : 0, "cloudSync": cloud ? 1 : 0, "refreshes": 10,
                    "providerRequests": requestsAfter - requestsBefore,
                    "portableRecords": records.count + sourceRecords.count,
                    "persistenceCalls": writes - writesBefore]
        }
        if cloud && liveTV {
            let capturesBefore = identityCaptures
            var updated = try sources.load()
            updated.playlists[0].name = "Changed fixture"
            try sources.save(updated)
            _ = await bridge.capture(fallback: records)
            XCTAssertGreaterThan(identityCaptures, capturesBefore, "A real source edit must invalidate the capture cache.")
            XCTAssertEqual(bridge.statuses[fixture.profiles.activeProfileID], .ready)
            sequence += 1
            let changedSources = try await sourceBridge.capture(.init(
                sequence: sequence, authority: LiveTVPortableSyncPreferenceStore.storageEpoch(defaults: fixture.defaults),
                records: sourceRecords,
                localCaptureDigests: ledger.entries.compactMapValues(\.localCaptureDigest)
            ))
            XCTAssertNotEqual(changedSources, sourceRecords, "An acknowledged source must still capture later local edits.")
        }
    }

    func testOptInIsDurableScopedAndRejectsCorruptValues() throws {
        let secrets = InMemorySecureStore()
        let first = LiveTVAutomaticChannelsStore(secureStore: secrets, namespace: "first")
        let other = LiveTVAutomaticChannelsStore(secureStore: secrets, namespace: "other")
        XCTAssertFalse(try first.isEnabled())
        try first.setEnabled(true)
        XCTAssertTrue(try LiveTVAutomaticChannelsStore(secureStore: secrets, namespace: "first").isEnabled())
        XCTAssertFalse(try other.isEnabled())
        try secrets.setString(
            "invalid", for: SettingsKey.scoped("com.plozz.liveTV.automaticChannels", namespace: "first"))
        XCTAssertThrowsError(try first.isEnabled())
    }

    func testWholeLibraryNeedsOnlyOneOptInAndSurvivesRelaunch() async throws {
        for kind in [ProviderKind.jellyfin, .plex, .emby] {
            let fixture = try Fixture(kind: kind)
            defer { fixture.close() }
            let runtime = fixture.runtime()
            await runtime.refresh(accounts: fixture.accounts)
            XCTAssertNil(runtime.issue)
            XCTAssertFalse(runtime.automaticChannelsEnabled)
            let initialRequests = await fixture.provider.requests.count
            XCTAssertEqual(initialRequests, 0)

            await runtime.setAutomaticChannelsEnabled(true)
            await runtime.refresh(accounts: fixture.accounts)

            XCTAssertTrue(runtime.automaticChannelsEnabled)
            XCTAssertNil(runtime.automaticChannelsIssue)
            XCTAssertGreaterThan(runtime.automaticChannelCount, 0)
            XCTAssertNotNil(runtime.automaticPreparation.startedAt)
            XCTAssertEqual(runtime.automaticPreparation.update.stage, .savingGuides)
            XCTAssertEqual(runtime.automaticPreparation.update.scannedItemCount, 12)
            XCTAssertTrue(runtime.service.definitions.allSatisfy(\.isAutomatic))
            let ids = runtime.service.definitions.map(\.id)
            let revisions = runtime.service.definitions.map(\.revisions)
            let channel = try XCTUnwrap(runtime.service.channels.first)
            let programmes = try runtime.service.programmes(
                channelIDs: [channel.id], from: Date(), to: Date().addingTimeInterval(3_600))
            XCTAssertFalse(programmes.isEmpty)

            let restored = fixture.runtime()
            await restored.refresh(accounts: fixture.accounts)
            XCTAssertTrue(restored.automaticChannelsEnabled)
            XCTAssertNil(restored.automaticChannelsIssue)
            XCTAssertEqual(restored.service.definitions.map(\.id), ids)
            XCTAssertEqual(restored.service.definitions.map(\.revisions), revisions)
        }
    }

    func testDisablingStopsDiscoveryAndRevokesPlaybackWithoutDeletingChannels() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let runtime = fixture.runtime()
        await runtime.refresh(accounts: fixture.accounts)
        await runtime.setAutomaticChannelsEnabled(true)
        await runtime.refresh(accounts: fixture.accounts)
        let channel = try XCTUnwrap(runtime.service.channels.first)
        let held = try runtime.service.playbackContext(catalogID: channel.id)
        let ids = runtime.service.definitions.map(\.id)
        let queries = await fixture.provider.requests.count

        await runtime.setAutomaticChannelsEnabled(false)
        XCTAssertNil(held.authorizationID)
        await runtime.refresh(accounts: fixture.accounts)
        XCTAssertFalse(runtime.automaticChannelsEnabled)
        XCTAssertEqual(runtime.automaticChannelCount, 0)
        XCTAssertEqual(runtime.service.definitions.map(\.id), ids)
        XCTAssertTrue(runtime.service.channels.isEmpty)
        let queriesWhileDisabled = await fixture.provider.requests.count
        XCTAssertEqual(queriesWhileDisabled, queries)

        await runtime.setAutomaticChannelsEnabled(true)
        await runtime.refresh(accounts: fixture.accounts)
        XCTAssertNil(runtime.automaticChannelsIssue)
        XCTAssertEqual(runtime.service.definitions.map(\.id), ids)
        XCTAssertGreaterThan(runtime.automaticChannelCount, 0)
    }

    func testInitialServerDiscoveryCanBeCancelledWithoutWaitingForItsResponse() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try fixture.settings.setEnabled(true)
        let requested = expectation(description: "Library request started")
        let gate = DiscoveryGate()
        await fixture.provider.requests.beforeNextLibraries {
            requested.fulfill()
            await gate.wait()
        }
        let runtime = fixture.runtime()
        let refresh = Task { await runtime.refresh(accounts: fixture.accounts) }
        await fulfillment(of: [requested], timeout: 2)
        XCTAssertTrue(runtime.isPreparingAutomaticChannels)
        XCTAssertEqual(runtime.automaticPreparation.update.serverName, "Library")

        await runtime.setAutomaticChannelsEnabled(false)
        XCTAssertFalse(runtime.isPreparingAutomaticChannels)
        XCTAssertFalse(runtime.automaticChannelsEnabled)
        XCTAssertFalse(try fixture.settings.isEnabled())

        await gate.resume()
        await refresh.value
        await runtime.refresh(accounts: fixture.accounts)
        XCTAssertFalse(runtime.isPreparingAutomaticChannels)
        XCTAssertFalse(runtime.automaticChannelsEnabled)
        XCTAssertEqual(runtime.automaticPreparation.update.stage, .checkingServers)
        let requests = await fixture.provider.requests.count
        XCTAssertEqual(requests, 1, "Cancelled discovery must not restart or fetch items")
    }

    func testLeavingOneHostDoesNotRevokeTheOtherHostsRestoredChannels() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try fixture.settings.setEnabled(true)
        let requested = expectation(description: "Automatic preparation started after restore")
        let gate = DiscoveryGate()
        await fixture.provider.requests.beforeNextItems {
            requested.fulfill()
            await gate.wait()
        }
        let runtime = fixture.runtime()
        let sourcesHost = Task { await runtime.refresh(accounts: fixture.accounts) }
        await fulfillment(of: [requested], timeout: 2)
        XCTAssertNotNil(runtime.authorizationID)
        XCTAssertTrue(runtime.service.isLoaded)

        let joined = expectation(description: "Guide requested the same runtime")
        let guideHost = Task {
            joined.fulfill()
            await runtime.refresh(accounts: fixture.accounts)
        }
        await fulfillment(of: [joined], timeout: 2)
        sourcesHost.cancel()
        await gate.resume()
        await sourcesHost.value
        await guideHost.value

        XCTAssertNil(runtime.issue, "Leaving Sources is not a profile or server access change")
        XCTAssertNil(runtime.automaticChannelsIssue)
        XCTAssertNotNil(runtime.authorizationID)
        XCTAssertGreaterThan(runtime.automaticChannelCount, 0)
    }

    func testConcurrentHostsShareInitialDiscoveryEvenWhenOneLeaves() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try fixture.settings.setEnabled(true)
        let requested = expectation(description: "Initial discovery started")
        let gate = DiscoveryGate()
        await fixture.provider.requests.beforeNextLibraries {
            requested.fulfill()
            await gate.wait()
        }
        let runtime = fixture.runtime()
        let guideHost = Task { await runtime.refresh(accounts: fixture.accounts) }
        await fulfillment(of: [requested], timeout: 2)
        let joined = expectation(description: "Sources requested the same runtime")
        let sourcesHost = Task {
            joined.fulfill()
            await runtime.refresh(accounts: fixture.accounts)
        }
        await fulfillment(of: [joined], timeout: 2)
        let requestsBeforeRelease = await fixture.provider.requests.count
        sourcesHost.cancel()
        await gate.resume()
        await guideHost.value
        await sourcesHost.value

        XCTAssertEqual(requestsBeforeRelease, 1, "Hosts must not replace each other's in-flight discovery")
        XCTAssertNil(runtime.issue)
        XCTAssertNotNil(runtime.authorizationID)
        XCTAssertGreaterThan(runtime.automaticChannelCount, 0)
    }

    func testProfileChangeStillRejectsPreparationAfterItsHostLeaves() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try fixture.settings.setEnabled(true)
        let requested = expectation(description: "Preparation started")
        let gate = DiscoveryGate()
        await fixture.provider.requests.beforeNextItems {
            requested.fulfill()
            await gate.wait()
        }
        let runtime = fixture.runtime()
        let refresh = Task { await runtime.refresh(accounts: fixture.accounts) }
        await fulfillment(of: [requested], timeout: 2)
        XCTAssertNotNil(runtime.authorizationID)

        refresh.cancel()
        let other = fixture.profiles.add(name: "Other")
        fixture.profiles.select(other.id)
        XCTAssertNil(runtime.authorizationID)
        await gate.resume()
        await refresh.value

        XCTAssertNil(runtime.authorizationID)
        XCTAssertTrue(try fixture.definitions.load().isEmpty, "Retired profile work must not publish a lineup")
        XCTAssertFalse(runtime.isPreparingAutomaticChannels)
    }

    func testChangedCredentialsSupersedeRefreshWithoutLateAuthorityRevocation() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try fixture.settings.setEnabled(true)
        let requested = expectation(description: "Old credential preparation started")
        let gate = DiscoveryGate()
        await fixture.provider.requests.beforeNextItems {
            requested.fulfill()
            await gate.wait()
        }
        let runtime = fixture.runtime()
        let oldRefresh = Task { await runtime.refresh(accounts: fixture.accounts) }
        await fulfillment(of: [requested], timeout: 2)
        let oldAuthorization = runtime.authorizationID
        let revision = CredentialRevision()
        fixture.accounts.credentialRevision = { _ in revision }
        XCTAssertNil(runtime.authorizationID)

        await runtime.refresh(accounts: fixture.accounts)
        let currentAuthorization = runtime.authorizationID
        await gate.resume()
        await oldRefresh.value

        XCTAssertNil(runtime.issue)
        XCTAssertNotNil(currentAuthorization)
        XCTAssertNotEqual(currentAuthorization, oldAuthorization)
        XCTAssertEqual(runtime.authorizationID, currentAuthorization)
        XCTAssertGreaterThan(runtime.automaticChannelCount, 0)
    }

    func testEnabledDiscoveryFailureIsScopedAndRetryRecovers() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let runtime = fixture.runtime()
        await runtime.refresh(accounts: fixture.accounts)
        await fixture.provider.requests.setUnavailable(true)
        await runtime.setAutomaticChannelsEnabled(true)
        await runtime.refresh(accounts: fixture.accounts)
        XCTAssertEqual(runtime.automaticChannelsIssue, .sourceUnavailable)
        XCTAssertEqual(runtime.automaticUnavailableSources.map(\.serverName), ["Library"])
        XCTAssertEqual(runtime.automaticUnavailableSources.first?.reason, .unreachable)
        XCTAssertNil(runtime.issue, "Automatic lineup errors must not present IPTV as a broken library channel")
        XCTAssertNotNil(runtime.authorizationID)
        XCTAssertTrue(runtime.automaticChannelsEnabled, "A failed preparation must remain retryable")

        await fixture.provider.requests.setUnavailable(false)
        runtime.retry()
        await runtime.refresh(accounts: fixture.accounts)
        XCTAssertNil(runtime.automaticChannelsIssue)
        XCTAssertTrue(runtime.automaticUnavailableSources.isEmpty)
        XCTAssertGreaterThan(runtime.automaticChannelCount, 0)
    }

    func testTransientDiscoveryFailureRecoversAutomaticallyWithoutAnImmediateRetryLoop() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let runtime = fixture.runtime()
        await runtime.refresh(accounts: fixture.accounts)
        await fixture.provider.requests.setUnavailable(true)
        await runtime.setAutomaticChannelsEnabled(true)
        await runtime.refresh(accounts: fixture.accounts)
        XCTAssertTrue(runtime.needsAutomaticRecovery)
        XCTAssertEqual(runtime.automaticRefreshInterval, 60)
        let request = runtime.refreshRequest
        runtime.requestAutomaticRefresh()
        XCTAssertEqual(runtime.refreshRequest, request)

        await fixture.provider.requests.setUnavailable(false)
        runtime.requestAutomaticRefresh(at: Date().addingTimeInterval(61))
        XCTAssertEqual(runtime.refreshRequest, request + 1)
        await runtime.refresh(accounts: fixture.accounts)
        XCTAssertNil(runtime.automaticChannelsIssue)
        XCTAssertGreaterThan(runtime.automaticChannelCount, 0)
        XCTAssertFalse(runtime.needsAutomaticRecovery)
        XCTAssertEqual(runtime.automaticRefreshInterval, 900)
    }

    func testOneUnreachableSavedJellyfinDoesNotBlockTheWorkingJellyfinLineup() async throws {
        let offline = AutomaticRuntimeProvider(kind: .jellyfin)
        await offline.requests.setUnavailable(true)
        let fixture = try Fixture(secondary: offline)
        defer { fixture.close() }
        let runtime = fixture.runtime()
        await runtime.refresh(accounts: fixture.accounts)
        await runtime.setAutomaticChannelsEnabled(true)
        await runtime.refresh(accounts: fixture.accounts)

        XCTAssertNil(runtime.issue)
        XCTAssertNil(runtime.automaticChannelsIssue)
        XCTAssertGreaterThan(runtime.automaticChannelCount, 0)
        XCTAssertEqual(runtime.automaticUnavailableSources.map(\.accountID), ["offline"])
        XCTAssertEqual(runtime.automaticUnavailableSources.first?.reason, .unreachable)
        let state = try runtime.service.portableState()
        XCTAssertFalse(runtime.needsAutomaticRecovery, "A working partial lineup must not rescan every minute")
        XCTAssertTrue(state.snapshots.flatMap(\.items).allSatisfy { $0.library.accountID == "catalog" })
        let ids = runtime.service.definitions.map(\.id)

        await offline.requests.setUnavailable(false)
        runtime.retry()
        await runtime.refresh(accounts: fixture.accounts)
        XCTAssertTrue(runtime.automaticUnavailableSources.isEmpty)
        XCTAssertNil(runtime.automaticChannelsIssue)
        XCTAssertTrue(Set(ids).isSubset(of: runtime.service.definitions.map(\.id)))
        XCTAssertTrue(try runtime.service.portableState().snapshots.flatMap(\.items).contains {
            $0.library.accountID == "offline"
        })
    }

    func testUnchangedAutomaticRefreshPreservesHeldPlaybackAuthority() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let runtime = fixture.runtime()
        await runtime.refresh(accounts: fixture.accounts)
        await runtime.setAutomaticChannelsEnabled(true)
        await runtime.refresh(accounts: fixture.accounts)
        let channel = try XCTUnwrap(runtime.service.channels.first)
        let held = try runtime.service.playbackContext(catalogID: channel.id)
        let authorization = try XCTUnwrap(held.authorizationID)
        let runtimeAuthorization = runtime.authorizationID

        runtime.retry()
        await runtime.refresh(accounts: fixture.accounts)

        XCTAssertNil(runtime.automaticChannelsIssue)
        XCTAssertEqual(held.authorizationID, authorization)
        XCTAssertEqual(runtime.authorizationID, runtimeAuthorization)
    }

    func testChangedProfileCannotEnableAnotherProfilesLineup() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let runtime = fixture.runtime()
        await runtime.refresh(accounts: fixture.accounts)
        let other = fixture.profiles.add(name: "Other")
        fixture.profiles.select(other.id)

        await runtime.setAutomaticChannelsEnabled(true)

        XCTAssertEqual(runtime.automaticChannelsIssue, .authorizationChanged)
        XCTAssertFalse(try fixture.settings.isEnabled())
        let queries = await fixture.provider.requests.count
        XCTAssertEqual(queries, 0)
    }

    func testCorruptOptInDoesNotContactLibrariesOrHideItsFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try fixture.secrets.setString(
            "invalid", for: SettingsKey.scoped("com.plozz.liveTV.automaticChannels", namespace: fixture.suite))
        let runtime = fixture.runtime()
        await runtime.refresh(accounts: fixture.accounts)

        XCTAssertFalse(runtime.automaticChannelsEnabled)
        XCTAssertEqual(runtime.automaticChannelsIssue, .storageFailed)
        XCTAssertNil(runtime.issue)
        let queries = await fixture.provider.requests.count
        XCTAssertEqual(queries, 0)
    }

    func testOptInWriteFailureDoesNotStartDiscoveryOrShowEnabled() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let runtime = LiveTVLibraryRuntime(
            profileID: fixture.profiles.activeProfileID, profiles: fixture.profiles,
            definitionsStore: fixture.definitions, snapshotStore: fixture.snapshots,
            automaticSettingsStore: FailingAutomaticOptInStore())
        await runtime.refresh(accounts: fixture.accounts)
        await runtime.setAutomaticChannelsEnabled(true)

        XCTAssertFalse(runtime.automaticChannelsEnabled)
        XCTAssertEqual(runtime.automaticChannelsIssue, .storageFailed)
        let queries = await fixture.provider.requests.count
        XCTAssertEqual(queries, 0)
    }

    func testEmptyLibraryRemainsEnabledWithAnActionablePreparationFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let runtime = fixture.runtime()
        await fixture.provider.requests.setEmpty(true)
        await runtime.refresh(accounts: fixture.accounts)
        await runtime.setAutomaticChannelsEnabled(true)
        await runtime.refresh(accounts: fixture.accounts)

        XCTAssertTrue(runtime.automaticChannelsEnabled)
        XCTAssertEqual(runtime.automaticChannelsIssue, .emptyCatalog)
        XCTAssertNil(runtime.issue)
        XCTAssertEqual(runtime.automaticChannelCount, 0)
    }

    @MainActor
    private final class Fixture {
        let suite = "LiveTVAutomaticChannelsRuntimeTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let profileStore: ProfileStore
        let profiles: ProfilesModel
        let secrets = InMemorySecureStore()
        let provider: AutomaticRuntimeProvider
        let accounts: AccountsProvidersModel
        let definitions: LibraryChannelDefinitionStore
        let snapshots = LibraryChannelSnapshotStore(databaseURL: nil)
        let settings: LiveTVAutomaticChannelsStore

        init(kind: ProviderKind = .jellyfin, secondary: AutomaticRuntimeProvider? = nil,
             extraProviders: [AutomaticRuntimeProvider] = [], itemCount: Int = 12) throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            profileStore = ProfileStore(defaults: defaults)
            profiles = ProfilesModel(store: profileStore)
            provider = AutomaticRuntimeProvider(kind: kind, itemCount: itemCount)
            let accountStore = AccountStore(secureStore: secrets)
            try accountStore.add(Account(
                id: "catalog", server: provider.session.server, userID: "user",
                userName: "User", deviceID: accountStore.deviceID()), token: "fixture-token")
            if let secondary {
                try accountStore.add(Account(
                    id: "offline", server: secondary.session.server, userID: "offline-user",
                    userName: "Offline user", deviceID: accountStore.deviceID()), token: "fixture-token")
            }
            for (index, extra) in extraProviders.enumerated() {
                try accountStore.add(Account(
                    id: "extra-\(index)", server: extra.session.server, userID: "user-\(index)",
                    userName: "Fixture", deviceID: accountStore.deviceID()), token: "fixture-token")
            }
            let active = (secondary == nil ? ["catalog"] : ["catalog", "offline"])
                + extraProviders.indices.map { "extra-\($0)" }
            accountStore.setActiveAccountIDs(active)
            let registry = ProviderRegistry()
            let provider = provider
            let byID = Dictionary(uniqueKeysWithValues: extraProviders.enumerated().map { ("extra-\($0.offset)", $0.element) })
            for registeredKind in Set([kind] + extraProviders.map(\.kind)) {
                registry.register(registeredKind) { context in
                    byID[context.accountID] ?? (context.accountID == "offline" ? (secondary ?? provider) : provider)
                }
            }
            accounts = AccountsProvidersModel(
                accountStore: accountStore, registry: registry, profilesModel: profiles)
            accounts.tokenResolver = { accountStore.token(for: $0) }
            accounts.reloadAccounts()
            definitions = LibraryChannelDefinitionStore(secureStore: secrets, namespace: suite)
            settings = LiveTVAutomaticChannelsStore(secureStore: secrets, namespace: suite)
        }

        func runtime() -> LiveTVLibraryRuntime {
            LiveTVLibraryRuntime(
                profileID: profiles.activeProfileID, profiles: profiles, definitionsStore: definitions,
                snapshotStore: snapshots, automaticSettingsStore: settings)
        }

        func close() { defaults.removePersistentDomain(forName: suite) }
    }
}

private actor AutomaticRuntimeRequests {
    private(set) var count = 0
    private(set) var empty = false
    private var unavailable = false
    private var libraryHook: (@Sendable () async -> Void)?
    private var itemHook: (@Sendable () async -> Void)?
    func beforeNextLibraries(_ hook: @escaping @Sendable () async -> Void) { libraryHook = hook }
    func beforeNextItems(_ hook: @escaping @Sendable () async -> Void) { itemHook = hook }
    func librariesRequested() async {
        let hook = libraryHook
        libraryHook = nil
        await hook?()
    }
    func itemsRequested() async {
        let hook = itemHook
        itemHook = nil
        await hook?()
    }
    func setEmpty(_ value: Bool) { empty = value }
    func setUnavailable(_ value: Bool) { unavailable = value }
    func record() throws {
        count += 1
        if unavailable { throw AppError.serverUnreachable }
    }
}

private actor DiscoveryGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func resume() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private struct FailingAutomaticOptInStore: LiveTVAutomaticChannelsStoring {
    func isEnabled() throws -> Bool { false }
    func setEnabled(_ enabled: Bool) throws { throw LibraryChannelError.storageFailed }
}

private struct AutomaticRuntimeProvider: LibraryChannelCatalogProviding, LibraryChannelPlaybackProviding {
    let requests = AutomaticRuntimeRequests()
    let kind: ProviderKind
    var serverID = "fixture-server"
    var itemCount = 12
    var session: UserSession {
        UserSession(
            server: MediaServer(
                id: serverID, name: "Library", baseURL: URL(string: "https://example.invalid")!,
                provider: kind),
            userID: "user", userName: "User", deviceID: "device", accessToken: "fixture-token")
    }

    func libraries() async throws -> [MediaLibrary] {
        try await requests.record()
        await requests.librariesRequested()
        return [MediaLibrary(id: "movies", title: "Movies", kind: .movie)]
    }

    func libraryChannelItems(in libraryID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        try await requests.record()
        await requests.itemsRequested()
        let isEmpty = await requests.empty
        let items: [MediaItem] = kind == .movie && !isEmpty ? (0..<itemCount).map { index in
            var item = MediaItem(id: "movie-\(index)", title: "Movie \(index)", kind: .movie, runtime: 3_600)
            item.libraryID = libraryID
            item.productionYear = 1990 + index
            item.genres = ["Comedy"]
            item.officialRating = "PG"
            return item
        } : []
        return MediaPage(
            items: Array(items.dropFirst(page.startIndex).prefix(page.limit)),
            startIndex: page.startIndex, totalCount: items.count)
    }

    func libraryChannelPlayback(for item: LibraryChannelItem) async throws -> PlaybackRequest { throw AppError.notFound }
    func recordLibraryChannelCompletion(itemID: String) async throws {}
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        try await libraryChannelItems(in: containerID, kind: kind, page: page)
    }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
#endif
