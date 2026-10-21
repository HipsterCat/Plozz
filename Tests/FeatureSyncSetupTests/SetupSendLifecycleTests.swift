import XCTest
@testable import CoreModels
@testable import FeatureSyncSetup

@MainActor
final class SetupSendLifecycleTests: XCTestCase {
    func testExpiredOfferFailsWithoutConnecting() async throws {
        let service = try makeService()
        let model = SyncSetupPairingModel(service: service, makeGuestLink: { _ in
            XCTFail("An expired offer must not connect")
            return FailingGuest()
        })
        await model.adopt(SyncPairingRendezvous(
            serviceName: "ABCD", publicKeyData: Data([1]), deviceName: "Device",
            deviceID: "other", expiresAtEpoch: 0
        ))
        XCTAssertEqual(model.phase, .failed("The setup code expired. Try again."))
    }

    func testConnectionFailureRemainsVisibleUntilReset() async throws {
        let model = SyncSetupPairingModel(
            service: try makeService(), makeGuestLink: { _ in FailingGuest() }
        )
        await model.send(code: "ABCD")
        XCTAssertEqual(model.phase, .failed("Couldn't reach the other device. Make sure both are on the same Wi-Fi."))
        await Task.yield()
        XCTAssertNotEqual(model.phase, .idle)
        model.reset()
        XCTAssertEqual(model.phase, .idle)
    }

    func testUnauthorizedSetupDoesNotReadCredentialsOrConnect() async throws {
        let service = try makeService {
            XCTFail("Unauthorized setup must not read credentials")
            return SyncSecretsBundle()
        }
        let model = SyncSetupPairingModel(service: service, isAuthorized: { false }, makeGuestLink: { _ in
            XCTFail("Unauthorized setup must not connect")
            return FailingGuest()
        })
        await model.send(code: "ABCD")
        XCTAssertEqual(model.phase, .failed("Setup didn't complete. Please try again."))
    }

    func testAuthorizationLossDuringHandshakePreventsSealedPayload() async throws {
        let receiver = try makeService()
        let pairing = receiver.makeHostPairing()
        var authorized = true
        let link = RecordingHandshakeLink(
            invite: try JSONEncoder().encode(PairingHandshakeInvite(
                publicKeyData: pairing.identity.publicKeyData,
                context: pairing.invite.context, hostNonce: SyncPairingSAS.makeNonce()
            )),
            beforeInvite: { authorized = false }
        )
        let model = SyncSetupPairingModel(
            service: try makeService(), isAuthorized: { authorized },
            makeGuestLink: { _ in StaticGuest(link: link) }
        )
        await model.send(inviteString: pairing.invite.encoded())
        let count = await link.sendCount
        XCTAssertEqual(count, 1, "Only the non-secret hello may leave before authorization is revoked.")
        XCTAssertEqual(model.phase, .failed("Setup didn't complete. Please try again."))
    }

    func testCancellingDuringHandshakePreventsSealedPayloadAndStaleSuccess() async throws {
        let receiver = try makeService()
        let pairing = receiver.makeHostPairing()
        var model: SyncSetupPairingModel?
        let link = RecordingHandshakeLink(
            invite: try JSONEncoder().encode(PairingHandshakeInvite(
                publicKeyData: pairing.identity.publicKeyData,
                context: pairing.invite.context, hostNonce: SyncPairingSAS.makeNonce()
            )),
            beforeInvite: { model?.reset() }
        )
        model = SyncSetupPairingModel(
            service: try makeService(), makeGuestLink: { _ in StaticGuest(link: link) }
        )
        await model?.send(inviteString: pairing.invite.encoded())
        let count = await link.sendCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model?.phase, .idle, "The cancelled operation cannot overwrite a newer UI state.")
    }

    func testCompletedSetupKeepsItsOutcomeAfterAuthorizationChanges() async throws {
        let pairing = try makeService().makeHostPairing()
        var authorized = true
        let link = RecordingHandshakeLink(
            invite: try JSONEncoder().encode(PairingHandshakeInvite(
                publicKeyData: pairing.identity.publicKeyData,
                context: pairing.invite.context, hostNonce: SyncPairingSAS.makeNonce()
            )),
            beforeInvite: {}
        )
        let model = SyncSetupPairingModel(
            service: try makeService(), isAuthorized: { authorized },
            makeGuestLink: { _ in StaticGuest(link: link) }
        )
        await model.send(inviteString: pairing.invite.encoded())
        XCTAssertEqual(model.phase, .sent)
        authorized = false
        model.authorizationDidChange()
        XCTAssertEqual(model.phase, .sent, "A later profile change cannot undo a completed transfer.")
    }

    func testCancelledHandshakeCannotInstallStaleConfirmation() async throws {
        let pairing = try makeService().makeHostPairing()
        var model: SyncSetupPairingModel?
        let link = RecordingHandshakeLink(
            invite: try JSONEncoder().encode(PairingHandshakeInvite(
                publicKeyData: pairing.identity.publicKeyData,
                context: pairing.invite.context, hostNonce: SyncPairingSAS.makeNonce()
            )),
            beforeInvite: {},
            afterSend: { count in if count == 2 { model?.reset() } }
        )
        model = SyncSetupPairingModel(
            service: try makeService(), confirmationTimeout: .milliseconds(50),
            makeGuestLink: { _ in StaticGuest(link: link) }
        )
        await model?.send(code: "ABCD")
        let count = await link.sendCount
        XCTAssertEqual(count, 2, "Cancellation after the nonce reveal must prevent the sealed transfer.")
        XCTAssertEqual(model?.phase, .idle, "A stale callback cannot revive confirmation after reset.")
    }

    private func makeService(
        secrets: @escaping @MainActor () -> SyncSecretsBundle = { SyncSecretsBundle() }
    ) throws -> SyncSetupService {
        let suite = "SetupSendLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return SyncSetupService(
            flag: SyncSetupFeatureFlag(defaults: defaults),
            beaconStore: InMemoryPresenceBeaconStore(),
            rendezvousStore: InMemoryPairingRendezvousStore(),
            deviceID: { "sender" }, deviceName: { "Sender" }, isConfigured: { true },
            configProvider: { .init(accounts: [], profiles: []) }, secretsProvider: secrets
        )
    }
}

private struct FailingGuest: PairingLinkConnecting {
    func connect() async throws -> any PairingLink { throw BonjourPairingError.connectionFailed }
}

private actor RecordingHandshakeLink: PairingLink {
    let invite: Data
    let beforeInvite: @MainActor @Sendable () -> Void
    let afterSend: @MainActor @Sendable (Int) -> Void
    private(set) var sendCount = 0

    init(invite: Data, beforeInvite: @escaping @MainActor @Sendable () -> Void,
         afterSend: @escaping @MainActor @Sendable (Int) -> Void = { _ in }) {
        self.invite = invite
        self.beforeInvite = beforeInvite
        self.afterSend = afterSend
    }

    func send(_ data: Data) async throws {
        sendCount += 1
        await afterSend(sendCount)
    }
    func receive() async throws -> Data {
        await beforeInvite()
        return invite
    }
    nonisolated func close() {}
}
