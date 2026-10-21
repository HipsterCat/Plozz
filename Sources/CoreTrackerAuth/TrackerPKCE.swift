import CryptoKit
import Foundation
import CoreModels

public struct TrackerPKCE: Sendable {
    public enum CallbackError: String, Error, Sendable {
        case unexpectedEndpoint, unexpectedScheme, unexpectedHost, unexpectedPort
        case unexpectedPath, unexpectedUserInfo, unexpectedFragment
        case invalidState, invalidCode
    }

    public let verifier: String
    public let state: String
    public let redirectURI: URL
    public let authorizationURL: URL

    public init(
        clientID: String?,
        authorizationEndpoint: URL,
        redirectURI: URL,
        verifier: String = Self.randomValue(),
        state: String = Self.randomValue()
    ) throws {
        guard let clientID,
              redirectURI.scheme == "https",
              redirectURI.host != nil,
              redirectURI.user == nil, redirectURI.password == nil,
              redirectURI.query == nil, redirectURI.fragment == nil,
              (43...128).contains(verifier.utf8.count),
              verifier.utf8.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0)
                      || (48...57).contains($0) || [45, 46, 95, 126].contains($0)
              }),
              !state.isEmpty else { throw AppError.invalidResponse }
        self.verifier = verifier
        self.state = state
        self.redirectURI = redirectURI
        var components = URLComponents(
            url: authorizationEndpoint,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components?.url else { throw AppError.invalidResponse }
        authorizationURL = url
    }

    public func authorizationCode(from callback: URL) throws -> String {
        guard let actual = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let expected = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false)
        else { throw CallbackError.unexpectedEndpoint }
        guard actual.scheme == expected.scheme else { throw CallbackError.unexpectedScheme }
        guard actual.host == expected.host else { throw CallbackError.unexpectedHost }
        guard actual.port == expected.port else { throw CallbackError.unexpectedPort }
        guard actual.percentEncodedPath == expected.percentEncodedPath else { throw CallbackError.unexpectedPath }
        guard actual.user == nil, actual.password == nil else { throw CallbackError.unexpectedUserInfo }
        // WeTrakr's Google sign-in appends a bare "#", which carries no fragment data.
        if let fragment = actual.fragment, !fragment.isEmpty { throw CallbackError.unexpectedFragment }
        let items = actual.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state
        else { throw CallbackError.invalidState }
        if items.contains(where: { $0.name == "error" }) {
            throw AppError.cancelled
        }
        guard items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { throw CallbackError.invalidCode }
        return code
    }

    public static func randomValue() -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
