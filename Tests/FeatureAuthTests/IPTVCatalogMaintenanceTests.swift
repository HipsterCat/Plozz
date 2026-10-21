import CoreModels
import Foundation
import ProviderIPTV
import XCTest
@testable import FeatureAuthCore

final class IPTVCatalogMaintenanceTests: XCTestCase {
    private final class FailingStore: SecureStore, @unchecked Sendable {
        let base = InMemorySecureStore()
        var failingKey: String?
        func readString(for key: String) throws -> String? {
            if key == failingKey { throw AppError.unauthorized }
            return try base.readString(for: key)
        }
        func string(for key: String) -> String? { base.string(for: key) }
        func setString(_ value: String, for key: String) throws { try base.setString(value, for: key) }
        func insertStringIfAbsent(_ value: String, for key: String) throws -> Bool {
            try base.insertStringIfAbsent(value, for: key)
        }
        func removeValue(for key: String) throws { try base.removeValue(for: key) }
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private func credential() throws -> IPTVCredential {
        try IPTVCredential(mode: .playlist, address: XCTUnwrap(URL(string: "https://iptv.invalid/playlist")))
    }

    private func account(_ id: String) throws -> Account {
        Account(
            id: id,
            server: MediaServer(id: id, name: "IPTV", baseURL: try XCTUnwrap(URL(string: "https://iptv.invalid")),
                                provider: .iptv),
            userID: id, userName: "IPTV", deviceID: "test"
        )
    }

    private func cache(_ credential: IPTVCredential, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(credential.identity.uuidString + ".sqlite")
        try Data([1]).write(to: url)
        let old = Date(timeIntervalSinceNow: -172_800)
        try FileManager.default.setAttributes([.creationDate: old, .modificationDate: old], ofItemAtPath: url.path)
        return url
    }

    func testCompleteHouseholdInventoryProtectsDisabledAccountsAndSharedCatalogs() throws {
        let root = try directory()
        let secure = InMemorySecureStore()
        let store = AccountStore(secureStore: secure)
        let saved = try credential()
        let url = try cache(saved, in: root)
        let orphan = try cache(credential(), in: root)
        try store.add(account("first"), token: saved.encoded())
        try store.add(account("second"), token: saved.encoded())
        store.setActiveAccountIDs([])
        try store.remove(id: "first")
        try store.maintainIPTVCatalogs(directory: root, inventoryStore: secure)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        try store.remove(id: "second")
        try store.maintainIPTVCatalogs(directory: root, inventoryStore: secure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testMissingMalformedOrUnavailableCredentialsNeverAuthorizeDeletion() throws {
        let root = try directory()
        let secure = FailingStore()
        let store = AccountStore(secureStore: secure)
        let saved = try credential()
        let url = try cache(saved, in: root)
        let orphan = try cache(credential(), in: root)
        try store.add(account("saved"), token: saved.encoded())
        for key in ["com.plozz.accounts.v2", "com.plozz.account.token.saved"] {
            secure.failingKey = key
            XCTAssertThrowsError(try store.maintainIPTVCatalogs(directory: root, inventoryStore: secure))
            XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        }
        secure.failingKey = nil
        try secure.removeValue(for: "com.plozz.account.token.saved")
        XCTAssertThrowsError(try store.maintainIPTVCatalogs(directory: root, inventoryStore: secure))
        try secure.setString("not-a-credential", for: "com.plozz.account.token.saved")
        XCTAssertThrowsError(try store.maintainIPTVCatalogs(directory: root, inventoryStore: secure))
        try secure.setString("not-an-account-list", for: "com.plozz.accounts.v2")
        XCTAssertThrowsError(try store.maintainIPTVCatalogs(directory: root, inventoryStore: secure))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testExplicitRemovalReclaimsRecentCacheButNotAReRegisteredCredential() throws {
        let root = try directory()
        let secure = InMemorySecureStore()
        let store = AccountStore(secureStore: secure)
        let saved = try credential()
        let url = root.appendingPathComponent(saved.identity.uuidString + ".sqlite")
        try Data([1]).write(to: url)
        try store.add(account("saved"), token: saved.encoded())
        try store.remove(id: "saved")
        try store.add(account("restored"), token: saved.encoded())
        try store.maintainIPTVCatalogs(directory: root, inventoryStore: secure)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try store.remove(id: "restored")
        try store.maintainIPTVCatalogs(directory: root, inventoryStore: secure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testMaintenanceBeforeHouseholdPromotionPreservesLegacyAccountCache() throws {
        let root = try directory()
        let legacy = InMemorySecureStore()
        let household = InMemorySecureStore()
        let store = AccountStore(secureStore: legacy)
        let saved = try credential()
        let url = try cache(saved, in: root)
        let orphan = try cache(credential(), in: root)
        try store.add(account("saved"), token: saved.encoded())

        XCTAssertThrowsError(try store.maintainIPTVCatalogs(directory: root, inventoryStore: household))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))

        try household.setString(
            XCTUnwrap(legacy.readString(for: "com.plozz.accounts.v2")), for: "com.plozz.accounts.v2"
        )
        XCTAssertThrowsError(try store.maintainIPTVCatalogs(directory: root, inventoryStore: household))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))

        try household.setString(saved.encoded(), for: "com.plozz.account.token.saved")
        try store.maintainIPTVCatalogs(directory: root, inventoryStore: household)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testCredentialReplacementReclaimsOldCacheWithoutTouchingImportedFiles() throws {
        let root = try directory()
        let cacheDirectory = root.appendingPathComponent("Caches")
        let importsDirectory = root.appendingPathComponent("Application Support")
        for directory in [cacheDirectory, importsDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let secure = InMemorySecureStore()
        let store = AccountStore(secureStore: secure)
        let old = try credential()
        let replacement = try credential()
        let oldURL = try cache(old, in: cacheDirectory)
        let newURL = try cache(replacement, in: cacheDirectory)
        let imported = try cache(credential(), in: importsDirectory)
        try store.add(account("saved"), token: old.encoded())
        try store.add(account("saved"), token: replacement.encoded())
        try store.maintainIPTVCatalogs(directory: cacheDirectory, inventoryStore: secure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.path))
    }

    func testBackgroundMaintenanceRunsAtStartupAndAfterRemoval() async throws {
        let root = try directory()
        let secure = InMemorySecureStore()
        let store = AccountStore(secureStore: secure)
        let saved = try credential()
        let url = try cache(saved, in: root)
        let orphan = try cache(credential(), in: root)
        try store.add(account("saved"), token: saved.encoded())
        store.enableIPTVCatalogMaintenance(directory: root, inventoryStore: secure)
        try await waitForRemoval(orphan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try store.remove(id: "saved")
        try await waitForRemoval(url)
    }

    private func waitForRemoval(_ url: URL) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while FileManager.default.fileExists(atPath: url.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
