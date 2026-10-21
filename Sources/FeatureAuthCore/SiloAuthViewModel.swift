import Foundation
import Observation
import CoreModels
import CoreNetworking
import ProviderSilo

@MainActor
@Observable
public final class SiloAuthViewModel {
    public enum Phase: Equatable {
        case idle
        case loading
        case pairing(code: String, match: String, url: URL, expiresAt: Date)
        case profiles([SiloProfile])
        case pin(SiloProfile)
        case expired
        case error(LocalizedStringResource)
    }
    public enum Operation: Equatable {
        case preparing, loadingProfiles, signingIn(String)

        public var message: LocalizedStringResource {
            switch self {
            case .preparing: "Getting your sign-in code…"
            case .loadingProfiles: "Approved. Loading your profiles…"
            case .signingIn(let name): "Connecting as \(name)…"
            }
        }
    }
    public private(set) var phase: Phase = .idle
    public private(set) var operation: Operation = .preparing
    public private(set) var verificationURL: URL?
    public private(set) var codeLifetime: TimeInterval = 600
    public var pin = ""
    public private(set) var pinError: LocalizedStringResource?
    private let server: MediaServer
    private let deviceID: String
    private let service: SiloAuthentication
    private let verificationOnly: Bool
    private let onAuthenticated: (UserSession) -> Void
    private var flow: Task<Void, Never>?
    private var generation = UUID()
    private var tokens: SiloTokenPair?
    @ObservationIgnored private var availableProfiles: [SiloProfile] = []
    @ObservationIgnored private let diagnostics: SiloSetupDiagnostics
    @ObservationIgnored private var reportFailure: SiloSetupDiagnostics.Sink?
    private var stage: SiloSetupDiagnostic.Stage = .validation

    public init(server: MediaServer, deviceID: String, service: SiloAuthentication? = nil,
                diagnostics: SiloSetupDiagnostics = .shared, verificationOnly: Bool = false,
                onAuthenticated: @escaping (UserSession) -> Void) {
        self.server = server
        self.deviceID = deviceID
        self.service = service ?? SiloAuthentication(baseURL: server.baseURL)
        self.diagnostics = diagnostics
        self.verificationOnly = verificationOnly
        self.onAuthenticated = onAuthenticated
    }

