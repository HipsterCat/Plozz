import Foundation

/// Only GET delivery may leave the DAV root. Browsing retains RedirectPolicy.
enum WebDAVMediaRedirectPolicy {
    static let maximumRedirects = 5
    static let statuses: Set<Int> = [301, 302, 303, 307, 308]

    static func validateRootURL(_ url: URL, root: WebDAVRoot) throws {
        guard TransportOrigin(url: url) == root.origin, url.fragment == nil,
              let path = WebDAVPathPolicy.normalizedPath(of: url),
              WebDAVPathPolicy.isWithinRoot(path, root: root.path) else {
            throw TransportError.pathEscapesRoot
        }
    }

    static func target(
        location: String,
        previous: URL,
        root: WebDAVRoot,
        alreadyAnonymous: Bool
    ) throws -> (url: URL, anonymous: Bool) {
        guard let url = URL(string: location, relativeTo: previous)?.absoluteURL,
              let origin = TransportOrigin(url: url),
              let previousOrigin = TransportOrigin(url: previous),
              url.fragment == nil else {
            throw TransportError.invalidOrigin(reason: "invalid media redirect")
        }
        if previousOrigin.isSecure && !origin.isSecure {
            throw TransportError.insecureRedirectDowngradeRejected(
                from: previousOrigin.displayString, to: origin.displayString
            )
        }
        if origin == root.origin {
            try validateRootURL(url, root: root)
            return (url, alreadyAnonymous)
        }
        // External delivery is limited to HTTPS DNS hosts with system TLS trust.
        // IP literals and local/special-use hostnames are not CDN destinations.
        let host = origin.host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = host.split(separator: ".")
        let localSuffixes = [".local", ".localhost", ".localdomain", ".internal", ".lan", ".home", ".home.arpa"]
        guard previousOrigin.isSecure, origin.isSecure,
              labels.count >= 2, !host.contains(":"),
              labels.last?.rangeOfCharacter(from: .letters) != nil,
              !localSuffixes.contains(where: { host.hasSuffix($0) }) else {
            throw TransportError.crossOriginRedirectRejected(
                from: previousOrigin.displayString, to: origin.displayString
            )
        }
        return (url, true)
    }
}
