import CoreModels
import XCTest
@testable import MediaDownloads

final class RegistryOfflinePlaybackResolverTests: XCTestCase {

    private func makeResolver(root: URL) -> (DownloadedMediaRegistry, RegistryOfflinePlaybackResolver) {
        let registry = DownloadedMediaRegistry(store: InMemoryDownloadedMediaStore())
        let storage = FixedDownloadStorageLocator(root: root)
        return (registry, RegistryOfflinePlaybackResolver(registry: registry, storage: storage))
    }

    private func pin(_ record: DownloadedMediaRecord, root: URL) throws -> URL {
        let url = try FixedDownloadStorageLocator(root: root).pinnedFileURL(for: record)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("downloaded media".utf8).write(to: url)
        return url
    }

    func testDownloadedCopyWinsOverAnotherServersSelectedVersion() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, resolver) = makeResolver(root: root)
        var downloaded = DownloadTestFactory.movie()
        downloaded.id = "plex-movie"
        downloaded.sourceAccountID = "plex-account"
        var record = try DownloadTestFactory.record(versionID: "plex-1080", status: .completed)
        record.snapshot = PinnedMediaSnapshot(item: downloaded)
        _ = try await registry.beginDownload(record)
        let localURL = try pin(record, root: root)

        var opened = downloaded
        opened.id = "jellyfin-movie"
        opened.sourceAccountID = "jellyfin-account"
        opened.selectedVersionID = "jellyfin-4k"
        for version in [nil, opened.selectedVersionID] {
            let resolved = await resolver.localPlaybackURL(for: opened, versionID: version)
            XCTAssertEqual(resolved, localURL)
        }
    }

    func testUnavailableExactVersionDoesNotHideAnotherCompletedCopy() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, resolver) = makeResolver(root: root)
        let local = try DownloadTestFactory.record(versionID: "z-local", status: .completed)
        _ = try await registry.beginDownload(local)
        let localURL = try pin(local, root: root)
        for (version, status) in [
            ("a-queued", DownloadStatus.queued),
            ("b-downloading", .downloading),
            ("c-missing", .completed)
        ] {
            _ = try await registry.beginDownload(
                try DownloadTestFactory.record(versionID: version, status: status)
            )
            let resolved = await resolver.localPlaybackURL(
                for: DownloadTestFactory.movie(), versionID: version
            )
            XCTAssertEqual(resolved, localURL, version)
        }
        let automatic = await resolver.localPlaybackURL(for: DownloadTestFactory.movie())
        XCTAssertEqual(automatic, localURL)
    }

    func testCrossServerLookupUsesAllCapturedProviderIdentities() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, resolver) = makeResolver(root: root)
        var downloaded = DownloadTestFactory.movie()
        downloaded.providerIDs["Tmdb"] = "603"
        var record = try DownloadTestFactory.record(versionID: "download", status: .completed)
        record.snapshot = PinnedMediaSnapshot(item: downloaded)
        _ = try await registry.beginDownload(record)
        let localURL = try pin(record, root: root)

        var opened = downloaded
        opened.id = "another-server-item"
        opened.providerIDs = ["tmdb": "603"]
        let resolved = await resolver.localPlaybackURL(for: opened, versionID: "remote-version")
        XCTAssertEqual(resolved, localURL)
    }

    func testLightweightItemMatchesItsAccountScopedSnapshot() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, resolver) = makeResolver(root: root)
        var downloaded = DownloadTestFactory.movie()
        downloaded.sourceAccountID = "account"
        var record = try DownloadTestFactory.record(versionID: "download", status: .completed)
        record.snapshot = PinnedMediaSnapshot(item: downloaded)
        _ = try await registry.beginDownload(record)
        let localURL = try pin(record, root: root)

        let opened = MediaItem(
            id: downloaded.id, title: downloaded.title, kind: .movie,
            sourceAccountID: "account"
        )
        let resolved = await resolver.localPlaybackURL(for: opened, versionID: "remote-version")
        XCTAssertEqual(resolved, localURL)
    }

    func testExactDownloadedVersionWinsAndSuppliesItsOwnMetadataAndSubtitles() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, resolver) = makeResolver(root: root)
        var urls: [String: URL] = [:]
        for version in ["a-hd", "z-uhd"] {
            let record = try DownloadTestFactory.record(versionID: version, status: .completed)
            _ = try await registry.beginDownload(record)
            urls[version] = try pin(record, root: root)
        }
        let selectedURL = try XCTUnwrap(urls["z-uhd"])
        let metadata = MediaSourceMetadata(
            container: "mkv", video: .init(codec: "hevc", bitDepth: 10)
        )
        try JSONEncoder().encode(metadata).write(
            to: selectedURL.appendingPathExtension("metadata.json")
        )
        let subtitleURL = selectedURL.deletingLastPathComponent().appendingPathComponent("en.srt")
        try Data("subtitle".utf8).write(to: subtitleURL)
        try JSONEncoder().encode([
            OfflineSubtitleFile(
                fileName: "en.srt", language: "en", codec: "srt",
                forced: false, hearingImpaired: false
            )
        ]).write(to: selectedURL.appendingPathExtension("subtitles.json"))
        let item = DownloadTestFactory.movie()
        let resolved = await resolver.localPlaybackURL(for: item, versionID: "z-uhd")
        let resolvedMetadata = await resolver.localPlaybackMetadata(for: item, versionID: "z-uhd")
        let subtitles = await resolver.localSubtitleTracks(for: item, versionID: "z-uhd")
        XCTAssertEqual(resolved, selectedURL)
        XCTAssertEqual(resolvedMetadata, metadata)
        XCTAssertEqual(subtitles.map(\.deliverySource), [.localFile(subtitleURL)])

        try FileManager.default.removeItem(at: XCTUnwrap(urls["a-hd"]))
        let fallback = await resolver.localPlaybackURL(for: item, versionID: "remote-version")
        let fallbackMetadata = await resolver.localPlaybackMetadata(for: item, versionID: "remote-version")
        let fallbackSubtitles = await resolver.localSubtitleTracks(for: item, versionID: "remote-version")
        XCTAssertEqual(fallback, selectedURL)
        XCTAssertEqual(fallbackMetadata, metadata)
        XCTAssertEqual(fallbackSubtitles, subtitles)
        let asset = await resolver.localPlaybackAsset(for: item, versionID: "remote-version")
        XCTAssertEqual(asset?.fileURL, selectedURL)
        XCTAssertEqual(asset?.metadata, metadata)
        XCTAssertEqual(asset?.subtitleTracks, subtitles)
    }

    func testLegacyStrongIdentityDoesNotIntroduceAnUnverifiedTitleMatch() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, resolver) = makeResolver(root: root)
        let record = try DownloadTestFactory.record(status: .completed)
        _ = try await registry.beginDownload(record)
        _ = try pin(record, root: root)
        let item = MediaItem(
            id: "unrelated", title: record.snapshot.title, kind: .movie,
            productionYear: record.snapshot.year
        )
        let resolved = await resolver.localPlaybackURL(for: item)
        XCTAssertNil(resolved)
    }

    func testMergedSourceReferencesFindARecordedCopyWithoutProviderIDs() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, resolver) = makeResolver(root: root)
        let downloaded = MediaItem(
            id: "downloaded", title: "Movie", kind: .movie, sourceAccountID: "archive"
        )
        let record = DownloadedMediaRecord(
            identity: try XCTUnwrap(DownloadMediaIdentity.primary(for: downloaded)),
            versionID: "original", sourceKind: .directShare, status: .completed,
            localFileName: "media.mkv", snapshot: .init(item: downloaded)
        )
        _ = try await registry.beginDownload(record)
        let localURL = try pin(record, root: root)
        var opened = MediaItem(
            id: "online", title: "Movie", kind: .movie, sourceAccountID: "server"
        )
        opened.sources = [.init(accountID: "archive", itemID: "downloaded", kind: .movie)]
        let resolved = await resolver.localPlaybackURL(for: opened, versionID: "stream")
        XCTAssertEqual(resolved, localURL)
        opened.sources[0].kind = .series
        let crossKind = await resolver.localPlaybackURL(for: opened, versionID: "stream")
        XCTAssertNil(crossKind)
    }

    func testDoesNotMatchCollidingItemIDsAcrossAccountsOrContradictoryProviderIDs() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, resolver) = makeResolver(root: root)
        var downloaded = DownloadTestFactory.movie()
        downloaded.sourceAccountID = "first-account"
        downloaded.providerIDs["Tmdb"] = "603"
        var record = try DownloadTestFactory.record(versionID: "shared-version", status: .completed)
        record.snapshot = PinnedMediaSnapshot(item: downloaded)
        _ = try await registry.beginDownload(record)
        _ = try pin(record, root: root)

        var collision = MediaItem(
            id: downloaded.id, title: "Different movie", kind: .movie,
            sourceAccountID: "second-account"
        )
        let unrelated = await resolver.localPlaybackURL(for: collision, versionID: "shared-version")
        XCTAssertNil(unrelated)

        collision.providerIDs = ["imdb": "tt0133093", "tmdb": "999"]
        let conflicting = await resolver.localPlaybackURL(for: collision, versionID: "shared-version")
        XCTAssertNil(conflicting)
        collision = downloaded
        collision.kind = .series
        let differentKind = await resolver.localPlaybackURL(for: collision, versionID: "shared-version")
        XCTAssertNil(differentKind)
    }

    func testEpisodeMatchingPreservesSeasonAndEpisodeBoundaries() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, resolver) = makeResolver(root: root)
        var downloaded = MediaItem(
            id: "plex-episode", title: "Pilot", kind: .episode,
            seasonNumber: 1, episodeNumber: 1,
            providerIDs: ["SeriesTvdb": "81189"], sourceAccountID: "plex-account"
        )
        let record = DownloadedMediaRecord(
            identity: try XCTUnwrap(DownloadMediaIdentity.primary(for: downloaded)),
            versionID: "plex-1080", sourceKind: .managedHTTP, status: .completed,
            localFileName: "media.mkv", snapshot: .init(item: downloaded)
        )
        _ = try await registry.beginDownload(record)
        let localURL = try pin(record, root: root)
        downloaded.id = "jellyfin-episode"
        downloaded.sourceAccountID = "jellyfin-account"
        let sameEpisode = await resolver.localPlaybackURL(for: downloaded, versionID: "jellyfin-4k")
        XCTAssertEqual(sameEpisode, localURL)
        downloaded.episodeNumber = 2
        let nextEpisode = await resolver.localPlaybackURL(for: downloaded, versionID: "jellyfin-4k")
        XCTAssertNil(nextEpisode)
        downloaded.seasonNumber = 2
        downloaded.episodeNumber = 1
        let nextSeason = await resolver.localPlaybackURL(for: downloaded, versionID: "jellyfin-4k")
        XCTAssertNil(nextSeason)
    }

    func testAnotherProfilesFileIsNotAnEligibleDownload() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, _) = makeResolver(root: root)
        let record = try DownloadTestFactory.record(status: .completed)
        _ = try await registry.beginDownload(record)
        _ = try pin(record, root: root)
        let (_, otherProfile) = makeResolver(root: root)
        let resolved = await otherProfile.localPlaybackURL(for: DownloadTestFactory.movie())
        XCTAssertNil(resolved)
    }

    func testReturnsLocalURLForCompletedDownloadWithFileOnDisk() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, resolver) = makeResolver(root: root)
        let storage = FixedDownloadStorageLocator(root: root)
        let identity = DownloadTestFactory.imdbIdentity("tt1375666")

        let record = try DownloadTestFactory.record(identity: identity, status: .completed)
        _ = try await registry.beginDownload(record)
        try await registry.markCompleted(identityKey: record.identityKey, totalBytes: 100)

        // Materialize the pinned file.
        let fileURL = try storage.pinnedFileURL(for: record)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("movie".utf8).write(to: fileURL)

        let item = DownloadTestFactory.movie(imdb: "tt1375666", title: "Inception")
        let resolved = await resolver.localPlaybackURL(for: item)
        XCTAssertEqual(resolved, fileURL)
    }

    func testReturnsNilWhenDownloadNotCompleted() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, resolver) = makeResolver(root: root)
        let identity = DownloadTestFactory.imdbIdentity("tt1375666")
        _ = try await registry.beginDownload(
            try DownloadTestFactory.record(identity: identity, status: .downloading)
        )

        let item = DownloadTestFactory.movie(imdb: "tt1375666")
        let resolved = await resolver.localPlaybackURL(for: item)
        XCTAssertNil(resolved)
    }

    func testReturnsNilWhenFileMissingEvenIfMarkedCompleted() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, resolver) = makeResolver(root: root)
        let identity = DownloadTestFactory.imdbIdentity("tt1375666")
        let record = try DownloadTestFactory.record(identity: identity, status: .completed)
        _ = try await registry.beginDownload(record)
        try await registry.markCompleted(identityKey: record.identityKey, totalBytes: 100)
        // Deliberately DO NOT create the file on disk.

        let item = DownloadTestFactory.movie(imdb: "tt1375666")
        let resolved = await resolver.localPlaybackURL(for: item)
        XCTAssertNil(resolved)
    }

    func testReturnsNilForUnknownItem() async throws {
        let root = DownloadTestFactory.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, resolver) = makeResolver(root: root)
        let item = DownloadTestFactory.movie(imdb: "tt9999999")
        let resolved = await resolver.localPlaybackURL(for: item)
        XCTAssertNil(resolved)
    }
}
