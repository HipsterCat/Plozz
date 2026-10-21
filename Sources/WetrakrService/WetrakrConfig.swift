import CoreModels
import Foundation

public struct WetrakrConfig: Sendable, Equatable {
    public var clientID: String?
    public var apiBaseURL: URL
    public var redirectURI: URL

    public init(
        clientID: String? = nil,
        apiBaseURL: URL = URL(string: "https://api.wetrakr.com")!,
        redirectURI: URL = URL(string: "https://plozz.app/auth/wetrakr/callback")!
    ) {
        self.clientID = Self.sanitize(clientID)
        self.apiBaseURL = apiBaseURL
        self.redirectURI = redirectURI
    }

    public var isConfigured: Bool { clientID != nil }

    public static func resolved(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        featureFlags: RuntimeFeatureFlags = .buildDefault
    ) -> Self {
        guard featureFlags.isEnabled(.wetrakr) else { return Self() }
        return Self(clientID: sanitize(bundle.object(forInfoDictionaryKey: "WetrakrClientID") as? String)
            ?? sanitize(environment["WETRAKR_CLIENT_ID"]))
    }

    private static func sanitize(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}
