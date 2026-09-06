import XCTest
import CoreModels
@testable import FeatureHomeCore

@MainActor
final class DetailOpenEnvironmentTests: XCTestCase {
    func testSelectingAnIndexRefForTheSameMoviePreservesImmediateResumeProgress() {
        let movie = MediaItem(
            id: "movie", title: "Movie", kind: .movie,
            runtime: 2_000, resumePosition: 800, playedPercentage: 0.4,
            sourceAccountID: "plex"
        )
        let membership = MediaSourceRef(accountID: "plex", itemID: movie.id, kind: .movie)
        let seeded = DetailOpenEnvironment.initialItem(for: movie, selectedSource: membership)
        XCTAssertEqual(seeded.resumePosition, 800)
        XCTAssertEqual(seeded.resumeProgressFraction, 0.4)
    }

    func testSelectingAnotherSourceDoesNotCopyTheOriginalMovieProgress() {
        let movie = MediaItem(
            id: "movie", title: "Movie", kind: .movie,
            resumePosition: 800, sourceAccountID: "plex"
        )
        let alternate = MediaSourceRef(accountID: "jellyfin", itemID: "other-movie", kind: .movie)
        let seeded = DetailOpenEnvironment.initialItem(for: movie, selectedSource: alternate)
        XCTAssertEqual(seeded.id, alternate.itemID)
        XCTAssertEqual(seeded.sourceAccountID, alternate.accountID)
        XCTAssertNil(seeded.resumePosition)
    }

    func testInitialSelectionUsesLiveLocalityBeforeDetailConstruction() {
        let item = MediaItem(
            id: "remote-series",
            title: "One Piece",
            kind: .series,
            sourceAccountID: "remote"
        )
        let remote = MediaSourceRef(
            accountID: "remote",
            itemID: "remote-series",
            kind: .series,
            providerKind: .jellyfin,
            locality: .local
        )
        let local = MediaSourceRef(
            accountID: "local",
            itemID: "local-series",
            kind: .series,
            providerKind: .plex,
            locality: .remote
        )

        let selection = DetailOpenEnvironment.initialSourceSelection(
            for: item,
            isDiscovery: false,
            libraryOrigin: nil,
            identitySources: { _ in [remote, local] },
            sourceLocality: { $0 == "local" ? .local : .remote }
        )

        XCTAssertEqual(selection.selected?.accountID, "local")
        XCTAssertEqual(selection.selected?.itemID, "local-series")
    }

    func testDiscoveryItemIsNeverRetargeted() {
        let item = MediaItem(id: "seerr:1", title: "Missing", kind: .movie)
        let selection = DetailOpenEnvironment.initialSourceSelection(
            for: item,
            isDiscovery: true,
            libraryOrigin: nil,
            identitySources: { _ in
                [MediaSourceRef(accountID: "local", itemID: "library-copy")]
            },
            sourceLocality: { _ in .local }
        )

        XCTAssertTrue(selection.sources.isEmpty)
        XCTAssertNil(selection.selected)
    }

    func testAccountTaggedGlobalItemWithoutLocalProofUsesExternalDetail() {
        let item = MediaItem(
            id: "global-discover-id",
            title: "The Legend of Hei",
            kind: .movie,
            providerIDs: ["PlexGuid": "plex://movie/global-discover-id"],
            locallyValidatedPlayableSource: false,
            sourceAccountID: "plex-account"
        )

        XCTAssertTrue(DetailOpenEnvironment.isDiscovery(
            item,
            identitySources: { _ in [] }
        ))
        let selection = DetailOpenEnvironment.initialSourceSelection(
            for: item,
            isDiscovery: true,
            libraryOrigin: nil,
            identitySources: { _ in [] },
            sourceLocality: { _ in .local }
        )
        XCTAssertTrue(selection.sources.isEmpty)
        XCTAssertNil(selection.selected)
        XCTAssertEqual(
            item.ownershipPresentation().showsPlaybackDetails,
            false
        )
        XCTAssertEqual(
            item.ownershipPresentation().showsProviderManagement,
            false
        )
    }

    func testValidatedIdentityIndexCopyRestoresLibraryDetail() {
        let item = MediaItem(
            id: "global-discover-id",
            title: "The Legend of Hei",
            kind: .movie,
            locallyValidatedPlayableSource: false,
            sourceAccountID: "plex-account"
        )
        let local = MediaSourceRef(
            accountID: "plex-account",
            itemID: "local-rating-key",
            kind: .movie,
            providerKind: .plex
        )

        XCTAssertFalse(DetailOpenEnvironment.isDiscovery(
            item,
            identitySources: { _ in [local] }
        ))
        let presentation = item.ownershipPresentation(
            additionalSources: [local]
        )
        XCTAssertTrue(presentation.canPlay)
        XCTAssertTrue(presentation.showsPlaybackDetails)
        XCTAssertTrue(presentation.showsProviderManagement)
    }
}
