#if os(tvOS)
import SwiftUI
import CoreModels
import PlozzCoreUI
import FeatureProfiles
import FeatureSyncSetup

/// tvOS "Set up from another device" screen: shows a QR + short code, advertises
/// over the local network, receives the sealed setup, and persists it so the TV is
/// signed in with no typing.
@MainActor
struct SyncSetupReceiveView: View {
    @Environment(\.themePalette) private var palette
    private let appState: AppState
    private let onClose: () -> Void
    @State private var model: SyncSetupPairingModel
    @State private var didApply = false
    @State private var applyError: String?

    init(appState: AppState, onClose: @escaping () -> Void) {
        self.appState = appState
        self.onClose = onClose
        _model = State(initialValue: SyncSetupPairingModel(service: appState.syncSetup))
    }

    var body: some View {
        ZStack {
            AppBackground(palette: palette)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await model.startReceiving() }
        .onDisappear { model.stopReceiving() }
        .alert("Setup didn’t finish", isPresented: Binding(
            get: { applyError != nil }, set: { if !$0 { applyError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: applyError ?? "") }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 28) {
            switch model.phase {
            case .idle:
                ProgressView()
            case .waitingForPeer(let code, let invite):
                OnboardingHeader(Text("Set up from another device"))
                HStack(alignment: .center, spacing: 60) {
                    VStack(spacing: 12) {
                        QRCodeView(invite.encoded())
                            .frame(width: 340, height: 340)
                            .padding(18).background(.white).cornerRadius(16)
                        Text("Scan with your phone or tablet").font(.callout)
                            .foregroundStyle(palette.secondaryText)
                    }
                    VStack(spacing: 10) {
                        Text("or enter code").font(.callout).foregroundStyle(palette.secondaryText)
                        ConnectionCodeView(SyncPairingCode.grouped(code), size: 64)
                        Text("on another device").font(.callout).foregroundStyle(palette.secondaryText)
                    }
                }
                Text("On your other device, open Settings > iCloud Sync > Set Up Another Device.")
                    .font(.callout).foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center).frame(maxWidth: 900)
            case .applying:
                if let sas = model.hostSASCode {
                    sasComparison(sas)
                } else {
                    ProgressView("Setting up…").font(.title2).foregroundStyle(palette.primaryText)
                }
            case .confirmingSAS(let sas):
                sasComparison(sas)
            case .applied(let received):
                appliedSummary(received)
            case .connecting, .sending, .sent:
                ProgressView()
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle").font(.system(size: 60))
                    .foregroundStyle(palette.secondaryText)
                Text(message).foregroundStyle(palette.secondaryText).multilineTextAlignment(.center)
                Button("Try Again") { Task { await model.startReceiving() } }
            }

            if case .applied = model.phase {} else {
                Button("Cancel", role: .cancel) { onClose() }.padding(.top, 12)
            }
        }
        .padding(.horizontal, 70)
        .padding(.top, summaryIsVisible ? 0 : 70)
        .padding(.bottom, summaryIsVisible ? 24 : 70)
    }

    private var summaryIsVisible: Bool {
        if case .applied = model.phase { return true }
        return false
    }

    // MARK: Verification code (SAS) — shown so the user can confirm both devices
    // display the SAME number before any credentials are trusted.

    @ViewBuilder
    private func sasComparison(_ code: String) -> some View {
        SetupCodeComparisonView(code: SyncPairingSAS.grouped(code))
    }

    // MARK: Applied summary (app design language — provider logos + profiles)

    @ViewBuilder
    private func appliedSummary(_ received: SyncSetupService.ReceivedSetup) -> some View {
        let servers = received.config.accounts
        let pendingIDs = Set(received.serversNeedingSignIn(
            excluding: Set(appState.accountsProviders.accounts.map(\.id))
        ).map(\.id))
        let profiles = received.config.profiles.map(\.profile)

        SetupSummaryView(
            title: pendingIDs.isEmpty ? "You’re all set" : "Set Up This Device",
            serverGroups: SyncedServerAccountGroup.groups(from: servers),
            pendingIDs: pendingIDs, profileCount: profiles.count,
            actionTitle: pendingIDs.isEmpty ? "Start Watching" : "Continue",
            onAction: {
                guard !didApply else { return }
                didApply = true
                let outcome = appState.applyReceivedSetup(received)
                model.recordApplication(outcome)
                if outcome.isTotalCredentialFailure {
                    didApply = false   // allow a retry
                    applyError = "Couldn’t finish signing in on this Apple TV. Check both devices are on the same Wi-Fi and try again."
                } else {
                    onClose()
                }
            }
        ) {
            ProfileSummaryGrid(
                profiles: profiles, avatarSize: 80, itemWidth: 152, spacing: 24,
                nameFont: .caption, nameLineLimit: nil, focusableProfiles: true
            )
            .foregroundStyle(palette.primaryText)
        }
    }
}
#endif
