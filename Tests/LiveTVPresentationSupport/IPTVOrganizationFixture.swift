import CoreModels
import CoreUI
import FeatureLiveTVCore
import SwiftUI
@testable import FeatureLiveTV

struct IPTVOrganizationFixture: View {
    @State private var model: LiveTVPrototypeModel
    @State private var imports: LiveTVPrototypeImportModel
    private let arguments = ProcessInfo.processInfo.arguments

    init() {
        let longName = ProcessInfo.processInfo.arguments.contains("--organization-long-name")
        let channels: [LiveTVPrototypeChannel] = [
            Self.channel("news", "National News", category: "US News", country: "US", language: "en"),
            Self.channel("cinema", "Cinema World", category: "International", country: "FR", language: "fr"),
            Self.channel("community", longName
                ? "Community Channel with local news, neighborhood updates and weekend events"
                : "Community Channel", category: "Uncategorized"),
            Self.channel("events", "Weekend Events", category: "Uncategorized")
        ]
        _model = State(initialValue: LiveTVPrototypeModel(
            channels: channels, preferencesStore: OrganizationFixtureStore()
        ))
        _imports = State(initialValue: LiveTVPrototypeImportModel(
            configuration: .init(playlists: [
                .init(id: "sample", name: "Sample playlist", playlistURL: URL(string: "https://example.test/list.m3u")!)
            ]), loader: LiveTVSourceLoader()
        ))
    }

    var body: some View {
        NavigationStack {
            if arguments.contains("--organization-hidden") {
                LiveTVHiddenChannelManagementView(model: model, canMutate: canMutate)
            } else {
                LiveTVChannelOrganizationView(model: model, imports: imports, canMutate: canMutate)
            }
        }
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.layoutDirection, arguments.contains("--organization-rtl") ? .rightToLeft : .leftToRight)
        .environment(\.themePalette, .dark)
        .environment(\.colorScheme, .dark)
        .background { AppBackground(palette: .dark) }
        #if os(iOS)
        .environment(\.plozzMetrics, .touch(density: .standard))
        .dynamicTypeSize(arguments.contains("--organization-large-text") ? .accessibility3 : .large)
        #endif
    }

    private func canMutate() -> Bool { !arguments.contains("--organization-read-only") }

    private static func channel(
        _ id: String, _ name: String, category: String, country: String? = nil, language: String? = nil
    ) -> LiveTVPrototypeChannel {
        .init(
            id: id, number: 1, name: name, category: category, symbol: "tv", accent: 0,
            source: .iptv, tagline: "", configuredSourceID: "sample", language: language, country: country
        )
    }
}

private final class OrganizationFixtureStore: LiveTVPreferencesStoring, @unchecked Sendable {
    private var value: LiveTVPreferences = {
        var organization = LiveTVChannelOrganization()
        organization.region = .init(isEnabled: true, countries: ["us"], languages: ["en"])
        organization.setCategory(.init(sourceID: "sample", name: "International", visibility: .hidden))
        organization.setCategory(.init(sourceID: "sample", name: "US News", visibility: .shown, isFavorite: true))
        return .init(organization: organization)
    }()

    func load() throws -> LiveTVPreferences { value }
    func save(_ preferences: LiveTVPreferences) throws { value = preferences }
}
