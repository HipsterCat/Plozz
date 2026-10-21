import XCTest
@testable import CoreModels
@testable import FeatureSyncSetup

final class SyncSetupSourceInviteTests: XCTestCase {
    func testReceiverAndSourceInvitesCannotBeConfused() throws {
        let source = SyncSetupSourceInvite()
        XCTAssertEqual(SyncSetupSourceInvite.decode(source.encoded()), source)
        XCTAssertNil(SyncPairingInvite.decode(source.encoded()))
        let receiver = SyncPairingInvite(
            serviceName: "ABCD", publicKeyData: SyncPairingIdentity().publicKeyData,
            context: SyncPairingContext()
        )
        XCTAssertNil(SyncSetupSourceInvite.decode(receiver.encoded()))
        XCTAssertNotNil(SyncPairingInvite.decode(receiver.encoded()))
        XCTAssertTrue(source.encoded().contains("#receive="))
        XCTAssertFalse(source.encoded().contains("?"))
    }

    func testInvitationExpiryAndUntrustedInput() {
        let date = Date(timeIntervalSince1970: 10_000)
        let source = SyncSetupSourceInvite(now: date)
        XCTAssertTrue(source.isUsable(now: date))
        XCTAssertFalse(source.isUsable(now: date.addingTimeInterval(180)))
        XCTAssertFalse(source.isUsable(now: date.addingTimeInterval(-1)))
        for input in ["https://plozz.app/pair#%", source.encoded() + "&extra=1",
                      source.encoded().replacingOccurrences(of: "plozz.app", with: "example.com"),
                      source.encoded().replacingOccurrences(of: "expires=10180", with: "expires=bad")] {
            XCTAssertNil(SyncSetupSourceInvite.decode(input))
        }
    }

    func testFirstRunInvitesStayInsideTheirInstallation() {
        let source = SyncSetupSourceInvite()
        let installation = AppInstallation.firstRun(UUID())
        let encoded = source.encoded(installation: installation)
        XCTAssertEqual(SyncSetupSourceInvite.decode(encoded, installation: installation), source)
        XCTAssertNil(SyncSetupSourceInvite.decode(encoded, installation: .standard))
        XCTAssertNil(SyncSetupSourceInvite.decode(encoded, installation: .firstRun(UUID())))
    }
}

@MainActor
final class SourceSetupPairingTests: XCTestCase {
    func testScanFindsOnlyItsTVAndRequiresMatchingCodeBeforeCredentials() async throws {
        let links = await InMemoryPairingLink.makePair()
        let browser = SourceSetupBrowser()
        let shared = InMemoryPairingRendezvousStore()
        let sender = SyncSetupPairingModel(
            service: try service(sending: true, rendezvous: shared),
            makeGuestLink: { _ in StaticGuest(link: links.guest) }, makeBrowser: { browser }
        )
        sender.startDiscovery(offeringSetup: true)
        defer { sender.stopDiscovery(); sender.cancelSending() }
        let invite = try XCTUnwrap(sender.sourceInvite)
        let receiver = SyncSetupPairingModel(
            service: try service(rendezvous: shared),
            makeHostLink: { pairing in
                XCTAssertEqual(pairing.sourceRequestID, invite.requestID)
                browser.publish([DiscoveredPairingDevice(
                    serviceName: pairing.code, displayName: "Phone",
                    sourceRequestID: pairing.sourceRequestID
                )])
                return StaticHost(link: links.host)
            }
        )
        let receiving = Task { await receiver.startReceiving(sourceInvite: invite) }
        defer { receiver.stopReceiving(); receiving.cancel() }
        try await waitUntil { sender.sourceReceiver != nil }
        XCTAssertTrue(shared.all().isEmpty, "A targeted scan must not ask unrelated iCloud devices to send setup.")
        let device = try XCTUnwrap(sender.sourceReceiver)
        let sending = Task { await sender.sendToSourceReceiver(device) }
        defer { sending.cancel() }
        try await waitUntil {
            if case .confirmingSAS = sender.phase { return receiver.hostSASCode != nil }
            return false
        }
        guard case .confirmingSAS(let code) = sender.phase else { return XCTFail("Missing TV confirmation") }
        XCTAssertEqual(code, receiver.hostSASCode)
        XCTAssertEqual(receiver.phase, .applying)
        sender.confirmSASMatch(true)
        await sending.value
        await receiving.value
        XCTAssertEqual(sender.phase, .sent)
        guard case .applied(let setup) = receiver.phase else { return XCTFail("Setup was not received") }
        XCTAssertEqual(setup.config.accounts.map(\.id), ["account"])
        XCTAssertEqual(setup.secrets?.accounts.first?.token, "fixture-token")
        XCTAssertNil(sender.sourceInvite, "The scanned request is single-use.")
    }

