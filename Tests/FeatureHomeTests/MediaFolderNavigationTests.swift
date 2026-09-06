import CoreModels
import FeatureHomeCore
import XCTest

final class MediaFolderNavigationTests: XCTestCase {
    func testShareFolderBecomesItsOwnLibraryGrid() {
        let folder = MediaItem(id: "d:TV Shows", title: "TV Shows", kind: .folder)
            .taggingSource("nas")
        let library = MediaFolderNavigation.library(for: folder, providerKind: .mediaShare)

        XCTAssertEqual(library?.id, folder.id)
        XCTAssertEqual(library?.title, "TV Shows")
        XCTAssertEqual(library?.kind, .folder)
        XCTAssertEqual(library?.sourceAccountID, "nas")
        XCTAssertEqual(library?.sourceContainerIDByAccount, ["nas": "d:TV Shows"])
    }

    func testNestedFolderKeepsItsExactPathAndOriginAccount() {
        let folder = MediaItem(
            id: "d:TV Shows/Collections/100%_Family",
            title: "100%_Family",
            kind: .folder
        ).taggingSource("another-account")
        let library = MediaFolderNavigation.library(
            for: folder,
            providerKind: .mediaShare,
            sourceAccountID: "origin"
        )

        XCTAssertEqual(library?.id, folder.id)
        XCTAssertEqual(library?.sourceAccountID, "origin")
        XCTAssertEqual(library?.sourceContainerIDByAccount, ["origin": folder.id])
    }

    func testCatalogMediaKeepsDetailNavigationEvenWithFolderLikeTitle() {
        for kind: MediaItemKind in [.movie, .series, .season, .episode, .video, .collection] {
            let item = MediaItem(id: "catalog-item", title: "TV Shows", kind: kind)
            XCTAssertNil(
                MediaFolderNavigation.library(for: item, providerKind: .mediaShare),
                "\(kind) must keep its existing detail/episode route"
            )
        }
    }

    func testServerBackedContainersKeepTheirExistingRouting() {
        let folder = MediaItem(id: "folder", title: "Collection", kind: .folder)
        for provider: ProviderKind in [.plex, .jellyfin, .emby] {
            XCTAssertNil(MediaFolderNavigation.library(for: folder, providerKind: provider))
        }
    }

    func testUnscopedShareFolderDoesNotInventAccountIdentity() {
        let folder = MediaItem(id: "share:root", title: "NAS", kind: .folder)
        let library = MediaFolderNavigation.library(for: folder, providerKind: .mediaShare)
        XCTAssertNil(library?.sourceAccountID)
        XCTAssertEqual(library?.sourceContainerIDByAccount, [:])
    }
}
