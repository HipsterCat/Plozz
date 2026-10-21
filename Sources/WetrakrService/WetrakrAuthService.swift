import CoreModels
import CoreNetworking
import CoreTrackerAuth
import Foundation

struct WetrakrAuthService: TrackerTokenRefreshing {
    let client: WetrakrClient
    var now: @Sendable () -> Date = { Date() }
    var sleep: @Sendable (TimeInterval) async throws -> Void = {
        try await Task.sleep(for: .seconds($0))
    }

    func beginDeviceCode() async throws -> WetrakrDeviceCode {
        let result = try await client.decode(WetrakrDeviceCode.self, endpoint:
            Endpoint(method: .post, path: "/oauth/device/code").jsonBody(["client_id": client.config.clientID])
        )
        guard !result.deviceCode.isEmpty, !result.userCode.isEmpty,
              result.expiresIn.isFinite, result.expiresIn > 0,
              result.interval.isFinite, result.interval > 0,
              let url = URL(string: result.verificationURL),
              url.scheme == "https", url.host == "wetrakr.com",
              url.user == nil, url.password == nil
        else { throw AppError.invalidResponse }
        return result
    }

    func awaitToken(for code: WetrakrDeviceCode) async throws -> TrackerTokens {
        let deadline = now().addingTimeInterval(code.expiresIn)
        var interval = max(1, code.interval)
        while now() < deadline {
            try Task.checkCancellation()
            try await sleep(min(interval, max(0, deadline.timeIntervalSince(now()))))
            try Task.checkCancellation()
            guard now() < deadline else { break }
            do {
                return try await token(path: "/oauth/device/token", body: [
                    "client_id": client.config.clientID ?? "", "code": code.deviceCode,
                ])
            } catch WetrakrError.authorizationPending {
                continue
            } catch AppError.rateLimited(let delay) {
                interval = max(interval + 5, delay ?? 0)
            }
        }
        throw AppError.quickConnectExpired
    }

    func exchange(code: String, verifier: String) async throws -> TrackerTokens {
        do {
            return try await token(path: "/oauth/token", body: [
                "client_id": client.config.clientID ?? "", "code": code, "code_verifier": verifier,
            ])
        } catch AppError.decoding {
            throw WetrakrError.invalidTokenResponse
        } catch AppError.invalidResponse {
            throw WetrakrError.invalidTokenResponse
        }
    }

    func refresh(_ refreshToken: String) async throws -> TrackerTokens {
        try await token(path: "/oauth/token/refresh", body: ["refresh_token": refreshToken], oneTime: true)
    }

    private func token(path: String, body: [String: String], oneTime: Bool = false) async throws -> TrackerTokens {
        var endpoint = try Endpoint(method: .post, path: path).jsonBody(body)
        endpoint.reportsUndeliveredRequests = oneTime
        return try await client.decode(WetrakrTokenResponse.self, endpoint: endpoint).tokens(now: now())
    }

    func user(accessToken: String) async throws -> WetrakrUser {
        let user = try await client.decode(WetrakrUser.self, endpoint: Endpoint(path: "/account/settings"), accessToken: accessToken)
        guard user.id > 0, !user.info.username.isEmpty else { throw AppError.invalidResponse }
        return user
    }

    func revoke(_ tokens: TrackerTokens) async throws {
        struct Revocation: Decodable, Sendable { let revoked: Bool }
        let result = try await client.decode(Revocation.self, endpoint:
            Endpoint(method: .post, path: "/oauth/logout").jsonBody(["refresh_token": tokens.refreshToken]),
            accessToken: tokens.accessToken
        )
        guard result.revoked else { throw AppError.invalidResponse }
    }
}