    public func start() {
        cancel()
        reportFailure = diagnostics.begin()
        stage = .validation
        let current = generation
        operation = .preparing
        phase = .loading
        flow = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.validateServer()
                try Task.checkCancellation()
                guard generation == current else { return }
                #if os(tvOS)
                let platform = "tvos"
                #else
                let platform = "ios"
                #endif
                stage = .start
                let challenge = try await service.beginPairing(platform: platform)
                try Task.checkCancellation()
                guard generation == current else { return }
                stage = .approvalLink
                guard !challenge.user_code.isEmpty, !challenge.device_code.isEmpty,
                      challenge.expires_in > 0, challenge.interval > 0 else {
                    throw SiloSetupFailure(.init(stage: .start, reason: .invalidResponse))
                }
                let (manualURL, url) = try Self.approvalURLs(challenge, baseURL: server.baseURL)
                var deadline = Date().addingTimeInterval(TimeInterval(challenge.expires_in))
                try Task.checkCancellation()
                guard generation == current else { return }
                verificationURL = manualURL
                codeLifetime = TimeInterval(challenge.expires_in)
                phase = .pairing(code: challenge.user_code, match: challenge.match_code, url: url, expiresAt: deadline)
                var interval = challenge.interval
                var consecutivePollFailures = 0
                var pollDelay = Double(interval)
                stage = .poll
                while Date() < deadline {
                    try await Task.sleep(for: .seconds(min(pollDelay, max(0, deadline.timeIntervalSinceNow))))
                    try Task.checkCancellation()
                    guard Date() < deadline else { break }
                    let result: SiloDevicePoll
                    do {
                        result = try await service.poll(challenge)
                    } catch let failure as SiloSetupFailure where failure.underlying == .serverUnreachable {
                        try Task.checkCancellation()
                        guard generation == current else { return }
                        consecutivePollFailures += 1
                        guard consecutivePollFailures < 3 else { throw failure }
                        // Continue this challenge, never replay device-start. If
                        // approval was consumed before the response was lost,
                        // the next poll's terminal status still ends the flow.
                        pollDelay = max(Double(interval), min(30, Double(interval) * pow(2, Double(consecutivePollFailures))))
                        PlozzLog.auth.info("Silo approval polling interrupted; waiting to continue the existing challenge")
                        continue
                    }
                    guard !Task.isCancelled, generation == current else {
                        if let received = result.tokens { discardVerificationLogin(received) }
                        return
                    }
                    switch result.status {
                    case "pending":
                        consecutivePollFailures = 0
                        interval = max(challenge.interval, result.poll_after)
                        pollDelay = Double(interval)
                        if let expiry = result.expires_at {
                            guard let updated = Self.pairingDate(expiry) else {
                                throw SiloSetupFailure(.init(stage: .poll, reason: .malformed))
                            }
                            deadline = updated
                            codeLifetime = max(codeLifetime, deadline.timeIntervalSinceNow)
                            phase = .pairing(code: challenge.user_code, match: challenge.match_code,
                                             url: url, expiresAt: deadline)
                        }
                    case "approved":
                        guard !result.temporary, let received = result.tokens,
                              !received.access_token.isEmpty, !received.refresh_token.isEmpty,
                              !received.user.id.isEmpty, received.expires_in > 0 else {
                            throw SiloSetupFailure(.init(stage: .poll, reason: .invalidResponse))
                        }
                        tokens = received
                        verificationURL = nil
                        try await loadProfiles(tokens: received, generation: current)
                        return
                    case "expired", "consumed", "canceled": throw AppError.quickConnectExpired
                    case "denied": throw SiloAuthenticationError.pairingDenied
                    default: throw AppError.invalidResponse
                    }
                }
                throw AppError.quickConnectExpired
            } catch {
                show(error, generation: current)
            }
        }
    }

    public func select(_ profile: SiloProfile) {
        guard case let .profiles(profiles) = phase, profiles.contains(profile) else { return }
        pin = ""
        pinError = nil
        if profile.has_pin { phase = .pin(profile) }
        else { finish(profile, pin: nil) }
    }

    public func submitPIN(_ profile: SiloProfile) {
        guard case let .pin(selected) = phase, selected == profile,
              !pin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let value = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        pin = ""
        pinError = nil
        finish(profile, pin: value)
    }

    public func chooseAnotherProfile() {
        guard case .pin = phase, !availableProfiles.isEmpty else { return }
        generation = UUID()
        flow?.cancel()
        flow = nil
        pin = ""
        pinError = nil
        phase = .profiles(availableProfiles)
    }

    public func retry() {
        guard case .error = phase else {
            if phase == .expired { start() }
            return
        }
        guard let tokens, tokens.receivedAt.addingTimeInterval(TimeInterval(tokens.expires_in)) > Date() else {
            start()
            return
        }
        reportFailure = diagnostics.begin()
        if !availableProfiles.isEmpty {
            pin = ""
            pinError = nil
            phase = .profiles(availableProfiles)
            return
        }
        let current = generation
        operation = .loadingProfiles
        phase = .loading
        flow = Task { [weak self] in
            guard let self else { return }
            do {
                try await loadProfiles(tokens: tokens, generation: current)
            } catch {
                show(error, generation: current)
            }
        }
    }

    private func loadProfiles(tokens: SiloTokenPair, generation current: UUID) async throws {
        stage = .profiles
        operation = .loadingProfiles
        phase = .loading
        let profiles = try await service.profiles(token: tokens.access_token)
        try Task.checkCancellation()
        guard generation == current else { return }
        guard !profiles.isEmpty else { throw AppError.notFound }
        availableProfiles = profiles
        phase = .profiles(profiles)
    }

    public func checkPairingExpiry() {
        guard case let .pairing(_, _, _, expiresAt) = phase, expiresAt <= Date() else { return }
        cancel()
        phase = .expired
    }

    private func finish(_ profile: SiloProfile, pin: String?) {
        guard let tokens else { return }
        flow?.cancel()
        let current = generation
        operation = .signingIn(profile.name)
        phase = .loading
        flow = Task { [weak self] in
            guard let self else { return }
            do {
                let proof: String?
                stage = pin == nil ? .session : .pin
                if let pin { proof = try await service.verifyPIN(pin, profile: profile, token: tokens.access_token) }
                else { proof = nil }
                try Task.checkCancellation()
                guard generation == current else { return }
                stage = .session
                let session = try await service.makeSession(
                    tokens: tokens, profile: profile, profileToken: proof,
                    deviceID: deviceID, serverName: server.name
                )
                try Task.checkCancellation()
                guard generation == current else { return }
                self.tokens = nil
                availableProfiles = []
                reportFailure = nil
                onAuthenticated(session)
            } catch SiloAuthenticationError.incorrectPIN {
                guard generation == current, !Task.isCancelled else { return }
                pinError = "That profile PIN did not match. Try again."
                phase = .pin(profile)
            } catch {
                show(error, generation: current)
            }
        }
    }

    private func show(_ error: Error, generation current: UUID) {
        guard generation == current, !Task.isCancelled else { return }
        guard !(error is CancellationError), error as? AppError != .cancelled else { return }
        verificationURL = nil
        let failure = setupFailure(error)
        PlozzLog.auth.error("Silo setup failed: stage=\(failure.diagnostic.stage.rawValue) reason=\(failure.diagnostic.reason.rawValue) status=\(failure.diagnostic.httpStatus ?? 0)")
        reportFailure?(failure.diagnostic)
        reportFailure = nil
        if let error = error as? SiloAuthenticationError {
            switch error {
            case .unsupportedServer:
                phase = .error("This connection requires a Silo server with the native v2 API. Check the server address and update Silo if needed.")
            case .pairingUnavailable:
                phase = .error("Device pairing is unavailable on this Silo server.")
            case .incorrectPIN:
                phase = .error("That profile PIN did not match. Try again.")
            case .pairingDenied:
                phase = .error("The Silo pairing request was denied.")
            }
        } else {
            let error = (error as? SiloSetupFailure)?.underlying ?? (error as? AppError) ?? .invalidResponse
            if error == .cancelled { return }
            if error == .quickConnectExpired {
                verificationURL = nil
                phase = .expired
                return
            }
            if error == .unauthorized {
                if let tokens { discardVerificationLogin(tokens) }
                tokens = nil
                availableProfiles = []
            }
            phase = .error(failure.userMessage)
        }
    }

    private func setupFailure(_ error: Error) -> SiloSetupFailure {
        if let auth = error as? SiloAuthenticationError {
            let reason: SiloSetupDiagnostic.Reason
            switch auth {
            case .unsupportedServer: reason = .unsupported
            case .pairingUnavailable: reason = .unavailable
            case .incorrectPIN: reason = .unauthorized
            case .pairingDenied: reason = .denied
            }
            return SiloSetupFailure(.init(stage: stage, reason: reason))
        }
        if error as? AppError == .quickConnectExpired {
            return SiloSetupFailure(.init(stage: .poll, reason: .expired), underlying: .quickConnectExpired)
        }
        return SiloSetupRequest.failure(error, stage: stage)
    }

    private static func pairingDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func approvalURLs(_ challenge: SiloDeviceChallenge, baseURL: URL) throws -> (URL, URL) {
        guard let complete = URL(string: challenge.verification_uri_complete, relativeTo: baseURL)?.absoluteURL,
              let manual = URL(string: challenge.verification_uri, relativeTo: baseURL)?.absoluteURL,
              ["http", "https"].contains(manual.scheme?.lowercased() ?? ""),
              Self.sameOrigin(manual, complete) else {
            throw SiloSetupFailure(.init(stage: .approvalLink, reason: .addressMismatch))
        }
        if Self.sameOrigin(manual, baseURL) { return (manual, complete) }
        // Silo may advertise server.public_url even when the device connected
        // through a LAN/proxy alias. Never follow that foreign link or transplant
        // its query. Use the documented activation page on the selected server.
        guard manual.lastPathComponent == "activate", complete.path == manual.path,
              manual.query == nil, manual.fragment == nil, complete.fragment == nil,
              ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""),
              baseURL.user == nil, baseURL.password == nil else {
            throw SiloSetupFailure(.init(stage: .approvalLink, reason: .addressMismatch))
        }
        let local = baseURL.appendingPathComponent("activate")
        guard var components = URLComponents(url: local, resolvingAgainstBaseURL: false) else {
            throw SiloSetupFailure(.init(stage: .approvalLink, reason: .invalidResponse))
        }
        components.queryItems = [URLQueryItem(name: "code", value: challenge.user_code)]
        guard let approval = components.url else {
            throw SiloSetupFailure(.init(stage: .approvalLink, reason: .invalidResponse))
        }
        return (local, approval)
    }

    public func cancel() {
        generation = UUID()
        flow?.cancel()
        flow = nil
        if let tokens { discardVerificationLogin(tokens) }
        tokens = nil
        availableProfiles = []
        verificationURL = nil
        pin = ""
        pinError = nil
        reportFailure = nil
        phase = .idle
    }

    private func discardVerificationLogin(_ tokens: SiloTokenPair) {
        guard verificationOnly else { return }
        Task { [service] in
            do { try await service.endVerificationLogin(accessToken: tokens.access_token) }
            catch { PlozzLog.auth.error("Could not revoke unfinished Silo address verification login") }
        }
    }

    static func sameOrigin(_ url: URL, _ base: URL) -> Bool {
        guard url.user == nil, url.password == nil,
              base.user == nil, base.password == nil,
              let scheme = url.scheme, let host = url.host,
              let baseScheme = base.scheme, let baseHost = base.host,
              let origin = try? NetworkOrigin(scheme: scheme, host: host, port: url.port),
              let baseOrigin = try? NetworkOrigin(scheme: baseScheme, host: baseHost, port: base.port) else { return false }
        return origin == baseOrigin
    }
}
