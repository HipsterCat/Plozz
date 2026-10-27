import CoreModels
import CoreUI
import FeatureHome
import FeatureHomeCore
import FeatureProfiles
import SwiftUI
@testable import AppShell

struct LargeNativeNavigationFixture: View {
    @State private var selection = NavigationRailDestination.home
    @State private var showsProfilePicker = false

    private let libraries: [AggregatedLibrary]
    private let destinations: [NavigationRailDestination]
    private let profile = Profile(id: "navigation-viewer", name: "Alex", colorIndex: 2)
    private var isSidebar: Bool { ProcessInfo.processInfo.arguments.contains("--native-vertical-navigation") }
    private var realLibraries: Bool { ProcessInfo.processInfo.arguments.contains("--real-library-pages") }

    init() {
        let longNames = ProcessInfo.processInfo.arguments.contains("--long-library-names")
        libraries = (1...20).map { index in
            AggregatedLibrary(
                accountID: "plex", accountName: "Plex", serverName: "Plex",
                providerKind: .plex,
                library: MediaLibrary(
                    id: "\(index)",
                    title: longNames ? "Library \(index) - Movies and Television Collection" : "Library \(index)",
                    kind: .movie
                )
            )
        }
        destinations = NavigationRailPlan.destinations(
            visibleLibraries: libraries, layout: .init(),
            availableKeys: NavigationDestinationDefaults.sidebar(visibleLibraries: libraries, hasMusic: true)
        )
    }

    var body: some View {
        Group {
            if showsProfilePicker {
                ProfilePickerView(
                    profiles: [profile, Profile(id: "other-viewer", name: "Sam", colorIndex: 4)],
                    activeProfileID: profile.id, onSelect: { _ in showsProfilePicker = false },
                    onCancel: { showsProfilePicker = false },
                    onOpenSettings: { selection = .settings; showsProfilePicker = false }
                )
            } else {
                shell
            }
        }
        .environment(\.themePalette, .dark)
        .environment(\.colorScheme, .dark)
        .environment(\.plozzNavigationStyle, isSidebar ? .sidebar : .tabBar)
        .environment(\.plozzReduceTransparency,
                     ProcessInfo.processInfo.arguments.contains("--opaque-controls"))
    }

    private var shell: some View {
        SettingsNavigationShell(style: isSidebar ? .sidebar : .tabBar, showsSettings: selection == .settings) { _ in
            if isSidebar {
                sidebar
            } else {
                NativeTopBarNavigation(
                    destinations: NavigationDestinationDefaults.topBar(destinations: destinations),
                    selection: $selection,
                    preventsAccidentalExit: true,
                    content: { destination, _ in AnyView(page(destination)) },
                    label: label,
                    profile: profile,
                    onOpenProfileSwitcher: { showsProfilePicker = true }
                )
            }
        } settings: {
            VStack {
                Text("Settings").accessibilityIdentifier("large-navigation-settings")
                Button("Back") { selection = .home }
            }
        }
    }

    private var sidebar: some View {
        TabView(selection: $selection) {
            Tab("Alex", systemImage: "person.crop.circle", value: NavigationRailDestination.library("profile")) {
                Color.clear.onAppear { showsProfilePicker = true }
            }
            ForEach(destinations, id: \.storageValue) { destination in
                Tab(value: destination) {
                    AnyView(page(destination).tvNavigationExitProtectionContent())
                } label: {
                    label(destination)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tvNavigationExitProtection(isEnabled: true)
    }

    private func label(_ destination: NavigationRailDestination) -> AnyView {
        if case let .library(key) = destination,
           let library = libraries.first(where: { $0.key == key }) {
            return AnyView(MainTabView.navigationLibraryLabel(
                .init(key: key, library: library), usesCompactSidebarText: isSidebar
            ))
        }
        return AnyView(Label(title(for: destination), systemImage: "square"))
    }

    private func page(_ destination: NavigationRailDestination) -> some View {
        NavigationStack {
            if realLibraries, destination == .allLibraries || libraries.contains(where: { .library($0.key) == destination }) {
                LibraryBrowseView(
                    viewModel: LibraryBrowseViewModel(
                        provider: NavigationFixtureProvider(), containerID: destination.storageValue,
                        containerKind: .movie, defaults: UserDefaults(suiteName: "NavigationFixture.\(UUID())")!,
                        sourceAccountID: "plex",
                        initialContentMode: ProcessInfo.processInfo.arguments.contains("--recommended-library-pages")
                            ? .recommended : .titles
                    ),
                    title: Text(verbatim: title(for: destination)),
                    isNavigationRoot: true,
                    onSelect: { _ in }
                )
            } else {
                Button("Page content") {}
                    .accessibilityIdentifier("large-navigation-content")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .bottom) {
            Text(verbatim: destination.storageValue)
                .accessibilityIdentifier("large-navigation-selection")
        }
    }

    private struct NavigationFixtureProvider: MediaProvider {
        let kind = ProviderKind.plex
        let session = UserSession(
            server: MediaServer(id: "plex", name: "Plex", baseURL: URL(string: "https://fixture.invalid")!,
                                provider: .plex),
            userID: "viewer", userName: "Viewer", deviceID: "fixture", accessToken: "fixture"
        )

        func libraries() async throws -> [MediaLibrary] { [] }
        func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
        func latest(limit: Int) async throws -> [MediaItem] { [] }
        func item(id: String) async throws -> MediaItem { throw AppError.notFound }
        func children(of itemID: String) async throws -> [MediaItem] { [] }
        func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
            try await Task.sleep(for: .milliseconds(200))
            return .init(
                items: (0..<20).map { MediaItem(id: "\($0)", title: "Movie \($0)", kind: .movie) },
                startIndex: 0, totalCount: 20
            )
        }
        func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
        func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
        func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
        func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
    }

    private func title(for destination: NavigationRailDestination) -> String {
        switch destination {
        case .home: "Home"
        case .watchlist: "Watchlist"
        case .liveTV: "Live TV"
        case .search: "Search"
        case .music: "Music"
        case .allLibraries: "All Libraries"
        case .settings: "Settings"
        case .library: "Library"
        }
    }
}
