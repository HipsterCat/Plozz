import Foundation

public struct MediaShareWorkScope: Equatable, Sendable {
    public var profileID: String?
    public var accountKeys: Set<String>

    public init(profileID: String?, accountKeys: Set<String>) {
        self.profileID = profileID
        self.accountKeys = accountKeys
    }

    public static let paused = Self(profileID: nil, accountKeys: [])
}
