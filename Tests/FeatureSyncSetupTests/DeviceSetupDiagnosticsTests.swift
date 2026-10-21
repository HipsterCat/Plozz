import CoreModels
import CoreNetworking
import XCTest
@testable import FeatureSyncSetup

final class DeviceSetupDiagnosticsTests: XCTestCase {
    func testConsentGenerationDeduplicationAndLimit() throws {
        let diagnostics = DeviceSetupDiagnostics()
        let captured = SetupDiagnosticCapture()
        XCTAssertNil(diagnostics.begin())
        diagnostics.start { captured.append($0) }
        let report = try XCTUnwrap(diagnostics.begin())
        report(failure())
        report(failure(elapsed: 50))
        report(.init(role: .sender, route: .code, stage: .connection, outcome: .cancelled, reason: .cancelled))
        report(.init(role: .sender, route: .code, stage: .connection, outcome: .cancelled, reason: .rejected))
        XCTAssertEqual(captured.values.count, 1, "Timing and user cancellation must not generate new issues.")
        diagnostics.stop()
        report(failure(route: .qr))
        diagnostics.start { captured.append($0) }
        report(failure(route: .link))
        XCTAssertEqual(captured.values.count, 1, "Old attempts cannot report across an opt-out or a new consent generation.")
        let current = try XCTUnwrap(diagnostics.begin())
        for role in [DeviceSetupDiagnostic.Role.sender, .receiver] {
            for stage in [DeviceSetupDiagnostic.Stage.validation, .connection, .configuration,
                          .handshake, .confirmation, .transfer, .persistence] {
                current(.init(role: role, route: .code, stage: stage, outcome: .failed, reason: .unknown))
            }
        }
        XCTAssertEqual(captured.values.count, 11, "At most ten distinct failures per reporting session.")
        diagnostics.stop()
    }

    func testInvalidDecodedMeasurementDoesNotReachSink() throws {
        let diagnostics = DeviceSetupDiagnostics()
        let captured = SetupDiagnosticCapture()
        diagnostics.start { captured.append($0) }
        defer { diagnostics.stop() }
        let report = try XCTUnwrap(diagnostics.begin())
        let data = Data("""
        {"role":"sender","route":"code","stage":"connection","outcome":"failed",
         "reason":"unknown","elapsedMilliseconds":-1}
        """.utf8)
        report(try JSONDecoder().decode(DeviceSetupDiagnostic.self, from: data))
        XCTAssertTrue(captured.values.isEmpty)
    }

    private func failure(route: DeviceSetupDiagnostic.Route = .code, elapsed: Int = 0) -> DeviceSetupDiagnostic {
        .init(role: .sender, route: route, stage: .connection, outcome: .failed,
              reason: .connection, elapsedMilliseconds: elapsed)
    }
}

@MainActor
final class SetupReceiveFailureTests: XCTestCase {
    func testFailedListenerStaysFailedWithdrawsOfferAndOnlyRetriesExplicitly() async throws {
        let store = InMemoryPairingRendezvousStore()
        let captured = SetupDiagnosticCapture()
        let diagnostics = DeviceSetupDiagnostics()
        diagnostics.start { captured.append($0) }
        defer { diagnostics.stop() }
        let host = SetupFailingHost()
        var hostsCreated = 0
        let model = SyncSetupPairingModel(
            service: try service(store: store), diagnostics: diagnostics,
            makeHostLink: { _ in hostsCreated += 1; return host }
        )
        await model.startReceiving()
        guard case .failed = model.phase else { return XCTFail("The receive error must remain visible.") }
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertEqual(hostsCreated, 1)
        XCTAssertGreaterThan(host.stopCount, 0)
        XCTAssertEqual(captured.values.first?.reason, .listener)
        XCTAssertEqual(captured.values.first?.stage, .connection)
        await Task.yield()
        XCTAssertEqual(hostsCreated, 1, "No silent re-arm loop.")
        await model.startReceiving()
        XCTAssertEqual(hostsCreated, 2)
        XCTAssertEqual(captured.values.count, 1, "Repeated failures are deduplicated for automatic reporting.")
    }

