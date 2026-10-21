@testable import AppRuntime
import CoreModels
import CoreSecureStore
import CoreUI
import FeatureAuthCore
import FeatureLiveTV
import FeatureLiveTVCore
import Observation
import SwiftUI
import UIKit
import XCTest
#if os(iOS)
import Vision
#endif

@MainActor
final class LiveTVSourcesRuntimeHostedTests: XCTestCase {
    #if os(iOS)
    func testSourceErrorAppearsBesideItsSourceWithoutAGenericFooter() async throws {
        for width in [CGFloat(390), 834] {
            for (name, palette) in [("dark", ThemePalette.dark), ("black", .pureBlack), ("light", .light)] {
                let fixture = try Fixture(hasIPTV: true)
                defer { fixture.close() }
                var configuration = try fixture.store.load()
                configuration.servers.append(.init(
                    id: "other", name: "Other server", accountID: "other", isEnabled: false
                ))
                try fixture.store.save(configuration)
                fixture.window.frame = CGRect(x: 0, y: 0, width: width, height: 1024)
                fixture.provider.failure = .unauthorized
                fixture.show(palette: palette)
                try await waitUntil { fixture.runtime.catalog.imports.serverSources.first?.failure == .permissionDenied }
                try await Task.sleep(for: .milliseconds(300))
                let capture = try recognizedLines(fixture.window, name: "sources-specific-error-\(Int(width))-\(name)")
                let lines = capture.lines
                let source = try XCTUnwrap(lines.first { $0.text == "IPTV" })
                let error = try XCTUnwrap(lines.first { $0.text.lowercased().contains("permission") })
                let firstErrorLine = try XCTUnwrap(lines.first { $0.text.contains("This server account") })
                let status = try XCTUnwrap(lines.first { $0.text == "Refresh failed" })
                let retry = try XCTUnwrap(lines.first { $0.text == "Retry" })
                let other = try XCTUnwrap(lines.first { $0.text == "Other server" })
                let setup = try XCTUnwrap(lines.first { $0.text == "ADD A SOURCE" })
                XCTAssertLessThan(error.frame.maxY, source.frame.minY)
                XCTAssertGreaterThan(error.frame.minY, setup.frame.maxY)
                XCTAssertFalse(try hasDivider(in: capture.image, between: status.frame, and: firstErrorLine.frame))
                XCTAssertTrue(try hasDivider(in: capture.image, between: retry.frame, and: other.frame))
                XCTAssertFalse(lines.contains { $0.text.lowercased().contains("channel and guide data") })
                XCTAssertNil(fixture.runtime.catalog.issue)
            }
        }
    }

    func testPageWideAccessErrorAppearsBeforeSources() async throws {
        let fixture = try Fixture(hasIPTV: true)
        defer { fixture.close() }
        fixture.state.authorized = false
        fixture.show()
        try await waitUntil { fixture.runtime.catalog.issue == .authorization }
        try await Task.sleep(for: .milliseconds(300))
        let lines = try recognizedLines(fixture.window, name: "sources-page-error").lines
        let error = try XCTUnwrap(lines.first { $0.text.lowercased().contains("profile access") })
        let sources = try XCTUnwrap(lines.first { $0.text == "YOUR SOURCES" })
        XCTAssertGreaterThan(error.frame.minY, sources.frame.maxY)
    }

    private func recognizedLines(
        _ window: UIWindow, name: String
    ) throws -> (image: UIImage, lines: [(text: String, frame: CGRect)]) {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.customWords = ["IPTV"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        let lines: [(text: String, frame: CGRect)] = (request.results ?? []).compactMap {
            guard let text = $0.topCandidates(1).first?.string else { return nil }
            return (text, $0.boundingBox)
        }
        return (image, lines)
    }

    private func hasDivider(in image: UIImage, between upper: CGRect, and lower: CGRect) throws -> Bool {
        let cgImage = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cgImage.bitsPerPixel, 32)
        XCTAssertEqual(cgImage.bitsPerComponent, 8)
        let data = try XCTUnwrap(cgImage.dataProvider?.data)
        let pixels = try XCTUnwrap(CFDataGetBytePtr(data))
        let top = max(2, Int((1 - upper.minY) * CGFloat(cgImage.height)) + 2)
        let bottom = min(cgImage.height - 3, Int((1 - lower.maxY) * CGFloat(cgImage.height)) - 2)
        guard top < bottom else { return false }
        let columns = [0.2, 0.5, 0.8].map { Int(CGFloat(cgImage.width) * $0) }
        return (top..<bottom).contains { y in
            columns.allSatisfy { x in
                let center = y * cgImage.bytesPerRow + x * 4
                return [-2, 2].allSatisfy { offset in
                    let neighbor = center + offset * cgImage.bytesPerRow
                    return (0..<3).reduce(0) {
                        $0 + abs(Int(pixels[center + $1]) - Int(pixels[neighbor + $1]))
                    } > 12
                }
            }
        }
    }
    #endif

