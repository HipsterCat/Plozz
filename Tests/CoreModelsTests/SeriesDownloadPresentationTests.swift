import XCTest
@testable import CoreModels

final class SeriesDownloadPresentationTests: XCTestCase {
    private let season = MediaItem(id: "season-1", title: "Season 1", kind: .season)

    private func item(kind: MediaItemKind = .series, hasTMDB: Bool = true) -> MediaItem {
        var item = MediaItem(id: "show", title: "A Show", kind: kind)
        if hasTMDB { item.providerIDs["Tmdb"] = "123" }
        return item
    }

    func testLibraryDownloadsRemainAvailableWithoutSeerr() {
        let presentation = SeriesDownloadPresentation(
            item: item(), children: [season], isDiscoveryItem: false, seerConnected: false
        )
        XCTAssertTrue(presentation.isVisible)
        XCTAssertTrue(presentation.hasLibraryDownloads)
        XCTAssertFalse(presentation.canRequestSeasons)
    }

    func testOwnedShowCanDownloadAndRequestMissingSeasons() {
        let presentation = SeriesDownloadPresentation(
            item: item(), children: [season], isDiscoveryItem: false, seerConnected: true
        )
        XCTAssertTrue(presentation.isVisible)
        XCTAssertTrue(presentation.hasLibraryDownloads)
        XCTAssertTrue(presentation.canRequestSeasons)
    }

    func testUnownedShowCanOpenRequestOnlySheet() {
        for children in [[], [season]] {
            let presentation = SeriesDownloadPresentation(
                item: item(), children: children, isDiscoveryItem: true, seerConnected: true
            )
            XCTAssertTrue(presentation.isVisible)
            XCTAssertFalse(presentation.hasLibraryDownloads, "Discovery metadata is not downloadable media.")
            XCTAssertTrue(presentation.canRequestSeasons)
        }
    }

    func testRequestControlDoesNotDependOnLoadedLibrarySeasons() {
        let presentation = SeriesDownloadPresentation(
            item: item(), children: [], isDiscoveryItem: false, seerConnected: true
        )
        XCTAssertTrue(presentation.isVisible)
        XCTAssertTrue(presentation.canRequestSeasons)
        XCTAssertFalse(presentation.hasLibraryDownloads)
    }

    func testMissingConnectionOrMetadataCannotOfferRequests() {
        for (connected, hasTMDB) in [(false, true), (true, false), (false, false)] {
            let presentation = SeriesDownloadPresentation(
                item: item(hasTMDB: hasTMDB),
                children: [season],
                isDiscoveryItem: true,
                seerConnected: connected
            )
            XCTAssertFalse(presentation.canRequestSeasons)
            XCTAssertFalse(presentation.isVisible)
        }
    }

    func testMoviesAndEpisodesKeepTheirExistingControls() {
        for kind in [MediaItemKind.movie, .episode] {
            let presentation = SeriesDownloadPresentation(
                item: item(kind: kind), children: [season], isDiscoveryItem: false, seerConnected: true
            )
            XCTAssertFalse(presentation.isVisible)
            XCTAssertFalse(presentation.hasLibraryDownloads)
            XCTAssertFalse(presentation.canRequestSeasons)
        }
    }

    func testLooseEpisodesStillProvideOfflineDownloads() {
        let episode = MediaItem(id: "episode-1", title: "Episode 1", kind: .episode)
        let presentation = SeriesDownloadPresentation(
            item: item(hasTMDB: false), children: [episode], isDiscoveryItem: false, seerConnected: false
        )
        XCTAssertTrue(presentation.hasLibraryDownloads)
        XCTAssertTrue(presentation.isVisible)
    }

    func testBulkDownloadLabelsDescribeTheirActualActions() {
        let cases: [(SeriesDownloadAction, String, String, Bool)] = [
            (.download, "Download All Available Episodes", "arrow.down.circle", true),
            (.preparing, "Preparing Downloads…", "clock", false),
            (.pause, "Pause Downloads", "pause.circle", true),
            (.resume, "Resume Downloads", "play.circle", true)
        ]
        for (action, title, icon, enabled) in cases {
            var resource = action.title
            resource.locale = Locale(identifier: "en")
            XCTAssertEqual(String(localized: resource), title)
            XCTAssertEqual(action.systemImage, icon)
            XCTAssertEqual(action.isEnabled, enabled)
        }
    }
}
