import Foundation
import CoreModels

/// A short-lived request to receive setup from the screen showing this QR.
/// It locates a receiver through Bonjour; the existing SAS exchange authenticates
/// the devices before the source sends anything secret.
public struct SyncSetupSourceInvite: Hashable, Sendable {
    public static let lifetime: TimeInterval = 180
    public let requestID: UUID
    public let expiresAtEpoch: Int

    public init(requestID: UUID = UUID(), now: Date = Date()) {
        self.requestID = requestID
        expiresAtEpoch = Int(now.timeIntervalSince1970 + Self.lifetime)
    }

    private init(requestID: UUID, expiresAtEpoch: Int) {
        self.requestID = requestID
        self.expiresAtEpoch = expiresAtEpoch
    }

    public func isUsable(now: Date = Date()) -> Bool {
        let remaining = TimeInterval(expiresAtEpoch) - now.timeIntervalSince1970
        return remaining > 0 && remaining <= Self.lifetime
    }

    public func encoded(installation: AppInstallation = .current) -> String {
        "\(installation.pairingURLPrefix)receive=\(requestID.uuidString)&expires=\(expiresAtEpoch)"
    }

    public static func decode(
        _ string: String, installation: AppInstallation = .current
    ) -> Self? {
        let prefixes = installation.firstRunCaseID == nil
            ? [installation.pairingURLPrefix, SyncPairingInvite.legacyScheme]
            : [installation.pairingURLPrefix]
        guard let prefix = prefixes.first(where: { string.hasPrefix($0) }) else { return nil }
        let parts = string.dropFirst(prefix.count).split(separator: "&", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].hasPrefix("receive="), parts[1].hasPrefix("expires="),
              let requestID = UUID(uuidString: String(parts[0].dropFirst("receive=".count))),
              let expiresAtEpoch = Int(parts[1].dropFirst("expires=".count)) else { return nil }
        return Self(requestID: requestID, expiresAtEpoch: expiresAtEpoch)
    }
}
