import CoreModels
import Foundation
import XCTest

final class HomeLiveTVSnapshotStoreTests: XCTestCase {
    private func directory() throws -> URL {
        let base = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let directory = base.appendingPathComponent("HomeLiveTVSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func channel(_ id: String, profileID: String = "profile") -> HomeLiveTVChannel {
        .init(
            route: .init(
                profileID: profileID, channelID: id, sourceID: "playlist",
                sourceAuthorizationID: "approval-digest", serverAuthorizationID: "credential-scope-digest"
            ), name: id, sourceName: "Playlist", number: 1
        )
    }

    @MainActor
    func testRelaunchHydratesSelectedCardsButNeverRestoresAPendingTune() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let all = (0..<100).map { channel(String($0)) }
        let selected = HomeLiveTVSnapshot(recentChannels: all, channels: Array(all.reversed()))
        let first = HomeLiveTVModel(
            profileID: "profile", store: HomeLiveTVSnapshotStore(profileID: "profile", directory: directory)
        )
        first.publish(selected)
        XCTAssertTrue(first.request(all[0].route, in: selected))

        let relaunched = HomeLiveTVModel(
            profileID: "profile", store: HomeLiveTVSnapshotStore(profileID: "profile", directory: directory)
        )
        XCTAssertEqual(relaunched.snapshot, selected)
        XCTAssertEqual(relaunched.snapshot.recentChannels.count, 3)
        XCTAssertEqual(relaunched.snapshot.channels.count, 8)
        XCTAssertNil(relaunched.pendingRequest)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let bytes = try Data(contentsOf: XCTUnwrap(files.first))
        XCTAssertLessThan(bytes.count, HomeLiveTVSnapshotStore.maximumBytes)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual((document["recentChannels"] as? [Any])?.count, 3)
        XCTAssertEqual((document["channels"] as? [Any])?.count, 8)
        XCTAssertNil(document["pendingRequest"])
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("streamURL"))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("logoURL"))

        relaunched.publish(.empty)
        XCTAssertTrue(HomeLiveTVSnapshotStore(profileID: "profile", directory: directory).load().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testOtherProfileCannotLoadOrBeWrittenIntoThisCache() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = HomeLiveTVSnapshot(channels: [channel("one")])
        let first = HomeLiveTVSnapshotStore(profileID: "profile", directory: directory)
        first.save(snapshot)
        let other = HomeLiveTVSnapshotStore(profileID: "other", directory: directory)
        XCTAssertTrue(other.load().isEmpty)
        other.save(snapshot)
        XCTAssertTrue(other.load().isEmpty)
        XCTAssertEqual(first.load(), snapshot)
    }

    func testMissingSnapshotReadDoesNotCreateStorage() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("not-created", isDirectory: true)
        let store = HomeLiveTVSnapshotStore(profileID: "profile", directory: missing)
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testCorruptOversizedFutureAndOverfullDocumentsAreCacheMisses() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HomeLiveTVSnapshotStore(profileID: "profile", directory: directory)
        let snapshot = HomeLiveTVSnapshot(recentChannels: [channel("one")], channels: [channel("one")])
        store.save(snapshot)
        let url = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).first)
        let valid = try Data(contentsOf: url)
        for bytes in [
            Data("not-json".utf8),
            Data(repeating: 32, count: HomeLiveTVSnapshotStore.maximumBytes + 1)
        ] {
            try bytes.write(to: url, options: .atomic)
            XCTAssertTrue(HomeLiveTVSnapshotStore(profileID: "profile", directory: directory).load().isEmpty)
        }
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        for key in ["version", "profileID", "recentChannels", "channels"] {
            var document = original
            switch key {
            case "version": document[key] = 99
            case "profileID": document[key] = "different-profile"
            case "recentChannels":
                document[key] = Array(repeating: try XCTUnwrap((original[key] as? [Any])?.first), count: 4)
            default:
                document[key] = Array(repeating: try XCTUnwrap((original[key] as? [Any])?.first), count: 9)
            }
            try JSONSerialization.data(withJSONObject: document).write(to: url, options: .atomic)
            XCTAssertTrue(store.load().isEmpty, "\(key) must be rejected, not silently truncated.")
        }
        store.save(snapshot)
        XCTAssertEqual(store.load(), snapshot, "Normal catalog publication can repair a disposable cache.")
    }

    @MainActor
    func testReadOnlyHydrationDoesNotPublishPortableState() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profileID = UUID().uuidString
        let notification = expectation(description: "No portable-state initialization or publication")
        notification.isInverted = true
        let token = NotificationCenter.default.addObserver(
            forName: .plozzLiveTVPortableStateDidChange, object: nil, queue: nil
        ) { event in
            if event.object as? String == profileID { notification.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        let store = HomeLiveTVSnapshotStore(profileID: profileID, directory: directory)
        store.save(HomeLiveTVSnapshot(channels: [channel("one", profileID: profileID)]))
        XCTAssertFalse(HomeLiveTVModel(profileID: profileID, store: store).snapshot.isEmpty)
        wait(for: [notification], timeout: 0.02)
    }

    func testLogoURLsPersistOnlyInAuthenticatedCiphertextAndRestoreWithoutAKeyWrite() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = HomeArtworkSecrets()
        let original = channel("news")
        let card = HomeLiveTVChannel(
            route: original.route, name: original.name, sourceName: original.sourceName, number: original.number,
            logoURL: URL(string: "https://example.test/logo.png?token=artwork-credential")
        )
        let snapshot = HomeLiveTVSnapshot(recentChannels: [card], channels: [card])
        let store = HomeLiveTVSnapshotStore(profileID: "profile", directory: directory, secureStore: secrets)
        store.save(snapshot)
        let url = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).first)
        let data = try Data(contentsOf: url)
        XCTAssertLessThanOrEqual(data.count, HomeLiveTVSnapshotStore.maximumBytes)
        for text in ["artwork-credential", "example.test", "logoURL", "news"] {
            XCTAssertNil(data.range(of: Data(text.utf8)), "Artwork metadata must not be plaintext.")
            XCTAssertFalse(secrets.values.values.contains { $0.contains(text) }, "Only the encryption key belongs in Keychain.")
        }
        XCTAssertEqual(secrets.writeCount, 1)
        let relaunched = HomeLiveTVSnapshotStore(profileID: "profile", directory: directory, secureStore: secrets)
        XCTAssertEqual(relaunched.load(), snapshot)
        XCTAssertEqual(secrets.writeCount, 1, "Hydration must never create or replace a key.")

        var tampered = data
        tampered[tampered.count - 1] ^= 1
        try tampered.write(to: url)
        XCTAssertTrue(relaunched.load().isEmpty)
        try data.write(to: url)
        secrets.failRead = true
        XCTAssertTrue(relaunched.load().isEmpty)
        store.save(snapshot)
        XCTAssertEqual(try Data(contentsOf: url), data, "A locked key must not cause plaintext fallback or key replacement.")
        XCTAssertEqual(secrets.writeCount, 1)
        secrets.failRead = false
        XCTAssertEqual(relaunched.load(), snapshot)

        let missing = HomeArtworkSecrets()
        XCTAssertTrue(HomeLiveTVSnapshotStore(
            profileID: "profile", directory: directory, secureStore: missing
        ).load().isEmpty)
        XCTAssertEqual(missing.writeCount, 0)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testPlaintextArtworkIsRejectedAndMissingSecureStorageCannotWriteIt() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HomeLiveTVSnapshotStore(profileID: "profile", directory: directory)
        let original = channel("news")
        store.save(.init(channels: [original]))
        let url = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).first)
        let metadata = try Data(contentsOf: url)
        let card = HomeLiveTVChannel(
            route: original.route, name: original.name, sourceName: original.sourceName, number: original.number,
            logoURL: URL(string: "https://example.test/logo.png?token=artwork-credential")
        )
        store.save(.init(channels: [card]))
        XCTAssertEqual(try Data(contentsOf: url), metadata)
        XCTAssertEqual(store.load().channels, [original], "Existing URL-free metadata remains compatible.")
        var plaintext = try XCTUnwrap(JSONSerialization.jsonObject(with: metadata) as? [String: Any])
        plaintext["channels"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([card]))
        try JSONSerialization.data(withJSONObject: plaintext).write(to: url)
        XCTAssertTrue(store.load().isEmpty, "No plaintext artifact may introduce a credential-bearing image request.")
    }
}

private final class HomeArtworkSecrets: SecureStoring, @unchecked Sendable {
    var values: [String: String] = [:]
    var writeCount = 0
    var failRead = false

    func readString(for key: String) throws -> String? {
        if failRead { throw CocoaError(.fileReadNoPermission) }
        return values[key]
    }
    func string(for key: String) -> String? { values[key] }
    func setString(_ value: String, for key: String) throws {
        writeCount += 1
        values[key] = value
    }
    func removeValue(for key: String) throws { values[key] = nil }
}
