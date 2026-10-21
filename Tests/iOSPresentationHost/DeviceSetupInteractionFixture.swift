import CoreModels
import CoreUI
import FeatureSyncSetup
import Observation
import SwiftUI
@testable import AppShelliOS

@MainActor
struct DeviceSetupInteractionFixture: View {
    @State private var app: PlozziOSAppModel
    @State private var controls: SetupFixtureControls
    @State private var model: SyncSetupPairingModel

    init() {
        SyncSetupFeatureFlag().isEnabled = false
        let app = PlozziOSAppModel()
        let controls = SetupFixtureControls()
        let service = SyncSetupService(
            flag: SyncSetupFeatureFlag(), beaconStore: InMemoryPresenceBeaconStore(),
            rendezvousStore: InMemoryPairingRendezvousStore(), deviceID: { "test-source" },
            deviceName: { "Test Phone" }, isConfigured: { true },
            configProvider: { .init(accounts: [], profiles: []) }
        )
        let revoke = ProcessInfo.processInfo.arguments.contains("--revoke-setup-authorization")
        let model = SyncSetupPairingModel(
            service: service, isAuthorized: { controls.allowed }, diagnostics: DeviceSetupDiagnostics(),
            makeGuestLink: { _ in
                FailingSetupGuest {
                    controls.attempts += 1
                    controls.canPresent = false
                    if revoke { controls.allowed = false }
                    return controls.attempts == 1 ? .seconds(3) : .seconds(30)
                }
            }
        )
        app.pendingSyncSetupOffer = SyncPairingRendezvous(
            serviceName: "ABCD", publicKeyData: Data([1]), deviceName: "Test TV",
            deviceID: "test-receiver", ttlSeconds: 180
        )
        _app = State(initialValue: app)
        _controls = State(initialValue: controls)
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack {
            Button("Show setup offer") { controls.canPresent = true }
            Text(app.pendingSyncSetupOffer == nil ? "Offer consumed" : "Offer retained")
                .accessibilityIdentifier("setup-fixture-offer")
            Text("Attempts: \(controls.attempts)")
                .accessibilityIdentifier("setup-fixture-attempts")
        }
        .modifier(PlozziOSSyncSetupOfferPresenter(
            appModel: app, canPresent: controls.canPresent, makeModel: { model }
        ))
        .environment(\.themePalette, ThemePalette.light)
        .environment(\.locale, Locale(identifier: "en_US"))
        .preferredColorScheme(.light)
    }
}

@MainActor @Observable
private final class SetupFixtureControls {
    var canPresent = false
    var allowed = true
    var attempts = 0
}

private struct FailingSetupGuest: PairingLinkConnecting {
    let onConnect: @MainActor @Sendable () -> Duration
    func connect() async throws -> any PairingLink {
        let delay = await onConnect()
        try await Task.sleep(for: delay)
        throw BonjourPairingError.connectionFailed
    }
}