    func testSyncedIdentityMarkerDoesNotHideLoadedIPTVSources() async throws {
        let fixture = try Fixture(hasIPTV: true)
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.runtime.catalog.catalog.channels.count == 1 }
        fixture.profiles.noteIdentityQuestions(
            for: ["iptv"], forProfile: fixture.profileID, knownNonPlexAccountIDs: []
        )

        try await waitUntil {
            fixture.runtime.isCurrent && fixture.runtime.catalog.catalog.channels.count == 1
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(fixture.profiles.activeProfile.pendingIdentityAccountIDs, ["iptv"])
        XCTAssertFalse(fixture.accounts.activeProfileAwaitsIdentity)
        XCTAssertTrue(fixture.runtime.isCurrent)
        XCTAssertEqual(fixture.runtime.catalog.catalog.channels.count, 1)
        XCTAssertNil(fixture.runtime.catalog.issue)
    }

    func testSourceUpdateDuringIPTVRestoreDoesNotLeaveProfileAccessFailure() async throws {
        let fixture = try Fixture(hasIPTV: true, pausesCatalog: true)
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.provider.isWaiting }
        let runtime = try XCTUnwrap(fixture.state.runtime)
        let identity = runtime.authorityID
        var configuration = try runtime.store.load()
        configuration.servers[0].name = "Updated IPTV"
        try runtime.store.save(configuration)
        fixture.provider.release()

