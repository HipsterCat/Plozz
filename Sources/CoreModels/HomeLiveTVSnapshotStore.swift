import CryptoKit
import Foundation
#if canImport(OSLog)
import OSLog
#endif

public protocol HomeLiveTVSnapshotStoring: Sendable {
    func load() -> HomeLiveTVSnapshot
    func save(_ snapshot: HomeLiveTVSnapshot)
}

/// A local, disposable cache of at most eleven cards, separate from preferences,
/// the encrypted lineup and portable sync. Reads are capped before JSON decoding.
public final class HomeLiveTVSnapshotStore: HomeLiveTVSnapshotStoring, @unchecked Sendable {
    public static let maximumBytes = 64 * 1_024
    private let profileID: String
    private let url: URL?
    private let secureStore: (any SecureStoring)?
    private let keyName: String
    private let lock = NSLock()
    private static let encryptedHeader = Data("PHL2".utf8)
    private enum CacheError: Error { case missingKey, invalidKey, invalidCiphertext }
    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "com.plozz.app", category: "home-live-tv")
    #endif

    private struct Document: Codable {
        var version = 1
        let profileID: String
        let recentChannels: [HomeLiveTVChannel]
        let channels: [HomeLiveTVChannel]
    }

    public init(
        profileID: String, directory: URL? = HomeLiveTVSnapshotStore.defaultDirectory(),
        secureStore: (any SecureStoring)? = nil
    ) {
        self.profileID = profileID
        self.secureStore = secureStore
        let name = SHA256.hash(data: Data(profileID.utf8)).map { String(format: "%02x", $0) }.joined()
        keyName = "liveTV.home." + name + ".key"
        url = directory?.appendingPathComponent(name).appendingPathExtension("json")
    }

    public static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Plozz/HomeLiveTV-v1", isDirectory: true)
    }

    public func load() -> HomeLiveTVSnapshot {
        lock.lock()
        defer { lock.unlock() }
        guard let url, let handle = try? FileHandle(forReadingFrom: url) else { return .empty }
        defer { try? handle.close() }
        do {
            let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
            guard data.count <= Self.maximumBytes else { return .empty }
            let encrypted = data.starts(with: Self.encryptedHeader)
            let plaintext = encrypted ? try AES.GCM.open(
                AES.GCM.SealedBox(combined: Data(data.dropFirst(Self.encryptedHeader.count))),
                using: encryptionKey(create: false), authenticating: Data(keyName.utf8)
            ) : data
            let document = try JSONDecoder().decode(Document.self, from: plaintext)
            guard isValid(document),
                  encrypted || !(document.recentChannels + document.channels).contains(where: { $0.logoURL != nil })
            else { return .empty }
            return HomeLiveTVSnapshot(recentChannels: document.recentChannels, channels: document.channels)
        } catch {
            #if canImport(OSLog)
            Self.logger.notice("Home Live TV cache could not be restored.")
            #endif
            return .empty
        }
    }

    public func save(_ snapshot: HomeLiveTVSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        guard let url else { return }
        if snapshot.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let document = Document(
            profileID: profileID, recentChannels: snapshot.recentChannels, channels: snapshot.channels
        )
        guard isValid(document) else { return }
        do {
            var data = try JSONEncoder().encode(document)
            if (document.recentChannels + document.channels).contains(where: { $0.logoURL != nil }) {
                guard let sealed = try AES.GCM.seal(
                    data, using: encryptionKey(create: true), authenticating: Data(keyName.utf8)
                ).combined else { throw CacheError.invalidCiphertext }
                data = Self.encryptedHeader + sealed
            }
            guard data.count <= Self.maximumBytes else { return }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            #if canImport(OSLog)
            Self.logger.error("Home Live TV cache could not be saved.")
            #endif
        }
    }

    private func encryptionKey(create: Bool) throws -> SymmetricKey {
        guard let secureStore else { throw CacheError.missingKey }
        if let stored = try secureStore.readString(for: keyName) {
            guard let data = Data(base64Encoded: stored), data.count == 32 else { throw CacheError.invalidKey }
            return SymmetricKey(data: data)
        }
        guard create else { throw CacheError.missingKey }
        let key = SymmetricKey(size: .bits256)
        try secureStore.setString(key.withUnsafeBytes { Data($0) }.base64EncodedString(), for: keyName)
        return key
    }

    private func isValid(_ document: Document) -> Bool {
        guard document.version == 1, document.profileID == profileID,
              document.recentChannels.count <= HomeLiveTVSnapshot.maximumRecentCount,
              document.channels.count <= HomeLiveTVSnapshot.maximumRowCount,
              Set(document.recentChannels.map(\.id)).count == document.recentChannels.count,
              Set(document.channels.map(\.id)).count == document.channels.count else { return false }
        let cards = document.recentChannels + document.channels
        guard Set(cards.map(\.route.sourceAuthorizationID)).count <= 1,
              Set(cards.map(\.route.serverAuthorizationID)).count <= 1 else { return false }
        return cards.allSatisfy { card in
            let route = card.route
            return route.profileID == profileID
                && !route.profileID.isEmpty && route.profileID.utf8.count <= 256
                && !route.channelID.isEmpty && route.channelID.utf8.count <= 1_024
                && !route.sourceID.isEmpty && route.sourceID.utf8.count <= 256
                && (route.accountID.map { !$0.isEmpty && $0.utf8.count <= 256 } ?? true)
                && !route.sourceAuthorizationID.isEmpty && route.sourceAuthorizationID.utf8.count <= 1_024
                && !route.serverAuthorizationID.isEmpty && route.serverAuthorizationID.utf8.count <= 8_192
                && !card.name.isEmpty && card.name.count <= 160 && card.name.utf8.count <= 1_024
                && card.sourceName.count <= 160 && card.sourceName.utf8.count <= 1_024
                && (card.logoURL.map { $0.absoluteString.utf8.count <= 8_192 } ?? true)
        }
    }
}
