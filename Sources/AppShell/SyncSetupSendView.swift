#if os(tvOS)
import CoreModels
import PlozzCoreUI
import FeatureProfiles
import FeatureSyncSetup
import SwiftUI

/// tvOS "Set up another device" (sender) screen. The Apple TV has no camera, so it
/// browses for nearby devices that are waiting to be set up and lets you pick one
/// (tap-to-pair), with an on-screen code field as a fallback. Credentials then flow
/// from this Apple TV to the chosen device over the E2E-encrypted pairing channel.
@MainActor
struct SyncSetupSendView: View {
    @Environment(\.themePalette) private var palette
    private let appState: AppState
    private let onClose: () -> Void
    @State private var model: SyncSetupPairingModel
    @State private var code = ""
    @State private var handled = false
    @State private var offer: SyncPairingRendezvous?
    @State private var authorization: Authorization
    @State private var sendTask: Task<Void, Never>?

    private struct Authorization: Equatable {
        let profileID: String
        let accountScope: String
        let plexIdentity: String

        @MainActor
        init(_ appState: AppState) {
            let accounts = appState.accountsProviders.accounts
            let profile = appState.profilesModel.activeProfile
            profileID = profile.id
            accountScope = HomeRuntimeScope.accountScopeKey(accounts)
            plexIdentity = profile.plexPlaybackIdentityKey(for: accounts)
        }

        @MainActor
        func isCurrent(in appState: AppState) -> Bool {
            self == Authorization(appState)
                && appState.isActiveProfileAuthorized
                && !appState.profileFlow.managementRequiresParentalPIN
        }
    }

    init(appState: AppState, offer: SyncPairingRendezvous? = nil, onClose: @escaping () -> Void) {
        self.appState = appState
        self.onClose = onClose
        _offer = State(initialValue: offer)
        let authorization = Authorization(appState)
        _authorization = State(initialValue: authorization)
        _model = State(initialValue: SyncSetupPairingModel(
            service: appState.syncSetup,
            isAuthorized: { authorization.isCurrent(in: appState) }
        ))
    }

    private var isAuthorized: Bool {
        authorization.isCurrent(in: appState)
    }

    var body: some View {
        ZStack {
            AppBackground(palette: palette)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 70)
                .padding(.top, model.phase == .sent ? 0 : 70)
                .padding(.bottom, model.phase == .sent ? 24 : 70)
        }
        .onAppear { if offer == nil { model.startDiscovery(offeringSetup: true) } }
        .onChange(of: model.sourceReceiver) { _, device in
            if let device { startSending { await model.sendToSourceReceiver(device) } }
        }
        .onChange(of: isAuthorized, initial: true) { _, _ in model.authorizationDidChange() }
        .onDisappear {
            sendTask?.cancel()
            model.cancelSending()
            model.stopDiscovery()
        }
        .onExitCommand { onClose() }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            if let offer {
                offerConfirmation(offer)
            } else {
                SyncSetupSenderPicker(
                    invite: model.sourceInvite, inviteExpired: model.sourceInviteExpired,
                    devices: model.nearbyDevices, code: $code,
                    onRefresh: { model.startDiscovery(offeringSetup: true) },
                    onSelect: { device in startSending { await model.pair(with: device) } },
                    onSendCode: { startSending { await model.send(code: code) } },
                    onClose: onClose
                )
            }
        case .connecting, .sending:
            VStack(spacing: 18) {
                ProgressView().controlSize(.large)
                Text("Setting up the other device…").font(.title2)
                    .foregroundStyle(palette.secondaryText)
                Button("Cancel", role: .cancel, action: onClose)
            }
        case .sent:
            sentSummary
        case .confirmingSAS(let sas):
            sasConfirm(sas)
        case .failed(let message):
            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 60))
                    .foregroundStyle(palette.secondaryText)
                Text("Setup didn’t finish").font(.title2.bold())
                Text(message).foregroundStyle(palette.secondaryText).multilineTextAlignment(.center)
                Button("Try Again") {
                    handled = false
                    model.reset()
                    if offer == nil { model.startDiscovery(offeringSetup: true) }
                }
                .disabled(!isAuthorized)
                Button("Cancel", role: .cancel) { onClose() }
            }
        default:
            ProgressView()
        }
    }

    private func startSending(_ action: @escaping @MainActor () async -> Void) {
        guard !handled, isAuthorized else { return }
        handled = true
        sendTask = Task { await action() }
    }

    private func offerConfirmation(_ offer: SyncPairingRendezvous) -> some View {
        let server = offer.requestedAccountID.flatMap { id in
            appState.accountsProviders.accounts.first { $0.id == id }?.server.name
        }
        let title: LocalizedStringResource = if let server {
            "Set up “\(server)” on “\(offer.deviceName)”?"
        } else {
            "Set up “\(offer.deviceName)”?"
        }
        let message: LocalizedStringResource = if let server {
            "Sign this device in to “\(server)”."
        } else {
            "Send your servers and sign-in so it’s ready to watch."
        }
        return VStack(spacing: 28) {
            Text(title).font(.largeTitle.bold()).foregroundStyle(palette.primaryText)
            Text(message)
                .foregroundStyle(palette.secondaryText)
            HStack(spacing: 24) {
                Button("Set Up") { startSending { await model.adopt(offer) } }
                    .disabled(!isAuthorized)
                Button("Not Now", role: .cancel, action: onClose)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: Verification code (SAS) confirmation — the sender gates the transfer
    // on the user confirming both devices show the SAME number, defeating a
    // man-in-the-middle on the (cameraless) tap-to-pair / code paths.

    @ViewBuilder
    private func sasConfirm(_ code: String) -> some View {
        ScrollView {
            SetupCodeComparisonView(code: SyncPairingSAS.grouped(code)) {
                model.confirmSASMatch($0)
            }
            .padding(24)
        }
        .defaultScrollAnchor(.center, for: .alignment)
    }

    // MARK: Sent success (what this Apple TV sent)

    private var sentSummary: some View {
        let requestedID = offer?.requestedAccountID
        let accounts = appState.accountsProviders.accounts.filter {
            requestedID == nil || $0.id == requestedID
        }
        let groups = SyncedServerAccountGroup.groups(from: accounts.map { SyncedAccountDescriptor(account: $0) })
        let profiles = requestedID == nil ? appState.profilesModel.profiles : []
        return SetupSummaryView(
            title: "Your other device is set up", serverGroups: groups,
            profileCount: profiles.count, actionTitle: "Done", onAction: onClose
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
