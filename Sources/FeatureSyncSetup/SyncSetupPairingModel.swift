import Foundation
import Observation
import CoreModels

// MARK: - Pairing view model (drives both roles)
//
// The @Observable state machine the pairing UI binds to. Link factories are
// injected (real Bonjour in apps, in-memory in tests) so the flow is unit-testable.
//
// Target role (e.g. Apple TV): `startReceiving()` mints a code + QR invite (shown
// on screen), advertises, awaits the sealed setup, then applies it.
//
// Source role (e.g. phone/tablet/computer): `send(inviteString:)` decodes a scanned
// QR, or `send(code:)` uses a typed short code, connects, verifies, and sends this
// device's config + credentials.

@MainActor
@Observable
public final class SyncSetupPairingModel {

    public enum Phase: Equatable, Sendable {
        case idle
        case waitingForPeer(code: String, invite: SyncPairingInvite)   // target advertising
        case applying                                                  // received, applying
        case applied(SyncSetupService.ReceivedSetup)                   // target done
        case connecting                                                // source connecting
        case confirmingSAS(code: String)                              // source awaiting user match-confirm
        case sending                                                   // source in flight
        case sent                                                      // source done
        case failed(LocalizedStringResource)
    }

    public private(set) var phase: Phase = .idle
    /// Nearby devices currently waiting to be set up (for tap-to-pair, no code).
    public private(set) var nearbyDevices: [DiscoveredPairingDevice] = []
    public private(set) var sourceInvite: SyncSetupSourceInvite?
    public private(set) var sourceInviteExpired = false
    public private(set) var sourceReceiver: DiscoveredPairingDevice?
    /// When this device is the RECEIVER on a non-QR pairing, the 6-digit SAS to
    /// display for the user to compare against the sending device. nil otherwise.
    public private(set) var hostSASCode: String?

    private let service: SyncSetupService
    private let isAuthorized: @MainActor () -> Bool
    public var canSend: Bool { isAuthorized() }
    private let diagnostics: DeviceSetupDiagnostics
    private let confirmationTimeout: Duration
    @ObservationIgnored private var sendAttempt: DeviceSetupAttempt?
    @ObservationIgnored private var receiveAttempt: DeviceSetupAttempt?
    private var sendGeneration = 0
    private var sendingLink: (any PairingLink)?
    private let existingAuthorizations: @MainActor () -> [String: LocalAuthorization]
    private let makeHostLink: @MainActor (SyncSetupService.HostPairing) -> any PairingLinkHosting
    private let makeGuestLink: @MainActor (String) -> any PairingLinkConnecting
    private let makeBrowser: @MainActor () -> any PairingBrowsing
    private var browser: (any PairingBrowsing)?
    private var discoveryGeneration = 0
    private var sourceInviteExpiration: Task<Void, Never>?
    private var isReceiving = false
    private var currentHost: (any PairingLinkHosting)?
    private var receivingLink: (any PairingLink)?
    /// Monotonic token identifying the active receive run, so a stale run's cleanup
    /// can't null out a newer run's host (the listener-orphan bug).
    private var receiveGeneration = 0
    /// Continuation the sender awaits while the user confirms the SAS match.
    private var sasContinuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var sasTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var sasTimedOut = false
    /// When receiving for a SINGLE server (from the per-server "set up with other
    /// device" entry), the account id + name to advertise so the source transfers only
    /// that server and names it in its confirm prompt. nil = whole-device request.
    private var requestedAccountID: String?
    private var requestedServerName: String?

    public init(
        service: SyncSetupService,
        isAuthorized: @escaping @MainActor () -> Bool = { true },
        diagnostics: DeviceSetupDiagnostics = .shared,
        confirmationTimeout: Duration = .seconds(60),
        existingAuthorizations: @escaping @MainActor () -> [String: LocalAuthorization] = { [:] },
        makeHostLink: @escaping @MainActor (SyncSetupService.HostPairing) -> any PairingLinkHosting = {
            BonjourPairingHost(
                serviceName: $0.invite.serviceName, displayName: $0.displayName,
                sourceRequestID: $0.sourceRequestID
            )
        },
        makeGuestLink: @escaping @MainActor (String) -> any PairingLinkConnecting = { BonjourPairingGuest(serviceName: $0) },
        makeBrowser: @escaping @MainActor () -> any PairingBrowsing = { BonjourPairingBrowser() }
    ) {
        self.service = service
        self.isAuthorized = isAuthorized
        self.diagnostics = diagnostics
        self.confirmationTimeout = confirmationTimeout
        self.existingAuthorizations = existingAuthorizations
        self.makeHostLink = makeHostLink
        self.makeGuestLink = makeGuestLink
        self.makeBrowser = makeBrowser
    }