    func testUnrelatedReceiverAndRenewedQRCodeCannotClaimTheSource() async throws {
        let browser = SourceSetupBrowser()
        let sender = SyncSetupPairingModel(service: try service(), makeBrowser: { browser })
        sender.startDiscovery(offeringSetup: true)
        defer { sender.stopDiscovery() }
        let old = try XCTUnwrap(sender.sourceInvite)
        sender.startDiscovery(offeringSetup: true)
        XCTAssertNotEqual(sender.sourceInvite?.requestID, old.requestID)
        browser.publish([
            DiscoveredPairingDevice(serviceName: "ABCD", displayName: "Phone", sourceRequestID: old.requestID),
            DiscoveredPairingDevice(serviceName: "EFGH", displayName: "Untargeted")
        ])
        try await waitUntil { !sender.nearbyDevices.isEmpty }
        XCTAssertNil(sender.sourceReceiver)
        XCTAssertEqual(sender.nearbyDevices.map(\.serviceName), ["EFGH"])
        sender.stopDiscovery()
        XCTAssertNil(sender.sourceInvite)
    }

    func testExpiredScannedInvitationDoesNotAdvertise() async throws {
        let receiver = SyncSetupPairingModel(service: try service(), makeHostLink: { _ in
            XCTFail("Expired source invitation must not advertise")
            return BonjourPairingHost(serviceName: "unused")
        })
        await receiver.startReceiving(sourceInvite: SyncSetupSourceInvite(now: Date().addingTimeInterval(-300)))
        XCTAssertEqual(receiver.phase, .failed("This setup code expired. Scan a new code on your Apple TV."))
    }

    func testDeclinedOrRevokedSourceConfirmationNeverSendsCredentials() async throws {
        for revokeAuthorization in [false, true] {
            let links = await InMemoryPairingLink.makePair()
            let recording = SourceSetupRecordingLink(base: links.guest)
            var authorized = true
            let sender = SyncSetupPairingModel(
                service: try service(sending: true), isAuthorized: { authorized },
                makeGuestLink: { _ in StaticGuest(link: recording) },
                makeBrowser: { SourceSetupBrowser() }
            )
            sender.startDiscovery(offeringSetup: true)
            defer { sender.stopDiscovery(); sender.cancelSending() }
            let invite = try XCTUnwrap(sender.sourceInvite)
            let receiver = SyncSetupPairingModel(
                service: try service(), makeHostLink: { _ in StaticHost(link: links.host) }
            )
            let receiving = Task { await receiver.startReceiving(sourceInvite: invite) }
            defer { receiver.stopReceiving(); receiving.cancel() }
            let sending = Task {
                await sender.sendToSourceReceiver(DiscoveredPairingDevice(
                    serviceName: "ABCD", displayName: "Phone", sourceRequestID: invite.requestID
                ))
            }
            defer { sending.cancel() }
            try await waitUntil {
                if case .confirmingSAS = sender.phase { return receiver.hostSASCode != nil }
                return false
            }
            XCTAssertEqual(recording.sentCount, 2, "Only the hello and nonce reveal may precede confirmation.")
            if revokeAuthorization {
                authorized = false
                sender.authorizationDidChange()
                sender.confirmSASMatch(true)
            } else {
                sender.confirmSASMatch(false)
            }
            await sending.value
            XCTAssertEqual(recording.sentCount, 2, "No encrypted credential payload may follow a rejected confirmation.")
            guard case .failed = sender.phase else { return XCTFail("Rejected setup must not succeed.") }
            if case .applied = receiver.phase { XCTFail("Rejected setup must not be received.") }
        }
    }

