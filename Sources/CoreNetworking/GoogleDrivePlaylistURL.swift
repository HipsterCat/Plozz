import Foundation

/// Resolves public file links without fetching a viewer page or accepting a download warning.
public enum GoogleDrivePlaylistURL {
    public static func downloadURL(for url: URL) -> URL {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.host?.lowercased() == "drive.google.com",
              parts.port == nil || parts.port == 443,
              parts.user == nil, parts.password == nil else { return url }

        let query = parts.queryItems ?? []
        let allowed: Set<String> = ["id", "export", "resourcekey", "confirm", "uuid", "usp", "authuser"]
        guard query.allSatisfy({ allowed.contains($0.name) }),
              Set(query.map(\.name)).count == query.count else { return url }

        let identifier: String?
        if parts.path == "/uc" || parts.path == "/open" {
            identifier = query.first { $0.name == "id" }?.value
        } else {
            var path = parts.path.split(separator: "/", omittingEmptySubsequences: false)
            if path.last == "" { path.removeLast() }
            guard path.first == "", path.count >= 4, path[1] == "file" else { return url }
            path.removeFirst(2)
            if path.first == "u" {
                guard path.count >= 4, !path[1].isEmpty,
                      path[1].utf8.allSatisfy({ (48...57).contains($0) }) else { return url }
                path.removeFirst(2)
            }
            guard (path.count == 2 || (path.count == 3 && ["view", "edit", "preview"].contains(path[2]))),
                  path[0] == "d" else { return url }
            identifier = String(path[1])
            if let queryID = query.first(where: { $0.name == "id" }), queryID.value != identifier { return url }
        }
        guard let identifier, !identifier.isEmpty,
              identifier.utf8.allSatisfy({
                  (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
              }) else { return url }

        var download = URLComponents()
        download.scheme = "https"
        download.host = "drive.usercontent.google.com"
        download.path = "/download"
        download.queryItems = [
            URLQueryItem(name: "id", value: identifier),
            URLQueryItem(name: "export", value: "download")
        ] + query.filter { ["resourcekey", "confirm", "uuid"].contains($0.name) }
        return download.url ?? url
    }
}
