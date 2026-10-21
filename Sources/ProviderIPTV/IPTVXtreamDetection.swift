import CoreModels
import CoreNetworking
import Foundation

enum IPTVXtreamDetection {
    static func candidate(for credential: IPTVCredential) throws -> IPTVCredential? {
        guard credential.mode == .playlist,
              let parts = URLComponents(url: credential.address, resolvingAgainstBaseURL: false),
              credential.address.pathExtension.isEmpty
                || ["get.php", "player_api.php"].contains(credential.address.lastPathComponent.lowercased()) else {
            return nil
        }
        let users = (parts.queryItems ?? []).filter { $0.name.lowercased() == "username" }
        let passwords = (parts.queryItems ?? []).filter { $0.name.lowercased() == "password" }
        let supplied = suppliedLogin(credential)
        let login: (username: String, password: String)
        if !users.isEmpty || !passwords.isEmpty {
            guard users.count == 1, passwords.count == 1,
                  let username = users[0].value, !username.isEmpty,
                  let password = passwords[0].value, !password.isEmpty,
                  supplied.map({ $0.username == username && $0.password == password }) != false else { return nil }
            login = (username, password)
        } else {
            guard let supplied else { return nil }
            login = supplied
        }
        return try IPTVCredential(
            mode: .xtream, address: credential.address, username: login.username, password: login.password,
            headers: credential.headers, guideURL: credential.explicitGuideURLs.first,
            additionalGuideURLs: Array(credential.explicitGuideURLs.dropFirst()),
            guideHeaders: credential.explicitGuideHeaders,
            discoversPlaylistGuides: credential.automaticallyDiscoversGuides
        )
    }

    static func isAPIEndpoint(_ address: URL) -> Bool {
        address.lastPathComponent.lowercased() == "player_api.php"
    }

    static func permitsFallback(after error: any Error) -> Bool {
        switch error {
        case LiveTVSourceImportError.invalidPlaylist, LiveTVSourceImportError.emptyPlaylist,
             AppError.notFound, IPTVError.unsupported:
            true
        default:
            false
        }
    }

    private static func suppliedLogin(_ credential: IPTVCredential) -> (username: String, password: String)? {
        if let authorization = credential.headers.first(where: { $0.key.lowercased() == "authorization" })?.value {
            guard authorization.lowercased().hasPrefix("basic "),
                  let data = Data(base64Encoded: String(authorization.dropFirst(6))),
                  let text = String(data: data, encoding: .utf8), let colon = text.firstIndex(of: ":") else { return nil }
            let username = String(text[..<colon])
            let password = String(text[text.index(after: colon)...])
            guard !username.isEmpty, !password.isEmpty else { return nil }
            return (username, password)
        }
        guard !credential.username.isEmpty, !credential.password.isEmpty else { return nil }
        return (credential.username, credential.password)
    }
}