    func testAuthorizationLossWithdrawsTheSourceQRCode() throws {
        var authorized = true
        let sender = SyncSetupPairingModel(
            service: try service(), isAuthorized: { authorized }, makeBrowser: { SourceSetupBrowser() }
        )
        sender.startDiscovery(offeringSetup: true)
        defer { sender.stopDiscovery() }
        XCTAssertNotNil(sender.sourceInvite)
        authorized = false
        sender.authorizationDidChange()
        XCTAssertNil(sender.sourceInvite)
        XCTAssertNil(sender.sourceReceiver)
        guard case .failed = sender.phase else { return XCTFail("Lost authorization must stop setup.") }
    }

    func testCancellingReceiverCannotPublishLateSuccess() async throws {
        let links = await InMemoryPairingLink.makePair()
        let receiver = SyncSetupPairingModel(
            service: try service(), makeHostLink: { _ in StaticHost(link: links.host) }
        )
        let receiving = Task { await receiver.startReceiving(sourceInvite: SyncSetupSourceInvite()) }
        try await waitUntil { receiver.phase == .applying }
        receiver.stopReceiving()
        await receiving.value
        XCTAssertEqual(receiver.phase, .applying, "Cancelled work must not publish an applied result.")
        links.guest.close()
    }

    private func service(
        sending: Bool = false,
        rendezvous: InMemoryPairingRendezvousStore = InMemoryPairingRendezvousStore()
    ) throws -> SyncSetupService {
        let suite = "SourceSetupPairingTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let account = Account(
            id: "account", server: MediaServer(
                id: "server", name: "Server", baseURL: URL(string: "https://example.com")!,
                provider: .jellyfin
            ), userID: "user", userName: "Viewer", deviceID: "source"
        )
        return SyncSetupService(
            flag: SyncSetupFeatureFlag(defaults: defaults),
            beaconStore: InMemoryPresenceBeaconStore(), rendezvousStore: rendezvous,
            deviceID: { sending ? "source" : "receiver" }, deviceName: { "Device" },
            isConfigured: { sending },
            configProvider: { .init(accounts: sending ? [account] : [], profiles: []) },
            secretsProvider: {
                SyncSecretsBundle(accounts: sending ? [
                    AccountSecret(accountID: account.id, provider: .jellyfin, token: "fixture-token",
                                  deviceID: "source", trustedOrigin: "https://example.com")
                ] : [])
            }
        )
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(predicate(), "Pairing did not reach the expected state.")
    }
}

private final class SourceSetupBrowser: PairingBrowsing, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable ([DiscoveredPairingDevice]) -> Void)?
    func start(onChange: @escaping @Sendable ([DiscoveredPairingDevice]) -> Void) {
        lock.withLock { callback = onChange }
    }

    func stop() { lock.withLock { callback = nil } }
    func publish(_ devices: [DiscoveredPairingDevice]) {
        let callback = lock.withLock { callback }
        callback?(devices)
    }
}

private final class SourceSetupRecordingLink: PairingLink, @unchecked Sendable {
    let base: any PairingLink
    private let lock = NSLock()
    private var count = 0
    var sentCount: Int { lock.withLock { count } }
    init(base: any PairingLink) { self.base = base }
    func send(_ data: Data) async throws {
        lock.withLock { count += 1 }
        try await base.send(data)
    }
    func receive() async throws -> Data { try await base.receive() }
    func close() { base.close() }
}
