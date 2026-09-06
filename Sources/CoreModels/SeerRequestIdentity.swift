import Foundation

/// The endpoint whose Seerr user IDs a mapping belongs to, independent of its
/// API key. This cannot detect a database replacement behind the same URL.
public struct SeerServerIdentity: Codable, Hashable, Sendable {
    public let canonicalURL: String

    public init?(baseURL: URL) {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil
        else { return nil }

        components.scheme = scheme
        components.host = host
        if let port = components.port {
            guard (1...65535).contains(port) else { return nil }
            if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
                components.port = nil
            }
        }
        // Query/userinfo can contain secrets or change proxy routing. Refuse
        // those above rather than storing secrets or equating different routes.
        components.fragment = nil
        // A single terminal slash is optional. Repeated slashes can change
        // reverse-proxy routing and must also survive a Codable round trip.
        if components.percentEncodedPath.hasSuffix("/"),
           !components.percentEncodedPath.hasSuffix("//") {
            components.percentEncodedPath.removeLast()
        }
        guard let canonicalURL = components.url?.absoluteString else { return nil }
        self.canonicalURL = canonicalURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let url = URL(string: value), let identity = Self(baseURL: url) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid Seerr server identity."
            )
        }
        self = identity
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(canonicalURL)
    }
}

/// A missing server on a user identity is an unverified legacy mapping, not
/// permission to fall back to the household administrator.
public enum SeerRequestIdentity: Equatable, Sendable {
    case admin
    case user(id: Int, server: SeerServerIdentity?)

    public var userID: Int? {
        switch self {
        case .admin: return nil
        case let .user(id, _): return id
        }
    }

    public func requiresRelink(to server: SeerServerIdentity?) -> Bool {
        switch self {
        case .admin:
            return false
        case let .user(id, boundServer):
            guard id > 0, let boundServer, let server else { return true }
            return boundServer != server
        }
    }
}