    /// Target role: show a code + QR, advertise, receive + apply the config.
    ///
    /// One explicit attempt. Failures remain visible until retry or dismissal;
    /// a failed listener must not silently spin and replace the displayed code.
    public func startReceiving(
        requestedAccountID: String? = nil,
        requestedServerName: String? = nil,
        sourceInvite: SyncSetupSourceInvite? = nil
    ) async {
        stopReceiving()
        self.requestedAccountID = requestedAccountID
        self.requestedServerName = requestedServerName
        isReceiving = true
        receiveGeneration += 1
        let generation = receiveGeneration
        receiveAttempt = DeviceSetupAttempt(
            role: .receiver, route: sourceInvite == nil ? .receive : .sourceQR, diagnostics: diagnostics
        )
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { stopReceiving(); return }
            if let sourceInvite, !sourceInvite.isUsable() {
                isReceiving = false
                receiveAttempt?.record(.failed, reason: .expired)
                phase = .failed("This setup code expired. Scan a new code on your Apple TV.")
                return
            }
            hostSASCode = nil
            // Generous TTL so the code never silently expires while the screen is
            // shown. The host's ephemeral key only lives as long as this ceremony,
            // so a long window here doesn't weaken the security model.
            let pairing = service.makeHostPairing(
                ttlSeconds: sourceInvite == nil ? 24 * 60 * 60 : Int(SyncSetupSourceInvite.lifetime),
                sourceRequestID: sourceInvite?.requestID
            )
            phase = .waitingForPeer(code: pairing.code, invite: pairing.invite)
            // Publish a same-Apple-ID rendezvous so the user's OTHER device can set
            // this one up with no scanned QR / typed code (the credential auto-skip).
            // Carry the requested server (if any) so the source transfers just that one
            // and names it in its confirm prompt.
            if sourceInvite == nil {
                service.publishRendezvous(
                    for: pairing,
                    requestedAccountID: requestedAccountID,
                    requestedServerName: requestedServerName
                )
            }
            let host = makeHostLink(pairing)
            currentHost = host
            receiveAttempt?.stage = .connection
            receiveAttempt?.record(.started)
            defer {
                host.stop()
                if currentHost === host { currentHost = nil }
                if generation == receiveGeneration {
                    isReceiving = false
                    hostSASCode = nil
                    service.withdrawRendezvous()
                }
            }
            do {
                let link: any PairingLink
                if let sourceInvite {
                    link = try await withPairingTimeout(
                        seconds: max(0, TimeInterval(sourceInvite.expiresAtEpoch) - Date().timeIntervalSince1970),
                        onTimeout: { host.stop() }
                    ) {
                        try await host.awaitConnection()
                    }
                } else {
                    link = try await host.awaitConnection()
                }
                guard isReceiving, generation == receiveGeneration else { link.close(); return }
                receivingLink = link
                defer {
                    link.close()
                    if generation == receiveGeneration { receivingLink = nil }
                }
                phase = .applying
                let received = try await service.receiveSetup(
                    pairing: pairing, over: link,
                    existingAuthorizations: existingAuthorizations(),
                    presentSAS: { [weak self] code in
                        Task { @MainActor in
                            guard let self, self.isReceiving, self.receiveGeneration == generation else { return }
                            self.hostSASCode = code
                        }
                    },
                    progress: { [weak self] stage in
                        await self?.recordReceiveStage(stage, generation: generation)
                    }
                )
                guard isReceiving, generation == receiveGeneration, !Task.isCancelled else { return }
                receiveAttempt?.record(.succeeded)
                phase = .applied(received)
                return
            } catch {
                if !isReceiving || generation != receiveGeneration || Task.isCancelled { return }
                receiveAttempt?.fail(error)
                phase = .failed(sourceInvite == nil ? Self.describe(error)
                    : "Setup didn’t finish. Show a new setup code on your Apple TV and scan it again.")
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.receiveGeneration == generation else { return }
                self.stopReceiving()
            }
        }
    }

    /// Stop advertising / awaiting a setup (call when the receive screen closes) so
    /// the device stops appearing in other devices' "set up another device" lists.
    public func stopReceiving() {
        if isReceiving { receiveAttempt?.record(.cancelled, reason: .cancelled) }
        isReceiving = false
        receiveGeneration += 1
        currentHost?.stop()
        currentHost = nil
        receivingLink?.close()
        receivingLink = nil
        hostSASCode = nil
        service.withdrawRendezvous()   // no longer waiting — remove the iCloud offer
    }

    private func recordReceiveStage(_ stage: DeviceSetupDiagnostic.Stage, generation: Int) {
        guard isReceiving, receiveGeneration == generation else { return }
        receiveAttempt?.stage = stage
        receiveAttempt?.record(.started)
    }

    public func recordApplication(_ outcome: SyncSetupService.ApplyOutcome) {
        receiveAttempt?.stage = .persistence
        receiveAttempt?.record(
            outcome.failedAccountIDs.isEmpty ? .succeeded : .failed,
            reason: outcome.failedAccountIDs.isEmpty ? .none : .storage
        )
    }

    // MARK: Source-side auto-discovery (tap-to-pair, no code)

    /// Source role: if a same-Apple-ID device is currently offering to be set up (it
    /// published a rendezvous to iCloud, e.g. an Apple TV the user just tapped "add my
    /// servers" on), connect and push this device's config + credentials with NO typing
    /// and NO SAS — the offer's ephemeral public key is authenticated out-of-band by
    /// iCloud account membership and pinned, exactly like a scanned QR. Returns true if
    /// an offer was found and a send was attempted.
    ///
    /// NOTE: because this transfers CREDENTIALS, the app should confirm with the user
    /// first (a single tap — see `adopt(_:)`), so a shared/stale Apple ID can't silently
    /// harvest tokens. This convenience is kept for tests / config-only flows.
    @discardableResult
    public func autoAdoptOfferedRendezvous() async -> Bool {
        guard case .idle = phase else { return false }   // don't interrupt an active flow
        guard let target = service.discoverRendezvousTarget() else { return false }
        await adopt(target)
        return true
    }

    /// Source role: push this device's config + credentials to a SPECIFIC offer the
    /// user has confirmed. Pins the offer's public key ⇒ no SAS, no typing. If the
    /// offer requested a single server, only that account is transferred.
    public func adopt(_ rendezvous: SyncPairingRendezvous) async {
        guard rendezvous.isUsable() else {
            failValidation(route: .automatic, reason: .expired)
            phase = .failed("The setup code expired. Try again.")
            return
        }
        let restrict = rendezvous.requestedAccountID.map { Set([$0]) }
        await send(
            serviceName: rendezvous.serviceName,
            expectedPublicKey: rendezvous.publicKeyData,
            route: .automatic,
            restrictToAccountIDs: restrict
        )
    }

    /// Begin listing nearby devices waiting to be set up.
    public func startDiscovery(offeringSetup: Bool = false) {
        stopDiscovery()
        let generation = discoveryGeneration
        if offeringSetup {
            let invite = SyncSetupSourceInvite()
            sourceInvite = invite
            sourceInviteExpiration = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(SyncSetupSourceInvite.lifetime)) }
                catch { return }
                guard let self, self.sourceInvite == invite else { return }
                self.sourceInviteExpired = true
                self.sourceReceiver = nil
            }
        }
        let browser = makeBrowser()
        browser.start { [weak self] devices in
            Task { @MainActor in
                guard let self, self.discoveryGeneration == generation else { return }
                self.nearbyDevices = devices.filter { $0.sourceRequestID == nil }
                if self.phase == .idle, self.sourceReceiver == nil,
                   let invite = self.sourceInvite, invite.isUsable(),
                   let receiver = devices.first(where: { $0.sourceRequestID == invite.requestID }) {
                    self.sourceReceiver = receiver
                }
            }
        }
        self.browser = browser
    }

    public func stopDiscovery() {
        discoveryGeneration += 1
        browser?.stop(); browser = nil
        sourceInviteExpiration?.cancel()
        sourceInviteExpiration = nil
        sourceInvite = nil
        sourceInviteExpired = false
        sourceReceiver = nil
        nearbyDevices = []
    }

    /// A source QR identifies the request, not the receiver's public key.
    /// Always compare SAS, even when these devices share an iCloud account.
    public func sendToSourceReceiver(_ device: DiscoveredPairingDevice) async {
        guard let invite = sourceInvite, invite.isUsable(),
              device.sourceRequestID == invite.requestID else {
            failValidation(route: .sourceQR, reason: .expired)
            phase = .failed("This setup code expired. Scan a new code on your Apple TV.")
            return
        }
        stopDiscovery()
        await send(serviceName: device.serviceName, expectedPublicKey: nil, route: .sourceQR)
    }

    /// Pair with a discovered device. If that device published a rendezvous to THIS
    /// iCloud account (same-Apple-ID), pin its authenticated public key so the transfer
    /// skips the numeric SAS — just like the automatic offer path. Otherwise fall back
    /// to SAS (a different Apple ID has no shared trust anchor).
    public func pair(with device: DiscoveredPairingDevice) async {
        stopDiscovery()
        let key = service.rendezvousPublicKey(forServiceName: device.serviceName)
        await send(serviceName: device.serviceName, expectedPublicKey: key, route: .nearby)
    }

    /// Source role: send using a scanned QR invite string. The in-app camera scan
    /// authenticates the recipient out-of-band, so the host key is pinned and the
    /// numeric SAS check is skipped for a zero-friction transfer.
    public func send(inviteString: String) async {
        guard let invite = SyncPairingInvite.decode(inviteString) else {
            failValidation(route: .qr, reason: .invalidInvite)
            phase = .failed("That doesn't look like a Plozz setup code.")
            return
        }
        await send(serviceName: invite.serviceName, expectedPublicKey: invite.publicKeyData, route: .qr)
    }

    /// Source role: send from a universal-link invite (`https://plozz.app/pair#…`).
    /// Unlike an in-app camera scan, a link can be delivered remotely (e.g. texted),
    /// so it is NOT trusted as in-person proof: we reuse the service name to connect
    /// but force the numeric SAS confirmation, exactly like a typed code.
    public func send(deepLink invite: String) async {
        guard let decoded = SyncPairingInvite.decode(invite) else {
            failValidation(route: .link, reason: .invalidInvite)
            phase = .failed("That doesn't look like a Plozz setup link.")
            return
        }
        await send(serviceName: decoded.serviceName, expectedPublicKey: nil, route: .link)
    }

    /// Source role: send using a typed short code. If a same-Apple-ID device published
    /// a rendezvous for this code, pin its authenticated key and skip the numeric SAS
    /// (the user read the code off their own device — in-person proof, like a QR).
    /// Otherwise (different Apple ID) fall back to SAS.
    public func send(code: String) async {
        let normalized = SyncPairingCode.normalize(code)
        guard normalized.count >= 4 else {
            failValidation(route: .code, reason: .invalidInvite)
            phase = .failed("Enter the code shown on your other device.")
            return
        }
        let key = service.rendezvousPublicKey(forServiceName: normalized)
        await send(serviceName: normalized, expectedPublicKey: key, route: .code)
    }

    private func send(
        serviceName: String,
        expectedPublicKey: Data?,
        route: DeviceSetupDiagnostic.Route,
        restrictToAccountIDs: Set<String>? = nil
    ) async {
        stopDiscovery()
        cancelSending()
        let generation = sendGeneration
        sendAttempt = DeviceSetupAttempt(role: .sender, route: route, diagnostics: diagnostics)
        phase = .connecting
        await withTaskCancellationHandler {
            do {
                try validateSend(generation: generation)
                sendAttempt?.stage = .connection
                sendAttempt?.record(.started)
                let guest = makeGuestLink(serviceName)
                let link = try await guest.connect()
                defer { link.close() }   // signal the peer promptly on success OR abort
                try validateSend(generation: generation)
                sendingLink = link
                defer { if generation == sendGeneration { sendingLink = nil } }
                let authorizedLink = AuthorizedSetupLink(base: link) { [weak self] in
                    guard let self else { throw CancellationError() }
                    try await self.validateSend(generation: generation)
                }
                phase = .sending
                try await service.sendSetup(
                    over: authorizedLink,
                    expectedPublicKey: expectedPublicKey,
                    restrictToAccountIDs: restrictToAccountIDs,
                    confirmSAS: { [weak self] code in
                        await self?.awaitSASConfirmation(code: code, generation: generation) ?? false
                    },
                    progress: { [weak self] stage in
                        await self?.recordSendStage(stage, generation: generation)
                    }
                )
                try validateSend(generation: generation)
                sendAttempt?.record(.succeeded)
                phase = .sent
            } catch {
                guard generation == sendGeneration else { return }
                let failure: Error = sasTimedOut ? BonjourPairingError.timedOut : error
                sendAttempt?.fail(failure)
                phase = .failed(Self.describe(failure))
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.sendGeneration == generation else { return }
                self.cancelSending()
            }
        }
    }

    private func failValidation(route: DeviceSetupDiagnostic.Route, reason: DeviceSetupDiagnostic.Reason) {
        cancelSending()
        sendAttempt = DeviceSetupAttempt(role: .sender, route: route, diagnostics: diagnostics)
        sendAttempt?.record(.failed, reason: reason)
    }

    private func recordSendStage(_ stage: DeviceSetupDiagnostic.Stage, generation: Int) {
        guard sendGeneration == generation else { return }
        sendAttempt?.stage = stage
        sendAttempt?.record(.started)
    }

    private func validateSend(generation: Int) throws {
        try Task.checkCancellation()
        guard generation == sendGeneration else { throw CancellationError() }
        guard isAuthorized() else { throw SetupAuthorizationError.changed }
    }

    public func cancelSending() {
        if phase == .connecting || phase == .sending || sasContinuation != nil {
            sendAttempt?.record(.cancelled, reason: .cancelled)
        }
        sendGeneration += 1
        sendingLink?.close()
        sendingLink = nil
        sasContinuation?.resume(returning: false)
        sasContinuation = nil
        sasTimeoutTask?.cancel()
        sasTimeoutTask = nil
        sasTimedOut = false
    }

    public func authorizationDidChange() {
        guard phase != .sent else { return }
        guard !isAuthorized() else { return }
        stopDiscovery()
        cancelSending()
        sendAttempt?.record(.failed, reason: .authorizationChanged)
        phase = .failed("Setup didn't complete. Please try again.")
    }

    /// Transition to the SAS-confirmation phase and suspend until the user taps
    /// "Matches" / "Doesn't match" (`confirmSASMatch`). Called from the send task
    /// on the non-QR path only.
    private func awaitSASConfirmation(code: String, generation: Int) async -> Bool {
        guard generation == sendGeneration, !Task.isCancelled, isAuthorized() else { return false }
        // Resolve any prior dangling continuation defensively.
        sasContinuation?.resume(returning: false)
        sasContinuation = nil
        sasTimedOut = false
        sasTimeoutTask?.cancel()
        sasTimeoutTask = Task { [weak self, confirmationTimeout] in
            do { try await Task.sleep(for: confirmationTimeout) } catch { return }
            guard let self, self.sendGeneration == generation, self.sasContinuation != nil else { return }
            self.sasTimedOut = true
            self.confirmSASMatch(false)
        }
        defer {
            if generation == sendGeneration { sasTimeoutTask?.cancel(); sasTimeoutTask = nil }
        }
        phase = .confirmingSAS(code: code)
        let confirmed = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            sasContinuation = cont
        }
        guard generation == sendGeneration else { return false }
        if confirmed { phase = .sending }
        return confirmed
    }

    /// The UI calls this when the user confirms whether the two devices' codes match.
    public func confirmSASMatch(_ matches: Bool) {
        guard let cont = sasContinuation else { return }
        sasContinuation = nil
        cont.resume(returning: matches)
    }

    public func reset() {
        cancelSending()
        phase = .idle
    }

    private struct AuthorizedSetupLink: PairingLink {
        let base: any PairingLink
        let validate: @Sendable () async throws -> Void

        func send(_ data: Data) async throws {
            try await validate()
            try await base.send(data)
        }

        func receive() async throws -> Data {
            try await validate()
            return try await base.receive()
        }

        func close() { base.close() }
    }

    private static func describe(_ error: Error) -> LocalizedStringResource {
        switch error {
        case SyncPairingError.expiredContext: return "The setup code expired. Try again."
        case SyncPairingError.notConfirmed: return "Setup was cancelled — the codes didn't match."
        case SyncPairingError.commitmentMismatch, SyncPairingError.decryptionFailed:
            return "Couldn't verify the other device. Try again."
        case BonjourPairingError.listenerFailed, BonjourPairingError.connectionFailed:
            return "Couldn't reach the other device. Make sure both are on the same Wi-Fi."
        case BonjourPairingError.timedOut:
            return "Setup timed out. Keep Plozz open on both devices and try again."
        default: return "Setup didn't complete. Please try again."
        }
    }
}

// MARK: - Injectable link factories (so tests can supply in-memory links)

public protocol PairingLinkHosting: AnyObject, Sendable {
    func awaitConnection() async throws -> PairingLink
    func stop()
}
public extension PairingLinkHosting {
    func stop() {}
}
public protocol PairingLinkConnecting: Sendable {
    func connect() async throws -> PairingLink
}
public protocol PairingBrowsing: Sendable {
    func start(onChange: @escaping @Sendable ([DiscoveredPairingDevice]) -> Void)
    func stop()
}

extension BonjourPairingHost: PairingLinkHosting {}
extension BonjourPairingGuest: PairingLinkConnecting {}
extension BonjourPairingBrowser: PairingBrowsing {}