    func testReceiverDisconnectIsLoggedWithoutPayloadOrAddress() async throws {
        let links = await InMemoryPairingLink.makePair()
        let diagnostics = DeviceSetupDiagnostics()
        let captured = SetupDiagnosticCapture()
        diagnostics.start { captured.append($0) }
        defer { diagnostics.stop() }
        let model = SyncSetupPairingModel(
            service: try service(), diagnostics: diagnostics, makeHostLink: { _ in StaticHost(link: links.host) }
        )
        let receiving = Task { await model.startReceiving() }
        defer { model.stopReceiving(); links.guest.close(); receiving.cancel() }
        try await waitUntil { model.phase == .applying }
        links.guest.close()
        await receiving.value
        guard case .failed = model.phase else { return XCTFail("Disconnect must not silently advertise again.") }
        XCTAssertEqual(captured.values.first?.stage, .handshake)
        let log = PlozzLog.recentLogText(limit: 30)
        XCTAssertTrue(log.contains("format=plozz-device-setup-1 role=receiver"))
        XCTAssertTrue(log.contains("outcome=failed"))
        XCTAssertFalse(log.contains("private-setup-fixture"))
    }

    func testCancellingSenderDuringCodeConfirmationUnblocksBothSidesWithoutReportingFailure() async throws {
        let links = await InMemoryPairingLink.makePair()
        let diagnostics = DeviceSetupDiagnostics()
        let captured = SetupDiagnosticCapture()
        diagnostics.start { captured.append($0) }
        defer { diagnostics.stop() }
        let receiver = SyncSetupPairingModel(
            service: try service(), makeHostLink: { _ in StaticHost(link: links.host) }
        )
        let sender = SyncSetupPairingModel(
            service: try service(), diagnostics: diagnostics,
            makeGuestLink: { _ in StaticGuest(link: links.guest) }
        )
        let receiving = Task { await receiver.startReceiving() }
        let sending = Task { await sender.send(code: "ABCD") }
        defer { receiver.stopReceiving(); sender.cancelSending(); receiving.cancel(); sending.cancel() }
        try await waitUntil { if case .confirmingSAS = sender.phase { return true }; return false }
        sending.cancel()
        await sending.value
        await receiving.value
        XCTAssertNotEqual(sender.phase, .sent)
        XCTAssertTrue(captured.values.isEmpty)
    }

    func testUnansweredConfirmationTimesOutAndLateAcceptanceCannotSend() async throws {
        let links = await InMemoryPairingLink.makePair()
        let diagnostics = DeviceSetupDiagnostics()
        let captured = SetupDiagnosticCapture()
        diagnostics.start { captured.append($0) }
        defer { diagnostics.stop() }
        let receiver = SyncSetupPairingModel(
            service: try service(), makeHostLink: { _ in StaticHost(link: links.host) }
        )
        let sender = SyncSetupPairingModel(
            service: try service(), diagnostics: diagnostics, confirmationTimeout: .milliseconds(100),
            makeGuestLink: { _ in StaticGuest(link: links.guest) }
        )
        let receiving = Task { await receiver.startReceiving() }
        defer { receiver.stopReceiving(); receiving.cancel(); sender.cancelSending() }
        await sender.send(code: "ABCD")
        await receiving.value
        sender.confirmSASMatch(true)
        XCTAssertEqual(sender.phase, .failed("Setup timed out. Keep Plozz open on both devices and try again."))
        XCTAssertEqual(captured.values.first?.stage, .confirmation)
        XCTAssertEqual(captured.values.first?.reason, .timeout)
        guard case .failed = receiver.phase else { return XCTFail("Late approval cannot produce a received setup.") }
    }

    private func service(store: InMemoryPairingRendezvousStore = .init()) throws -> SyncSetupService {
        let suite = "SetupReceiveFailureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return SyncSetupService(
            flag: SyncSetupFeatureFlag(defaults: defaults), beaconStore: InMemoryPresenceBeaconStore(),
            rendezvousStore: store, deviceID: { "private-setup-fixture" }, deviceName: { "private-setup-fixture" },
            isConfigured: { true }, configProvider: { .init(accounts: [], profiles: []) }
        )
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(predicate())
    }
}

private final class SetupFailingHost: PairingLinkHosting, @unchecked Sendable {
    private let lock = NSLock()
    private var stops = 0
    var stopCount: Int { lock.withLock { stops } }
    func awaitConnection() async throws -> any PairingLink { throw BonjourPairingError.listenerFailed }
    func stop() { lock.withLock { stops += 1 } }
}

private final class SetupDiagnosticCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DeviceSetupDiagnostic] = []
    var values: [DeviceSetupDiagnostic] { lock.withLock { storage } }
    func append(_ value: DeviceSetupDiagnostic) { lock.withLock { storage.append(value) } }
}