        try await waitUntil {
            runtime.isCurrent && runtime.catalog.catalog.channels.map(\.name) == ["IPTV channel"]
        }
        XCTAssertEqual(runtime.authorityID, identity, "Neither profile nor account access changed.")
        XCTAssertNil(runtime.catalog.issue)
        XCTAssertEqual(runtime.catalog.imports.configuration.servers, configuration.servers)
        XCTAssertEqual(try runtime.store.load().servers, configuration.servers)
    }

    func testLoadedIPTVTracksSourceChangesWithoutReopeningSources() async throws {
        let fixture = try Fixture(hasIPTV: true)
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.runtime.catalog.catalog.channels.count == 1 }
        let runtime = fixture.runtime
        let identity = runtime.authorityID
        var configuration = try runtime.store.load()
        configuration.servers[0].isEnabled = false
        try runtime.store.save(configuration)
        try await waitUntil { runtime.isCurrent && runtime.catalog.catalog.channels.isEmpty }

        configuration.servers[0].isEnabled = true
        try runtime.store.save(configuration)
        try await waitUntil { runtime.isCurrent && runtime.catalog.catalog.channels.count == 1 }
        configuration.servers[0].name = "Synced IPTV"
        try fixture.store.save(configuration)
        NotificationCenter.default.post(name: .plozzLiveTVPortableStateDidApply, object: fixture.profileID)
        try await waitUntil {
            runtime.isCurrent && runtime.catalog.imports.configuration.servers == configuration.servers
        }
        XCTAssertEqual(runtime.authorityID, identity)
        XCTAssertEqual(runtime.catalog.catalog.channels.count, 1)
        XCTAssertNil(runtime.catalog.issue)
        XCTAssertEqual(try runtime.store.load().servers, configuration.servers)
    }

    func testSourcesStayAdmittedWhenBackgroundSyncSavesItsCheckpoint() async throws {
        let fixture = try Fixture(hasIPTV: true)
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.state.runtime?.isCurrent == true }
        let runtime = try XCTUnwrap(fixture.state.runtime)
        try await waitUntil { runtime.catalog.catalog.channels.count == 1 }
        let reads = fixture.provider.catalogReads
        var configuration = try fixture.store.load()
        configuration.syncCheckpoint = .init(profileID: fixture.profileID, accountEpoch: "sync-generation")
        try fixture.store.save(configuration)
        NotificationCenter.default.post(name: .plozzLiveTVPortableStateDidChange, object: fixture.profileID)
        NotificationCenter.default.post(name: .plozzLiveTVPortableStateDidApply, object: fixture.profileID)
        NotificationCenter.default.post(name: .plozzLiveTVPortableStateDidChange, object: "another-profile")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(runtime.isCurrent, "No Retry or navigation should be needed after a sync checkpoint.")
        XCTAssertNil(runtime.catalog.issue)
        XCTAssertEqual(runtime.catalog.catalog.channels.count, 1)
        XCTAssertEqual(fixture.provider.catalogReads, reads, "Bookkeeping must not restart the catalogue.")
    }

    func testSourceUpdatesCannotReadmitLockedProfileOrPublishLateChannels() async throws {
        let fixture = try Fixture(hasIPTV: true, pausesCatalog: true)
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.provider.isWaiting }
        let runtime = fixture.runtime
        fixture.state.authorized = false
        var configuration = try runtime.store.load()
        configuration.servers[0].name = "Updated IPTV"
        try runtime.store.save(configuration)
        fixture.provider.release()
        try await waitUntil { runtime.authorityID == nil && runtime.catalog.issue == .authorization }
        XCTAssertFalse(runtime.isCurrent)
        XCTAssertTrue(runtime.catalog.catalog.channels.isEmpty)

        fixture.state.authorized = true
        try await waitUntil { runtime.isCurrent && runtime.catalog.catalog.channels.count == 1 }
        XCTAssertNil(runtime.catalog.issue)
    }

    func testBackgroundSourceUpdateWaitsForPresentationToResume() async throws {
        let fixture = try Fixture(hasIPTV: true)
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.runtime.catalog.catalog.channels.count == 1 }
        fixture.state.phase = .background
        try await waitUntil { !fixture.runtime.isCurrent }
        let reads = fixture.provider.catalogReads
        var configuration = try fixture.runtime.store.load()
        configuration.servers[0].name = "Updated IPTV"
        try fixture.runtime.store.save(configuration)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(fixture.runtime.catalog.catalog.channels.isEmpty)
        XCTAssertEqual(fixture.provider.catalogReads, reads)

        fixture.state.phase = .active
        try await waitUntil { fixture.runtime.isCurrent && fixture.runtime.catalog.catalog.channels.count == 1 }
        XCTAssertEqual(fixture.runtime.catalog.imports.configuration.servers, configuration.servers)
        XCTAssertNil(fixture.runtime.catalog.issue)
    }

    func testSourcesStayAdmittedWhileOpeningAndClosingAnEditor() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.state.runtime?.isCurrent == true }
        let runtime = try XCTUnwrap(fixture.state.runtime)
        fixture.state.path = [1]
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(runtime.isCurrent)
        fixture.state.path = []
        try await waitUntil { runtime.isCurrent }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(runtime.isCurrent)
        XCTAssertNil(runtime.catalog.issue)
    }

    func testSourcesReadmitAutomaticallyAfterPresentationAndAuthorityChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.state.runtime?.isCurrent == true }
        let runtime = try XCTUnwrap(fixture.state.runtime)
        for index in 0..<3 {
            fixture.state.presented = false
            try await waitUntil { !runtime.isCurrent }
            fixture.state.presented = true
            try await waitUntil { runtime.isCurrent }
            fixture.profiles.setActiveAccountIDs(["generation-\(index)"], for: fixture.profileID)
            try await waitUntil { runtime.isCurrent }
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(runtime.isCurrent)
            XCTAssertNil(runtime.catalog.issue)
            XCTAssertTrue(runtime === fixture.state.runtime)
        }
        fixture.state.phase = .inactive
        try await waitUntil { !runtime.isCurrent }
        fixture.state.phase = .active
        try await waitUntil { runtime.isCurrent }
        XCTAssertNil(runtime.catalog.issue)
    }

    func testSourcesRecoverAutomaticallyAfterProfileAuthorizationReturns() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.state.authorized = false
        fixture.show()
        try await waitUntil { fixture.state.runtime?.catalog.issue == .authorization }
        let runtime = try XCTUnwrap(fixture.state.runtime)
        fixture.state.authorized = true
        try await waitUntil { runtime.isCurrent }
        XCTAssertNil(runtime.catalog.issue)
        fixture.state.authorized = false
        try await waitUntil { !runtime.isCurrent }
        XCTAssertTrue(runtime.catalog.catalog.channels.isEmpty)
    }

    private func waitUntil(
        file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Sources must settle without pressing Retry or reopening.", file: file, line: line)
    }

    @MainActor @Observable
    final class State {
        var presented = true
        var authorized = true
        var phase: ScenePhase = .active
        var path: [Int] = []
        @ObservationIgnored var runtime: LiveTVSourcesRuntime?
    }

    private struct Page: View {
        let state: State
        let profiles: ProfilesModel
        let accounts: AccountsProvidersModel
        let cache: LiveTVIndexedCache
        let profileID: String
        let runtime: LiveTVSourcesRuntime

        var body: some View {
            NavigationStack(path: Binding(get: { state.path }, set: { state.path = $0 })) {
                LiveTVSourcesRuntimeHost(
                    profileID: profileID, namespace: profileID,
                    profiles: profiles, accounts: accounts, cache: cache,
                    isPresented: state.presented,
                    isProfileAuthorized: { state.authorized },
                    content: capture, runtime: runtime
                )
                .navigationDestination(for: Int.self) { _ in Text("Source editor") }
            }
            .environment(profiles)
            .environment(\.scenePhase, state.phase)
        }

        private func capture(_ runtime: LiveTVSourcesRuntime) -> some View {
            state.runtime = runtime
            return LiveTVSourcesView(store: runtime.store, catalog: runtime.catalog)
        }
    }

    @MainActor private final class Fixture {
        let domain = "LiveTVSourcesRuntimeHostedTests." + UUID().uuidString
        let defaults: UserDefaults
        let profiles: ProfilesModel
        let accounts: AccountsProvidersModel
        let profileID: String
        let directory: URL
        let cache: LiveTVIndexedCache
        let state = State()
        let runtime: LiveTVSourcesRuntime
        let store: LiveTVSourcesStore
        let provider: CachedIPTVProvider
        let window: UIWindow
        weak var previous: UIWindow?

        init(hasIPTV: Bool = false, pausesCatalog: Bool = false) throws {
            provider = CachedIPTVProvider(paused: pausesCatalog)
            defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            profiles = ProfilesModel(store: ProfileStore(defaults: defaults))
            profileID = profiles.add(name: "Sources fixture").id
            profiles.select(profileID)
            let accountStore = AccountStore(secureStore: InMemorySecureStore())
            if hasIPTV {
                try accountStore.add(Account(
                    id: "iptv",
                    server: MediaServer(
                        id: "server", name: "IPTV",
                        baseURL: URL(string: "https://iptv.example")!, provider: .iptv
                    ),
                    userID: "viewer", userName: "Viewer", deviceID: "device"
                ), token: "fixture")
            }
            accounts = AccountsProvidersModel(
                accountStore: accountStore,
                registry: ProviderRegistry(), profilesModel: profiles
            )
            accounts.reloadAccounts()
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
            cache = LiveTVIndexedCache(
                url: directory.appendingPathComponent("catalog.sqlite"),
                namespace: profileID, authorizationScope: "iptv-profile-v1",
                secureStore: InMemorySecureStore()
            )
            store = LiveTVSourcesStore(secureStore: InMemorySecureStore(), namespace: profileID)
            if hasIPTV {
                try store.save(.init(servers: [
                    .init(id: "source", name: "IPTV", accountID: "iptv")
                ]))
            }
            let state = state
            let profiles = profiles
            let accounts = accounts
            let provider = provider
            let approvals = LiveTVSourceApprovalStore(
                defaults: defaults, profileID: profileID, namespace: profileID
            )
            runtime = LiveTVSourcesRuntime(
                profileID: profileID,
                store: LiveTVApprovalAwareSourcesStore(underlying: store, approvals: approvals),
                approvals: approvals,
                cache: cache, loader: EmptyLoader(),
                preferencesStore: LiveTVPreferencesStore(defaults: defaults, namespace: profileID),
                scanCoordinator: LiveTVChannelScanCoordinator(
                    store: LiveTVChannelHealthStore(defaults: defaults, namespace: profileID)
                ),
                context: {
                    state.authorized && !accounts.activeProfileAwaitsIdentity
                        ? LiveTVSourceApprovalContext(profiles: profiles) : nil
                },
                accountAuthorizationID: { accounts.liveTVAuthorizationID },
                serverProviderResolver: { id in
                    guard hasIPTV, id == "iptv" else { return nil }
                    return .init(accountID: id, authorizationID: "fixture", kind: .iptv, provider: provider)
                }
            )
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            previous = scene.windows.first(where: \.isKeyWindow)
            window = UIWindow(windowScene: scene)
            #if os(iOS)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            #else
            window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            #endif
        }

        func show(palette: ThemePalette = .dark) {
            window.overrideUserInterfaceStyle = palette.isLight ? .light : .dark
            window.rootViewController = UIHostingController(rootView: Page(
                state: state, profiles: profiles, accounts: accounts, cache: cache,
                profileID: profileID, runtime: runtime
            )
            .environment(\.themePalette, palette)
            .environment(\.colorScheme, palette.isLight ? .light : .dark))
            window.makeKeyAndVisible()
        }

        func close() {
            provider.release()
            runtime.invalidate()
            window.isHidden = true
            window.rootViewController = nil
            state.runtime = nil
            previous?.makeKeyAndVisible()
            defaults.removePersistentDomain(forName: domain)
            if FileManager.default.fileExists(atPath: directory.path) {
                do { try FileManager.default.removeItem(at: directory) }
                catch { XCTFail("Could not remove this fixture's cache: \(error)") }
            }
        }
    }

    @MainActor private final class CachedIPTVProvider: ServerLiveTVProviding {
        private var paused: Bool
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var catalogReads = 0
        var failure: AppError?
        var isWaiting: Bool { !waiters.isEmpty }

        init(paused: Bool) { self.paused = paused }

        func release() {
            paused = false
            let pending = waiters
            waiters = []
            pending.forEach { $0.resume() }
        }

        func cachedLiveTVCatalog() async throws -> ServerLiveTVCatalogSnapshot? {
            catalogReads += 1
            if paused {
                await withCheckedContinuation { waiters.append($0) }
            }
            try Task.checkCancellation()
            if let failure { throw failure }
            return .init(channels: [.init(id: "channel", name: "IPTV channel")], supportsGuide: false)
        }

        func liveTVAvailability() async throws -> ServerLiveTVAvailability {
            XCTFail("Restoring Sources must use the existing IPTV catalogue.")
            throw AppError.serverUnreachable
        }

        func liveTVChannels() async throws -> [ServerLiveTVChannel] {
            XCTFail("Restoring Sources must not refresh channels.")
            return []
        }

        func liveTVGuide(channelIDs: [String], from: Date, to: Date) async throws -> [ServerLiveTVProgramme] {
            XCTFail("Restoring Sources must not refresh the guide.")
            return []
        }

        func openLiveTVChannel(id: String) async throws -> any LiveTVStreamLease {
            throw ServerLiveTVError.tunerUnavailable
        }
    }

    private struct EmptyLoader: LiveTVSourceLoading {
        func loadPlaylist(from url: URL) async throws -> LiveTVPlaylistImport {
            XCTFail("Presentation recovery must use the cache, not refetch playlists.")
            throw LiveTVSourceImportError.downloadFailed
        }

        func loadGuide(
            from url: URL, channels: [LiveTVPrototypeChannel], now: Date
        ) async throws -> LiveTVGuideImport {
            XCTFail("Presentation recovery must not refetch guides.")
            throw LiveTVSourceImportError.downloadFailed
        }
    }
}
