import XCTest
import CoreModels
@testable import FeatureHomeCore

final class HomePresentationRowTests: XCTestCase {
    func testBothPresetsPutLibrariesLastInHomeAndTheArrangerWithLiveAndFallbackRows() {
        let source = library("a")
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie)
        let section = LibrarySection(id: "recentlyAdded", title: "Latest", items: [item])
        let content = HomeViewModel.Content(
            continueWatching: [item], latest: [item], watchlist: [item], libraries: [source],
            librarySections: [.init(library: source, sections: [section])]
        )
        let card = HomeLiveTVChannel(
            route: .init(
                profileID: "profile", channelID: "news", sourceID: "source",
                sourceAuthorizationID: "approval", serverAuthorizationID: "servers"
            ), name: "News", sourceName: "Source", number: 1
        )
        let snapshot = HomeLiveTVSnapshot(recentChannels: [], channels: [card])
        for preset: HomeRowCustomization.Defaults in [.matchServer, .combined] {
            var customization = HomeRowCustomization(defaults: preset)
            if preset == .matchServer {
                customization.resolvedDefaults = .init(
                    mode: .combined, order: HomeRowChoice.shared.map(\.id), fallbackAccountIDs: ["a"]
                )
            }
            let visibility = HomeLibraryVisibility(rowCustomization: customization)
            let home = HomeRow.rows(
                for: content, isLibraryVisible: visibility.isEnabled,
                isGlobalRowEnabled: visibility.isGlobalRowEnabled
            )
            let presented = HomePresentationRow.resolve(
                rows: home, content: content, visibility: visibility, liveTV: snapshot
            )
            let arranged = visibility.rowSections(
                choices: HomeRowChoice.shared + HomeRowChoice.baseRows(for: source)
            ).enabled
            XCTAssertEqual(presented.map(\.id), arranged)
            XCTAssertEqual(presented.last?.id, .libraries)
            XCTAssertTrue(presented.contains { $0.id == .liveTV })
        }
    }

    func testRetainedNativeRowsImmediatelyHonorDisabledLibraryAndItemVisibility() {
        let scoped = HomeServerRowDefinition(
            accountID: "a", serverName: "Server", providerKind: .plex,
            section: .init(id: "scoped", kind: .recommendations, libraryID: "disabled")
        )
        let unscoped = HomeServerRowDefinition(
            accountID: "a", serverName: "Server", providerKind: .plex,
            section: .init(id: "unscoped", kind: .recommendations)
        )
        let hidden = MediaItem(id: "hidden", title: "Hidden", kind: .movie)
            .taggingSource("a").taggingLibrary("disabled")
        let shown = MediaItem(id: "shown", title: "Shown", kind: .movie)
            .taggingSource("a").taggingLibrary("enabled")
        let visibility = HomeLibraryVisibility(
            disabledKeys: ["a:disabled"],
            rowCustomization: .init(defaults: .custom, shown: [scoped.id, unscoped.id])
        )
        for failure: AppError? in [nil, .serverUnreachable] {
            let content = HomeViewModel.Content(serverRows: [
                .init(definition: scoped, items: [hidden], isLoading: failure == nil, failure: failure),
                .init(definition: unscoped, items: [hidden, shown], isLoading: failure == nil, failure: failure)
            ])
            let rows = HomePresentationRow.resolve(rows: [], content: content, visibility: visibility)
            XCTAssertEqual(rows.map(\.id), [unscoped.id])
            guard case let .library(row) = rows.first?.source else { return XCTFail("Missing retained row") }
            XCTAssertEqual(row.section.items.map(\.id), ["shown"])
            XCTAssertEqual(row.isLoading, failure == nil)
            XCTAssertEqual(row.failure, failure)
        }
        let allHidden = HomeViewModel.Content(serverRows: [.init(definition: unscoped, items: [hidden])])
        XCTAssertTrue(HomePresentationRow.resolve(rows: [], content: allHidden, visibility: visibility).isEmpty)
    }

    func testLiveOnlyHomeUsesTypedRowsAndIndependentVisibility() {
        let card = HomeLiveTVChannel(
            route: .init(
                profileID: "profile", channelID: "live", sourceID: "playlist",
                sourceAuthorizationID: "approval", serverAuthorizationID: "servers"
            ), name: "News", sourceName: "Playlist", number: 1
        )
        let snapshot = HomeLiveTVSnapshot(recentChannels: [card], channels: [card])
        let order: [HomeRowID] = [.liveTV, .global(.continueWatching)]
        let visibility = HomeLibraryVisibility(rowCustomization: .init(order: order, shown: Set(order)))
        let rows = HomePresentationRow.resolve(rows: [], content: .init(), visibility: visibility, liveTV: snapshot)
        XCTAssertEqual(rows.map(\.id), order)
        guard case .liveTV(let channels) = rows.first?.source,
              case .home(let recent) = rows.last?.source else { return XCTFail("Expected typed Live TV and mixed recent row") }
        XCTAssertEqual(channels, [card])
        XCTAssertEqual(recent.kind, .continueWatching)
        XCTAssertTrue(recent.items.isEmpty, "A live channel must never masquerade as a MediaItem.")
        if case .loaded = HomePresentationRow.displayState(.empty, liveTV: snapshot, visibility: visibility) {
        } else { XCTFail("Cached Live TV can populate an otherwise empty Home.") }

        let hidden = HomeLibraryVisibility(rowCustomization: .init(order: order, hidden: Set(order)))
        XCTAssertFalse(HomePresentationRow.hasLiveTVRows(snapshot, visibility: hidden))
        let noRecent = HomeLibraryVisibility(rowCustomization: .init(
            order: order, hidden: [.global(.continueWatching)], shown: [.liveTV]
        ))
        XCTAssertEqual(
            HomePresentationRow.resolve(rows: [], content: .init(), visibility: noRecent, liveTV: snapshot).map(\.id),
            [.liveTV]
        )
    }

    func testEmptyNativeAudioRowDisappearsEvenWhenItsSavedDefinitionIsShown() {
        let definition = HomeServerRowDefinition(
            accountID: "a", serverName: "Server", providerKind: .emby,
            section: .init(id: "emby:listening", kind: .recommendations, title: "Continue Listening")
        )
        let visibility = HomeLibraryVisibility(rowCustomization: .init(
            defaults: .custom, order: [definition.id], shown: [definition.id]
        ))
        let staleVideo = MediaItem(id: "movie", title: "Movie", kind: .movie).taggingSource("a")
        let before = HomeViewModel.Content(serverRows: [.init(definition: definition, items: [staleVideo])])
        XCTAssertEqual(
            HomePresentationRow.resolve(rows: [], content: before, visibility: visibility).map(\.id),
            [definition.id]
        )
        let refreshed = HomeViewModel.Content(serverRows: [.init(definition: definition, items: [])])
        XCTAssertTrue(
            HomePresentationRow.resolve(rows: [], content: refreshed, visibility: visibility).isEmpty,
            "A saved native-row preference must not preserve an empty heading after refresh."
        )
    }

    private func library(_ account: String) -> AggregatedLibrary {
        AggregatedLibrary(
            accountID: account, accountName: account, serverName: "Server",
            providerKind: .emby, library: MediaLibrary(id: "movies", title: "Movies", kind: .movie)
        )
    }

    func testEveryLayoutReceivesOneOrderedAndFilteredRowList() {
        let a = library("a")
        let b = library("b")
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie)
        let sections = [
            HomeLibrarySectionGroup(library: a, sections: [
                LibrarySection(id: "recentlyAdded", title: "Latest A", items: [item]),
                LibrarySection(id: "hidden", title: "Hidden", items: [item], isHomeDefault: false)
            ]),
            HomeLibrarySectionGroup(library: b, sections: [
                LibrarySection(id: "recentlyAdded", title: "Latest B", items: [item])
            ])
        ]
        let content = HomeViewModel.Content(
            continueWatching: [item], latest: [item], watchlist: [item], libraries: [a, b],
            mergeLibraries: false, librarySections: sections
        )
        let order: [HomeRowID] = [
            .library(b.key, kind: .recentlyAdded), .global(.watchlist),
            .library(a.key, kind: .recentlyAdded), .global(.continueWatching), .libraries
        ]
        let visibility = HomeLibraryVisibility(rowCustomization: .init(order: order))
        let rows = HomeRow.rows(for: content, isLibraryVisible: visibility.isEnabled,
                                isGlobalRowEnabled: visibility.isGlobalRowEnabled)
        let resolved = HomePresentationRow.resolve(rows: rows, content: content, visibility: visibility)
        XCTAssertEqual(resolved.map(\.id), order)
        XCTAssertEqual(Set(resolved.map(\.id)).count, resolved.count)
    }

    func testAllRowsCanStayHiddenIncludingLibraries() {
        let source = library("a")
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie)
        let content = HomeViewModel.Content(
            continueWatching: [item], latest: [item], watchlist: [item], libraries: [source],
            librarySections: [.init(library: source, sections: [
                LibrarySection(id: "recentlyAdded", title: "Latest", items: [item])
            ])]
        )
        let choices = HomeRowChoice.shared + HomeRowChoice.baseRows(for: source)
        let visibility = HomeLibraryVisibility(
            rowCustomization: .init(hidden: Set(choices.map(\.id)))
        )
        let rows = HomeRow.rows(for: content, isLibraryVisible: visibility.isEnabled)
        XCTAssertTrue(HomePresentationRow.resolve(rows: rows, content: content, visibility: visibility).isEmpty)
    }

    func testSelectedRecommendationKeepsItsOrderedSlotWhileLoadingAndFailing() {
        let source = library("a")
        let id = HomeRowID.library(key: source.key, section: "selected")
        let visibility = HomeLibraryVisibility(rowCustomization: .init(order: [id, .libraries], shown: [id]))
        for failure: AppError? in [nil, .serverUnreachable] {
            let content = HomeViewModel.Content(
                libraries: [source], librarySections: [
                    .init(library: source, sections: [],
                          loadingRows: failure == nil ? [.hubs] : [],
                          failures: failure.map { [.hubs: $0] } ?? [:])
                ]
            )
            let rows = HomeRow.rows(for: content, isLibraryVisible: visibility.isEnabled)
            let result = HomePresentationRow.resolve(rows: rows, content: content, visibility: visibility)
            XCTAssertEqual(result.map(\.id), [id, .libraries])
            guard case let .library(row) = result.first?.source else {
                return XCTFail("Expected the selected recommendation's loading/error slot")
            }
            XCTAssertEqual(row.failure, failure)
            XCTAssertEqual(row.isLoading, failure == nil)
        }
    }

    func testNextUpAndLatestRetainTheirOrderAsEitherFeedCompletes() {
        let source = library("a")
        let item = MediaItem(id: "episode", title: "Episode", kind: .episode)
        for loaded in [Set<String>(), ["nextUp"], ["recentlyAdded"], ["nextUp", "recentlyAdded"]] {
            let group = HomeLibrarySectionGroup(
                library: source,
                sections: ["recentlyAdded", "nextUp"].filter(loaded.contains).map {
                    LibrarySection(id: $0, title: $0, items: [item])
                },
                loadingRows: Set([LibraryHomeRowKind.nextUp, .recentlyAdded].filter {
                    !loaded.contains($0.rawValue)
                })
            )
            XCTAssertEqual(group.rows.map(\.id), ["nextUp", "recentlyAdded"])
        }
    }

    func testMergeSuppressesCachedNativeAndLibraryNextUpRowsIncludingPlaceholders() {
        let source = library("a")
        let native = HomeServerRowDefinition(
            accountID: source.accountID, serverName: source.serverName, providerKind: .jellyfin,
            section: .init(id: "native-next", kind: .nextUp)
        )
        let item = MediaItem(id: "resume", title: "Resume", kind: .episode, resumePosition: 60)
        var visibility = HomeLibraryVisibility(
            rowCustomization: .init(
                defaults: .provider, shown: [native.id], serverRows: [native]
            ),
            mergeNextUpIntoContinueWatching: true
        )
        for loading in [false, true] {
            let content = HomeViewModel.Content(
                continueWatching: [item], libraries: [source],
                librarySections: [.init(
                    library: source,
                    sections: loading ? [] : [.init(id: "nextUp", title: "Next Up", items: [item])],
                    loadingRows: loading ? [.nextUp] : []
                )],
                serverRows: [.init(definition: native, items: loading ? [] : [item], isLoading: loading)]
            )
            let rows = HomeRow.rows(for: content, isLibraryVisible: visibility.isEnabled)
            let merged = HomePresentationRow.resolve(rows: rows, content: content, visibility: visibility)
            XCTAssertTrue(merged.contains { $0.id == .global(.continueWatching) })
            XCTAssertFalse(merged.contains { $0.id == native.id || $0.id.libraryKind == .nextUp })
            visibility.mergeNextUpIntoContinueWatching = false
            let separate = HomePresentationRow.resolve(rows: rows, content: content, visibility: visibility)
            XCTAssertTrue(separate.contains { $0.id == native.id })
            XCTAssertTrue(separate.contains { $0.id.libraryKind == .nextUp })
            visibility.mergeNextUpIntoContinueWatching = true
        }
    }
}
