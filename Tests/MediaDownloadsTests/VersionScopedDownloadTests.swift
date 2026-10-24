import CoreModels
import XCTest
@testable import MediaDownloads

/// Download management keeps separate files independent; playback can prefer
/// one of these copies without requiring the selected server version on disk.
final class VersionScopedDownloadTests: XCTestCase {
    private func makeRegistry() -> DownloadedMediaRegistry {
        DownloadedMediaRegistry(store: InMemoryDownloadedMediaStore())
    }

    private func movieSelecting(_ versionID: String?) -> MediaItem {
        var item = DownloadTestFactory.movie(imdb: "tt1375666", title: "Inception")
        item.selectedVersionID = versionID
        return item
    }

    func testTwoVersionsOfOneTitleCoexist() async throws {
        let registry = makeRegistry()
        let identity = DownloadTestFactory.imdbIdentity("tt1375666")

        let uhd = try DownloadTestFactory.record(
            identity: identity, versionID: "v-4k", status: .completed
        )
        let hd = try DownloadTestFactory.record(
            identity: identity, versionID: "v-1080", status: .completed
        )
        _ = try await registry.beginDownload(uhd)
        _ = try await registry.beginDownload(hd)

        XCTAssertNotEqual(
            uhd.identityKey,
            hd.identityKey,
            "each version needs its own key, or one download overwrites the other"
        )
        let all = await registry.all()
        XCTAssertEqual(all.count, 2)
    }

    func testLookupReturnsTheSelectedVersionNotJustAnyDownloadedCopy() async throws {
        let registry = makeRegistry()
        let identity = DownloadTestFactory.imdbIdentity("tt1375666")

        let uhd = try DownloadTestFactory.record(
            identity: identity, versionID: "v-4k", status: .completed
        )
        let hd = try DownloadTestFactory.record(
            identity: identity, versionID: "v-1080", status: .completed
        )
        _ = try await registry.beginDownload(uhd)
        _ = try await registry.beginDownload(hd)

        let found = await registry.record(
            for: movieSelecting("v-1080"), versionID: "v-1080"
        )
        XCTAssertEqual(found?.identityKey, hd.identityKey)
    }

    /// Download controls must allow another version to be saved separately.
    func testUndownloadedVersionReportsNoLocalCopy() async throws {
        let registry = makeRegistry()
        let identity = DownloadTestFactory.imdbIdentity("tt1375666")

        let hd = try DownloadTestFactory.record(
            identity: identity, versionID: "v-1080", status: .completed
        )
        _ = try await registry.beginDownload(hd)

        let found = await registry.record(
            for: movieSelecting("v-4k"), versionID: "v-4k"
        )
        XCTAssertNil(
            found,
            "4K isn't downloaded, so its download control must not manage the 1080p file"
        )
    }

    /// "Is this title available offline at all?" must still see version-scoped
    /// copies, otherwise download badges and the offline library go blank.
    func testAnyVersionLookupStillFindsAVersionScopedDownload() async throws {
        let registry = makeRegistry()
        let identity = DownloadTestFactory.imdbIdentity("tt1375666")

        let uhd = try DownloadTestFactory.record(
            identity: identity, versionID: "v-4k", status: .completed
        )
        _ = try await registry.beginDownload(uhd)

        let found = await registry.record(for: movieSelecting(nil))
        XCTAssertEqual(found?.identityKey, uhd.identityKey)
    }

    /// Records with no version concept keep their historic un-suffixed key.
    func testVersionlessRecordsKeepTheirOriginalKey() {
        let identity = DownloadTestFactory.imdbIdentity("tt1375666")
        XCTAssertEqual(
            MediaIdentityKey.string(for: identity, versionID: nil),
            MediaIdentityKey.string(for: identity)
        )
        XCTAssertEqual(
            MediaIdentityKey.string(for: identity, versionID: ""),
            MediaIdentityKey.string(for: identity)
        )
    }
}
