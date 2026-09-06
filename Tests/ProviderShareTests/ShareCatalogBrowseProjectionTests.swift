import XCTest
import CoreModels
@testable import ProviderShare

final class ShareCatalogBrowseProjectionTests: XCTestCase {
    private var createdCatalogDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in createdCatalogDirectories {
            try FileManager.default.removeItem(at: directory)
        }
        createdCatalogDirectories.removeAll()
        try super.tearDownWithError()
    }

    private func catalogDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plozz-browse-projection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        createdCatalogDirectories.append(directory)
        return directory
    }

    private func episode(
        _ path: String,
        series: String,
        season: Int,
        number: Int,
        metadataRoot: String
    ) -> CatalogAsset {
        CatalogAsset(
            relPath: path,
            basename: (path as NSString).lastPathComponent,
            size: 1_000,
            modifiedAt: Date(),
            kind: .episode,
            library: .tv,
            title: "Episode \(number)",
            year: nil,
            seriesTitle: series,
            seriesKey: ShareCatalogID.seriesKey(fromTitle: series),
            season: season,
            episode: number,
            metadataRoot: metadataRoot
        )
    }

    private func movie(
        _ path: String,
        title: String,
        year: Int,
        size: Int64 = 1_000
    ) -> CatalogAsset {
        let grouping = ShareMediaParser.movieGrouping(
            relPath: path,
            parsedTitle: title,
            parsedYear: year
        )
        return CatalogAsset(
            relPath: path,
            basename: (path as NSString).lastPathComponent,
            size: size,
            modifiedAt: Date(),
            kind: .movie,
            library: .movies,
            title: grouping.title,
            year: grouping.year,
            seriesTitle: nil,
            seriesKey: nil,
            season: nil,
            episode: nil,
            movieKey: ShareCatalogID.movieKey(fromTitle: grouping.title, year: grouping.year),
            movieTitleKey: ShareCatalogID.movieKey(fromTitle: grouping.title, year: nil)
        )
    }

    private func folder(_ path: String) -> MediaItem {
        MediaItem(id: "d:\(path)", title: (path as NSString).lastPathComponent, kind: .folder)
    }

    private func file(_ path: String) -> MediaItem {
        MediaItem(id: "f:\(path)", title: (path as NSString).lastPathComponent, kind: .video)
    }

    private func completeScan(
        _ store: ShareCatalogStore,
        directories: [String],
        scanID: Int64 = 1
    ) async {
        for path in directories {
            await store.recordDirectory(relPath: path, modifiedAt: Date(), scanID: scanID)
        }
        let finalized = await store.finalizePlayableInventory(inScan: scanID)
        XCTAssertTrue(finalized)
        await store.markDirectoryStateComplete(scanID: scanID)
    }

    func testAnimeContextIsIndependentOfMovieLibraryAndPersists() async throws {
        let directory = try catalogDirectory()
        let store = ShareCatalogStore(accountKey: "anime-movies", directory: directory)
        await store.upsert([
            movie("Movies/Akira (1988).mkv", title: "Akira", year: 1988)
        ], scanID: 1)
        await store.setLibraryAnimeContext(true)

        let liveContext = await store.libraryAnimeContext()
        let liveMovies = await store.movies(offset: 0, limit: 10)
        XCTAssertTrue(liveContext)
        XCTAssertEqual(liveMovies.first?.title, "Akira")

        let reopened = ShareCatalogStore(accountKey: "anime-movies", directory: directory)
        let reopenedContext = await reopened.libraryAnimeContext()
        let reopenedMovies = await reopened.movies(offset: 0, limit: 10)
        XCTAssertTrue(reopenedContext)
        XCTAssertEqual(reopenedMovies.first?.kind, .movie)
    }

    func testResetExternalEnrichmentRequeuesItemsAndPreservesLocalState() async throws {
        let store = ShareCatalogStore(accountKey: "reset-enrichment", directory: try catalogDirectory())
        let path = "Movies/Akira (1988).mkv"
        let itemID = ShareCatalogID.file(path)
        var asset = movie(path, title: "Akira", year: 1988)
        asset.explicitProviderIDs = ["imdb": "tt0094625"]
        await store.upsert([asset], scanID: 1)
        await store.materializeFilenameProviderIDs()

        var external = EnrichmentRecord()
        external.title = "Externally Resolved Akira"
        external.posterURL = URL(string: "https://example.com/akira.jpg")
        let savedExternal = await store.saveEnrichment(itemID: itemID, external, version: 18)
        let savedLocalState = await store.writeLocalEnrichmentState(
            itemID: itemID,
            version: 7,
            attempts: 2
        )
        XCTAssertTrue(savedExternal)
        XCTAssertTrue(savedLocalState)

        let settledBefore = await store.pendingEnrichment(forItemID: itemID, version: 18)
        let projectedBefore = await store.item(id: itemID)
        let localIDsBefore = await store.localProviderIDs(forItemID: itemID)
        XCTAssertNil(settledBefore)
        XCTAssertEqual(projectedBefore?.posterURL, external.posterURL)
        XCTAssertEqual(localIDsBefore["imdb"], "tt0094625")

        let reset = await store.resetExternalEnrichment()
        XCTAssertTrue(reset)

        let pendingAfter = await store.pendingEnrichment(forItemID: itemID, version: 18)
        let projectedAfter = await store.item(id: itemID)
        let localStateAfter = await store.localEnrichmentState(itemID: itemID)
        let localIDsAfter = await store.localProviderIDs(forItemID: itemID)
        XCTAssertNotNil(pendingAfter)
        XCTAssertEqual(projectedAfter?.title, "Akira")
        XCTAssertNil(projectedAfter?.posterURL)
        XCTAssertEqual(localStateAfter?.version, 7)
        XCTAssertEqual(localStateAfter?.attempts, 2)
        XCTAssertEqual(localIDsAfter["imdb"], "tt0094625")
    }

    func testLibraryContainerStaysFolderWhileAuthoritativeShowRootPromotes() async throws {
        let store = ShareCatalogStore(accountKey: "series-root", directory: try catalogDirectory())
        let showRoot = "TV Shows/Animanimals"
        await store.upsert([
            episode(
                "\(showRoot)/Season 01/Animanimals.S01E01.mkv",
                series: "Animanimals",
                season: 1,
                number: 1,
                metadataRoot: showRoot
            )
        ], scanID: 1)
        await completeScan(store, directories: ["TV Shows", showRoot])

        let projected = await store.browseItems([
            folder("TV Shows"),
            folder(showRoot),
        ])

        XCTAssertEqual(projected.map(\.id), [
            "d:TV Shows",
            ShareCatalogID.series("animanimals"),
        ])
        XCTAssertEqual(projected[0].kind, .folder, "one-show library must remain a physical container")
        XCTAssertEqual(projected[1].kind, .series)
        XCTAssertEqual(projected.count, 2, "a recognized show must not also appear as a duplicate folder")
        let reader: any ShareCatalogReading = store
        let throughCapability = await reader.browseItems([folder(showRoot)])
        XCTAssertEqual(throughCapability.map(\.id), [ShareCatalogID.series("animanimals")])
    }

    func testSortAwareCatalogCapabilityUsesStoreImplementation() async throws {
        let store = ShareCatalogStore(accountKey: "sorted-capability", directory: try catalogDirectory())
        await store.upsert([
            movie("Movies/Alien (1979).mkv", title: "Alien", year: 1979),
            movie("Movies/Dune (2021).mkv", title: "Dune", year: 2021),
            episode("TV/Alpha/S01E01.mkv", series: "Alpha", season: 1, number: 1, metadataRoot: "TV/Alpha"),
            episode("TV/Zeta/S01E01.mkv", series: "Zeta", season: 1, number: 1, metadataRoot: "TV/Zeta"),
        ], scanID: 1)
        let reader: any ShareCatalogReading = store
        let sort = CoreModels.SortDescriptor(field: .name, direction: .descending)
        let directMovies = await store.movies(offset: 0, limit: 10, sort: sort)
        let movies = await reader.movies(offset: 0, limit: 10, sort: sort)
        let directSeries = await store.series(in: .tv, offset: 0, limit: 10, sort: sort)
        let series = await reader.series(in: .tv, offset: 0, limit: 10, sort: sort)
        XCTAssertEqual(movies.map(\.title), ["Dune", "Alien"])
        XCTAssertEqual(directMovies, movies)
        XCTAssertEqual(series.map(\.title), ["Zeta", "Alpha"])
        XCTAssertEqual(directSeries, series)
    }

    func testSeriesProjectionIsScopedToExactMetadataRoot() async throws {
        let store = ShareCatalogStore(accountKey: "series-scope", directory: try catalogDirectory())
        await store.upsert([
            episode(
                "TV Shows/Animanimals/Season 01/E01.mkv",
                series: "Animanimals",
                season: 1,
                number: 1,
                metadataRoot: "TV Shows/Animanimals"
            ),
            episode(
                "Archive/Animanimals/Season 02/E01.mkv",
                series: "Animanimals",
                season: 2,
                number: 1,
                metadataRoot: "Archive/Animanimals"
            ),
        ], scanID: 1)
        await completeScan(
            store,
            directories: ["TV Shows", "TV Shows/Animanimals", "Archive"]
        )

        let projected = await store.browseItems([
            folder("TV Shows"),
            folder("TV Shows/Animanimals"),
            folder("Archive"),
        ])

        XCTAssertEqual(projected.map(\.id), [
            "d:TV Shows",
            ShareCatalogID.series("animanimals"),
            "d:Archive",
        ])
    }

    func testCompleteDirectSeasonFolderPromotesToCatalogSeason() async throws {
        let store = ShareCatalogStore(accountKey: "season-root", directory: try catalogDirectory())
        let showRoot = "TV Shows/Animanimals"
        let seasonRoot = "\(showRoot)/Season 01"
        await store.upsert([
            episode(
                "\(seasonRoot)/E01.mkv",
                series: "Animanimals",
                season: 1,
                number: 1,
                metadataRoot: showRoot
            ),
            episode(
                "\(seasonRoot)/E02.mkv",
                series: "Animanimals",
                season: 1,
                number: 2,
                metadataRoot: showRoot
            ),
        ], scanID: 1)
        await completeScan(store, directories: [seasonRoot])

        let projected = await store.browseItems([folder(seasonRoot)])

        XCTAssertEqual(projected.map(\.id), [
            ShareCatalogID.season("animanimals", 1),
        ])
        XCTAssertEqual(projected.first?.kind, .season)
        XCTAssertEqual(projected.first?.seriesID, ShareCatalogID.series("animanimals"))
    }

    func testPartialSeasonSubfolderDoesNotPromote() async throws {
        let store = ShareCatalogStore(accountKey: "partial-season", directory: try catalogDirectory())
        let showRoot = "TV Shows/Animanimals"
        await store.upsert([
            episode(
                "\(showRoot)/Season 01/Disc A/E01.mkv",
                series: "Animanimals",
                season: 1,
                number: 1,
                metadataRoot: showRoot
            ),
            episode(
                "\(showRoot)/Season 01/Disc B/E02.mkv",
                series: "Animanimals",
                season: 1,
                number: 2,
                metadataRoot: showRoot
            ),
        ], scanID: 1)
        await completeScan(store, directories: ["\(showRoot)/Season 01/Disc A"])

        let projected = await store.browseItems([folder("\(showRoot)/Season 01/Disc A")])

        XCTAssertEqual(projected.first?.id, "d:\(showRoot)/Season 01/Disc A")
        XCTAssertEqual(projected.first?.kind, .folder)
    }

    func testDedicatedMovieFolderPromotesOneLogicalMovieWithVersions() async throws {
        let store = ShareCatalogStore(accountKey: "movie-folder", directory: try catalogDirectory())
        let root = "Movies/Dune (2021)"
        await store.upsert([
            movie("\(root)/Dune.2021.1080p.mkv", title: "Dune", year: 2021, size: 1_000),
            movie("\(root)/Dune.2021.2160p.mkv", title: "Dune", year: 2021, size: 2_000),
        ], scanID: 1)
        await completeScan(store, directories: [root])

        let projected = await store.browseItems([folder(root)])

        XCTAssertEqual(projected.count, 1)
        XCTAssertEqual(projected.first?.id, ShareCatalogID.movie("dune-2021"))
        XCTAssertEqual(projected.first?.kind, .movie)
        XCTAssertEqual(projected.first?.versions.count, 2)
    }

    func testTitleMatchedMovieFolderNeedsStructuralMembershipEvidence() async throws {
        let store = ShareCatalogStore(accountKey: "movie-title-folder", directory: try catalogDirectory())
        let root = "Movies/Arrival"
        await store.upsert([
            movie("\(root)/Arrival.2016.mkv", title: "Arrival", year: 2016)
        ], scanID: 1)
        await completeScan(store, directories: [root])

        let projected = await store.browseItems([folder(root)])

        XCTAssertEqual(projected.first?.id, ShareCatalogID.movie("arrival-2016"))
        XCTAssertEqual(projected.first?.kind, .movie)
        XCTAssertEqual(projected.count, 1)
    }

    func testLooseSingleMovieDoesNotTurnLibraryContainerIntoMovie() async throws {
        let store = ShareCatalogStore(accountKey: "movie-library", directory: try catalogDirectory())
        await store.upsert([
            movie("Movies/Dune (2021).mkv", title: "Dune", year: 2021)
        ], scanID: 1)
        await completeScan(store, directories: ["Movies"])

        let projected = await store.browseItems([folder("Movies")])

        XCTAssertEqual(projected.first?.id, "d:Movies")
        XCTAssertEqual(projected.first?.kind, .folder)
    }

    func testSingleMovieInArbitraryMismatchedFolderDoesNotPromote() async throws {
        let store = ShareCatalogStore(accountKey: "movie-arbitrary", directory: try catalogDirectory())
        await store.upsert([
            movie("Incoming/Arrival.2016.mkv", title: "Arrival", year: 2016)
        ], scanID: 1)
        await completeScan(store, directories: ["Incoming"])

        let projected = await store.browseItems([folder("Incoming")])

        XCTAssertEqual(projected.first?.id, "d:Incoming")
        XCTAssertEqual(projected.first?.kind, .folder)
    }

    func testMixedCatalogEntitiesDoNotReplaceFolder() async throws {
        let store = ShareCatalogStore(accountKey: "mixed-folder", directory: try catalogDirectory())
        let root = "Mixed/Dune (2021)"
        await store.upsert([
            movie("\(root)/Dune.mkv", title: "Dune", year: 2021),
            episode(
                "\(root)/Show/Season 01/E01.mkv",
                series: "Show",
                season: 1,
                number: 1,
                metadataRoot: "\(root)/Show"
            ),
        ], scanID: 1)
        await completeScan(store, directories: [root])

        let projected = await store.browseItems([folder(root)])

        XCTAssertEqual(projected.first?.id, "d:\(root)")
        XCTAssertEqual(projected.first?.kind, .folder)
    }

    func testIndexedFilesUseCatalogIdentityAndMetadataWhileUnindexedFilesSurvive() async throws {
        let store = ShareCatalogStore(accountKey: "files", directory: try catalogDirectory())
        let first = "Movies/Dune (2021)/Dune.1080p.mkv"
        let second = "Movies/Dune (2021)/Dune.2160p.mkv"
        await store.upsert([
            movie(first, title: "Dune", year: 2021, size: 1_000),
            movie(second, title: "Dune", year: 2021, size: 2_000),
        ], scanID: 1)
        var enrichment = EnrichmentRecord()
        enrichment.title = "Dune: Part One"
        enrichment.posterURL = URL(string: "https://example.com/dune.jpg")
        _ = await store.saveEnrichment(
            itemID: ShareCatalogID.file(first),
            enrichment,
            version: 1
        )

        let unindexed = file("Movies/Dune (2021)/Notes from camera.mp4")
        let projected = await store.browseItems([file(first), file(second), unindexed])

        XCTAssertEqual(projected.count, 2, "two indexed versions collapse, unrelated live file remains")
        XCTAssertEqual(projected[0].id, ShareCatalogID.movie("dune-2021"))
        XCTAssertEqual(projected[0].title, "Dune: Part One")
        XCTAssertEqual(projected[0].posterURL, URL(string: "https://example.com/dune.jpg"))
        XCTAssertEqual(projected[1], unindexed)
    }

    func testIncompleteFolderInventoryDoesNotHidePotentialUnindexedNestedFiles() async throws {
        let store = ShareCatalogStore(accountKey: "incomplete-folder", directory: try catalogDirectory())
        let showRoot = "TV Shows/Animanimals"
        await store.upsert([
            episode(
                "\(showRoot)/Season 01/E01.mkv",
                series: "Animanimals",
                season: 1,
                number: 1,
                metadataRoot: showRoot
            )
        ], scanID: 1)
        // No completed-directory-state marker: the known episode is insufficient
        // proof that another playable child was not missed by an interrupted scan.

        let projected = await store.browseItems([folder(showRoot)])

        XCTAssertEqual(projected.first?.id, "d:\(showRoot)")
        XCTAssertEqual(projected.first?.kind, .folder)
    }

    func testCompletedScanWithUnclassifiedPlayableDescendantDoesNotPromoteFolder() async throws {
        let store = ShareCatalogStore(accountKey: "excluded-playable", directory: try catalogDirectory())
        let showRoot = "TV Shows/Animanimals"
        let episodePath = "\(showRoot)/Season 01/E01.mkv"
        let unmatchedPath = "\(showRoot)/Behind the curtain.mp4"
        await store.upsert([
            episode(
                episodePath,
                series: "Animanimals",
                season: 1,
                number: 1,
                metadataRoot: showRoot
            )
        ], scanID: 1)
        let inventorySaved = await store.upsertPlayablePaths(
            [episodePath, unmatchedPath],
            scanID: 1
        )
        XCTAssertTrue(inventorySaved)
        await completeScan(store, directories: [showRoot])

        let projected = await store.browseItems([folder(showRoot)])

        XCTAssertEqual(projected, [folder(showRoot)])
    }

    func testFolderPromotionKeepsIndependentlyOwnedCollectionsReachable() async throws {
        for isCollection in [false, true] {
            let store = ShareCatalogStore(accountKey: "extra-owner", directory: try catalogDirectory())
            let showRoot = "TV Shows/Animanimals"
            let ownerPath = isCollection ? "\(showRoot)/Collections/Clips" : showRoot
            let extraPath = "\(ownerPath)/featurettes/Interview.mkv"
            await store.upsert([
                episode(
                    "\(showRoot)/Animanimals.S01E01.mkv",
                    series: "Animanimals",
                    season: 1,
                    number: 1,
                    metadataRoot: showRoot
                )
            ], scanID: 1)
            await store.upsertExtras([
                CatalogExtraCandidate(
                    relPath: extraPath,
                    parentDir: "\(ownerPath)/featurettes",
                    basename: "Interview.mkv",
                    size: 1_000,
                    modifiedAt: Date(),
                    kind: .featurette,
                    title: "Interview",
                    ownerPath: ownerPath
                )
            ], scanID: 1)
            await store.resolveExtraOwners()
            let extras = await store.extras(
                ownerID: isCollection ? "d:\(ownerPath)" : ShareCatalogID.series("animanimals")
            )
            XCTAssertEqual(extras.count, 1)
            await completeScan(store, directories: [showRoot])

            let projected = await store.browseItems([folder(showRoot)])
            XCTAssertEqual(projected.count, 1)
            XCTAssertEqual(projected.first?.kind, isCollection ? .folder : .series)
        }
    }

    func testUnchangedIncrementalSkipRetainsCompletedFolderPromotion() async throws {
        let store = ShareCatalogStore(accountKey: "incremental-folder", directory: try catalogDirectory())
        let showRoot = "TV Shows/Animanimals"
        await store.upsert([
            episode(
                "\(showRoot)/Animanimals.S01E01.mkv",
                series: "Animanimals",
                season: 1,
                number: 1,
                metadataRoot: showRoot
            )
        ], scanID: 1)
        await completeScan(store, directories: [showRoot], scanID: 1)
        let baseline = await store.browseItems([folder(showRoot)])
        XCTAssertEqual(baseline.first?.kind, .series)

        await store.invalidateCompletedDirectoryState()
        await store.touchDirectoryContents(relPaths: [showRoot], scanID: 2)
        let duringScan = await store.browseItems([folder(showRoot)])
        XCTAssertEqual(duringScan.first?.kind, .folder)

        let inventoryFinalized = await store.finalizePlayableInventory(inScan: 2)
        XCTAssertTrue(inventoryFinalized)
        await store.markDirectoryStateComplete(scanID: 2)
        let afterSkip = await store.browseItems([folder(showRoot)])
        let recordedDirectories = await store.recordedDirectoryPaths()
        XCTAssertEqual(afterSkip.map(\.id), [
            ShareCatalogID.series("animanimals"),
        ])
        XCTAssertEqual(afterSkip.first?.kind, .series)
        XCTAssertTrue(recordedDirectories.contains(showRoot))
    }

    func testIndexedEpisodeKeepsFileWatchIdentity() async throws {
        let store = ShareCatalogStore(accountKey: "episode-file", directory: try catalogDirectory())
        let showRoot = "TV Shows/Animanimals"
        let path = "\(showRoot)/Season 01/E01.mkv"
        await store.upsert([
            episode(
                path,
                series: "Animanimals",
                season: 1,
                number: 1,
                metadataRoot: showRoot
            )
        ], scanID: 1)

        let projected = await store.browseItems([file(path)])

        XCTAssertEqual(projected.first?.id, ShareCatalogID.file(path))
        XCTAssertEqual(projected.first?.kind, .episode)
        XCTAssertEqual(projected.first?.seriesID, ShareCatalogID.series("animanimals"))
        XCTAssertEqual(projected.first?.seasonID, ShareCatalogID.season("animanimals", 1))
    }

    func testProjectionPreservesLiveWatchAndSourceState() async throws {
        let store = ShareCatalogStore(accountKey: "state", directory: try catalogDirectory())
        let path = "Movies/Dune (2021)/Dune.mkv"
        await store.upsert([movie(path, title: "Dune", year: 2021)], scanID: 1)
        let live = MediaItem(
            id: ShareCatalogID.file(path),
            title: "Dune.mkv",
            kind: .video,
            resumePosition: 321,
            playedPercentage: 0.4,
            isPlayed: true,
            sourceAccountID: "share-account",
            additionalSourceAccountIDs: ["backup-account"],
            lastPlayedAt: Date(timeIntervalSince1970: 123)
        )

        let items = await store.browseItems([live])
        guard let projected = items.first else {
            return XCTFail("expected projected catalog item")
        }

        XCTAssertEqual(projected.id, ShareCatalogID.movie("dune-2021"))
        XCTAssertEqual(projected.resumePosition, 321)
        XCTAssertEqual(projected.playedPercentage, 0.4)
        XCTAssertTrue(projected.isPlayed)
        XCTAssertEqual(projected.sourceAccountID, "share-account")
        XCTAssertEqual(projected.additionalSourceAccountIDs, ["backup-account"])
        XCTAssertEqual(projected.lastPlayedAt, Date(timeIntervalSince1970: 123))
    }

    func testSpecialPathCharactersRemainExactlyScoped() async throws {
        let store = ShareCatalogStore(accountKey: "special-paths", directory: try catalogDirectory())
        let showRoot = "TV_%/O'Brien [tvdb-42]"
        await store.upsert([
            episode(
                "\(showRoot)/Season 01/E01.mkv",
                series: "O'Brien",
                season: 1,
                number: 1,
                metadataRoot: showRoot
            ),
            episode(
                "TV_AX/O'Brien [tvdb-42]/Season 01/E02.mkv",
                series: "O'Brien",
                season: 1,
                number: 2,
                metadataRoot: "TV_AX/O'Brien [tvdb-42]"
            ),
        ], scanID: 1)
        await completeScan(store, directories: [showRoot])

        let projected = await store.browseItems([folder(showRoot)])

        XCTAssertEqual(projected.map(\.id), [
            ShareCatalogID.series("obrien"),
        ])
        XCTAssertEqual(projected.first?.kind, .series)
    }
}
