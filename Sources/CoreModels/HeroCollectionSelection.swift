import Foundation

/// A provider-local collection, qualified by the profile's account and server viewer.
public struct HeroCollectionSelection: Codable, Hashable, Sendable, Identifiable {
    public struct ID: Hashable, Sendable {
        public let accountID: String
        public let libraryID: String?
        public let collectionID: String
        public let serverUserID: String?
    }

    public let accountID: String
    /// Nil for a personal collection spanning the viewer's accessible libraries.
    public let libraryID: String?
    public let collectionID: String
    public let serverUserID: String?
    public let title: String // l10n:content — collection name from the server

    public var libraryKey: String? { libraryID.map { "\(accountID):\($0)" } }
    public var id: ID {
        ID(accountID: accountID, libraryID: libraryID, collectionID: collectionID, serverUserID: serverUserID)
    }

    public static func normalized(_ selections: [Self]) -> [Self] {
        var seen = Set<ID>()
        return selections.filter { seen.insert($0.id).inserted }
    }

    public init(
        accountID: String, libraryID: String? = nil, collectionID: String, title: String,
        serverUserID: String? = nil
    ) {
        self.accountID = accountID
        self.libraryID = libraryID
        self.collectionID = collectionID
        self.serverUserID = serverUserID
        self.title = title
    }

    public func matches(_ account: ResolvedAccount) -> Bool {
        accountID == account.account.id
            && (serverUserID == nil || serverUserID == (account.plexHomeUserID ?? account.provider.session.userID))
    }
}
