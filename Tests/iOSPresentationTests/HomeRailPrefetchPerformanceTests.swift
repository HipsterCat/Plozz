#if os(iOS)
import CoreModels
import CoreNetworking
import PlozzCoreUI
import FeatureAuth
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import AppShelliOS

@MainActor
final class HomeRailPrefetchPerformanceTests: XCTestCase {
    func testPerformanceRepeatedRailUpdates() async throws {
        try PerformanceProbe.requireEnabled()
        let fixture = try await Fixture(prefetchesArtwork: true)
        defer { fixture.close() }
        try await PerformanceProbe.measure(self, scenario: "mobile-home-rail-prefetch") {
            let before = PlozziOSHomeMediaRail.artworkPrefetchSourceBuildCount
            for _ in 0..<24 { try await fixture.update() }
            XCTAssertEqual(fixture.state.presentedRevision, fixture.state.revision)
            XCTAssertEqual(fixture.state.items.count, 180)
            XCTAssertEqual(Set(fixture.state.items.compactMap(\.sourceAccountID)).count, 12)
            return [
                "rootUpdates": 24, "items": fixture.state.items.count, "accounts": 12,
                "seriesSourceBuilds": PlozziOSHomeMediaRail.artworkPrefetchSourceBuildCount - before
            ]
        }
    }

    func testDisabledPrefetchDoesNotBuildSeriesSources() async throws {
        let before = PlozziOSHomeMediaRail.artworkPrefetchSourceBuildCount
        let fixture = try await Fixture(prefetchesArtwork: false)
        defer { fixture.close() }
        for _ in 0..<4 { try await fixture.update() }
        XCTAssertEqual(PlozziOSHomeMediaRail.artworkPrefetchSourceBuildCount, before)
    }

    func testStableRailUpdatesReusePrefetchButArtworkAndPolicyChangesRestartIt() async throws {
        let fixture = try await Fixture(prefetchesArtwork: true)
        defer { fixture.close() }
        let before = PlozziOSHomeMediaRail.artworkPrefetchSourceBuildCount
        for _ in 0..<4 { try await fixture.update() }
        XCTAssertEqual(PlozziOSHomeMediaRail.artworkPrefetchSourceBuildCount, before)

        let changes: [() -> Void] = [
            { fixture.state.items[0].seriesID = "replacement-series" },
            { fixture.state.items[0].fallbackArtworkURL = fixture.alternateArtwork },
            { fixture.state.items[0].sourceAccountID = "replacement-account" },
            { fixture.app.settings.cardStyle.artwork = ArtworkSettings(preference: .online) },
            { fixture.app.metadataProviderSettingsModel.settings.preferOnlineArtwork.toggle() }
        ]
        for change in changes {
            let beforeChange = PlozziOSHomeMediaRail.artworkPrefetchSourceBuildCount
            change()
            try await fixture.update()
            let deadline = ContinuousClock.now + .seconds(3)
            while PlozziOSHomeMediaRail.artworkPrefetchSourceBuildCount == beforeChange,
                  ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertGreaterThan(PlozziOSHomeMediaRail.artworkPrefetchSourceBuildCount, beforeChange)
        }
    }

    @MainActor @Observable
    final class Model {
        var revision = 0
        var items: [MediaItem] = []
        @ObservationIgnored var presentedRevision = -1
    }

    private struct Rail: View {
        let app: PlozziOSAppModel
        let state: Model
        let prefetchesArtwork: Bool

        var body: some View {
            PlozziOSHomeMediaRail(
                title: Text("Continue Watching \(state.revision)"),
                items: state.items, style: .landscape, appModel: app,
                prefetchesArtwork: prefetchesArtwork, showsSeriesArtwork: true
            )
            .background(RevisionProbe(state: state, revision: state.revision))
            .environment(app)
            .environment(\.plozzCardStyle, .borderless)
            .environment(\.plozzMetrics, .touch(density: .standard, dynamicTypeSize: .large))
        }
    }

