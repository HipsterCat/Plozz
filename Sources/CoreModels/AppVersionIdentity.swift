import Foundation

/// User-visible Plozz releases are independent of Apple's version series.
public struct AppVersionIdentity: Equatable, Sendable {
    public let marketingVersion: String
    public let build: String
    public let releaseVersion: String?

    public var displayVersion: String { releaseVersion ?? marketingVersion }

    public static var current: Self {
        Self(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    public init(infoDictionary: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let raw = infoDictionary[key] as? String else { return nil }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty || text.contains("$(") ? nil : text
        }
        marketingVersion = value("CFBundleShortVersionString") ?? "—"
        build = value("CFBundleVersion") ?? "—"
        releaseVersion = value("PlozzReleaseID") == nil ? nil : value("PlozzReleaseVersion")
    }
}