    private struct RevisionProbe: UIViewRepresentable {
        let state: Model
        let revision: Int
        func makeUIView(context: Context) -> UIView { UIView() }
        func updateUIView(_ view: UIView, context: Context) {
            state.presentedRevision = revision
        }
    }

    @MainActor
    private final class Fixture {
        let app: PlozziOSAppModel
        let state = Model()
        let window: UIWindow
        let previous: UIWindow?
        let alternateArtwork: URL
        private let suite = "HomeRailPrefetch.\(UUID())"
        private let defaults: UserDefaults
        private let profileID: String
        private let originalProviders: MetadataProviderSettings

        init(prefetchesArtwork: Bool) async throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            app = PlozziOSAppModel(
                accountStore: AccountStore(secureStore: InMemorySecureStore()),
                profileStore: ProfileStore(defaults: defaults)
            )
            profileID = app.profiles.add(name: "Fixture", avatarSymbol: "person.fill", colorIndex: 0).id
            app.selectProfile(profileID)
            app.settings.cardStyle.artwork = ArtworkSettings(preference: .library)
            originalProviders = app.metadataProviderSettingsModel.settings
            app.metadataProviderSettingsModel.settings = MetadataProviderSettings(
                orderMode: .custom, preferOnlineArtwork: false,
                disabledOrder: MetadataSourceAttribution.all.map(\.id)
            )
            let artwork = try await Self.artwork()
            alternateArtwork = try await Self.artwork()
            state.items = (0..<180).map { index in
                var item = MediaItem(
                    id: "episode-\(index)", title: "Episode \(index)", kind: .episode,
                    people: (0..<32).map { MediaPerson(id: "person-\($0)", name: "Person \($0)") },
                    providerIDs: ["Tmdb": "\(index + 1)", "Imdb": "tt\(index + 1)"]
                )
                item.sourceAccountID = "account-\(index % 12)"
                item.seriesID = "series-\(index)"
                item.parentTitle = "Series \(index)"
                item.posterURL = artwork
                item.seriesPosterURL = artwork
                item.backdropURL = artwork
                item.fallbackArtworkURL = artwork
                item.logoURL = artwork
                return item
            }
            let deadline = ContinuousClock.now + .seconds(5)
            while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
                  ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive })
            previous = scene.windows.first(where: \.isKeyWindow)
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = UIHostingController(rootView: Rail(
                app: app, state: state, prefetchesArtwork: prefetchesArtwork
            ))
            window.makeKeyAndVisible()
            try await update()
            try await Task.sleep(for: .milliseconds(250))
        }

        func update() async throws {
            state.revision += 1
            let deadline = ContinuousClock.now + .seconds(3)
            repeat {
                window.layoutIfNeeded()
                if state.presentedRevision == state.revision {
                    await Task.yield()
                    return
                }
                try await Task.sleep(for: .milliseconds(2))
            } while ContinuousClock.now < deadline
            XCTFail("The production Home rail did not receive the update.")
        }

        func close() {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
            app.metadataProviderSettingsModel.settings = originalProviders
            defaults.removePersistentDomain(forName: suite)
            for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.components(separatedBy: ".").contains(profileID) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        private static func artwork() async throws -> URL {
            let url = try XCTUnwrap(URL(string: "https://example.invalid/prefetch-\(UUID()).png"))
            let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180)).image { context in
                UIColor.systemPink.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            }
            let data = try XCTUnwrap(image.pngData())
            let cache = try XCTUnwrap(ArtworkSession.shared.configuration.urlCache)
            for variant in ArtworkImageVariant.allCases {
                let requestURL = variant.requestURL(for: url)
                let response = try XCTUnwrap(HTTPURLResponse(
                    url: requestURL, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "image/png", "Cache-Control": "max-age=3600"]
                ))
                cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: URLRequest(url: requestURL))
                let decoded = await ArtworkImageCache.shared.image(for: url, variant: variant)
                _ = try XCTUnwrap(decoded)
            }
            return url
        }
    }
}
#endif
