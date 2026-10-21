#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreUI
import FeatureAuthCore
#if os(iOS)
import UIKit
#endif

public struct ServerAddressesView: View {
    @State private var model: ServerAddressesModel
    @State private var operation: Task<Void, Never>?
    @FocusState private var closeFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(
        account: Account, store: any AccountPersisting,
        isAuthorized: @escaping @MainActor () -> Bool,
        onChanged: @escaping @MainActor () -> Void
    ) {
        _model = State(initialValue: ServerAddressesModel(
            account: account, store: store, isAuthorized: isAuthorized, onChanged: onChanged
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let server = model.pairingServer {
                SiloSignInView(
                    server: server, deviceID: model.account.deviceID, verificationOnly: true,
                    onAuthenticated: { session in
                        operation = Task { await model.completePairing(session) }
                    },
                    onCancel: model.cancelPairing
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SettingsFormMetrics.sectionSpacing) {
                        ServerAddressesHeader(close: { dismiss() }, closeFocused: $closeFocused)
                        ServerAddressIdentity(
                            server: model.account.server, userName: model.account.userName
                        )
                        ServerSavedAddresses(model: model)
                        ServerAddAddressForm(model: model) {
                            operation = Task { await model.add() }
                        }
                    }
                    .padding(SettingsFormMetrics.pageInset)
                    .frame(maxWidth: SettingsFormMetrics.pageWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollClipDisabled()
            }
        }
        #if os(tvOS)
        .defaultFocus($closeFocused, true, priority: .userInitiated)
        #endif
        .onDisappear {
            operation?.cancel()
            model.cancel()
        }
    }
}

private struct ServerAddressesHeader: View {
    let close: () -> Void
    let closeFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Connection addresses")
                .settingsFeatureTitle()
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .plozzActionButton(role: .secondary)
                .accessibilityIdentifier("closeServerAddresses")
                #if os(tvOS)
                .focused(closeFocused)
                #endif
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

private struct ServerAddressIdentity: View {
    let server: MediaServer
    let userName: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var logoSize = 56.0

    var body: some View {
        let identityLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        VStack(alignment: .leading, spacing: 12) {
            identityLayout {
                ProviderBrandMark(provider: server.provider, size: min(logoSize, 80))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: server.provider.displayName)
                        .font(.caption.weight(.medium))
                        .plozzForeground(.secondary)
                    Text(verbatim: server.name)
                        .font(.headline)
                        .plozzForeground(.primary)
                    if userName.isEmpty {
                        Text("Guest access").font(.subheadline).plozzForeground(.secondary)
                    } else {
                        Text("Signed in as \(userName)")
                            .font(.subheadline)
                            .plozzForeground(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .settingsGroupSurface(cornerRadius: SettingsFormMetrics.groupCornerRadius)
            Label("Addresses are saved for this sign-in on this device.", systemImage: "person.crop.circle")
                .settingsHelperText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ServerSavedAddresses: View {
    let model: ServerAddressesModel
    @State private var pendingRemoval: URL?

    var body: some View {
        SettingsSectionGroup("Saved addresses") {
            ServerAddressRow(url: model.account.server.baseURL, isOriginal: true)
            ForEach(model.alternatives, id: \.self) { url in
                VStack(alignment: .leading, spacing: 12) {
                    ServerAddressRow(url: url, isOriginal: false)
                    HStack {
                        Button("Remove", systemImage: "minus.circle", role: .destructive) {
                            pendingRemoval = url
                        }
                        .plozzActionButton(role: .secondary)
                        .disabled(model.isWorking)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Plozz prefers a reachable local address and tries another saved address if the connection fails.")
                if model.account.server.provider == .plex {
                    Label("Plex also discovers its own local, remote, and relay addresses automatically.", systemImage: "network")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        #if os(tvOS)
        .focusSection()
        #endif
        .confirmationDialog("Remove this address?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval { model.remove(pendingRemoval) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
    }
}

private struct ServerAddressRow: View {
    let url: URL
    let isOriginal: Bool
    #if os(iOS)
    @State private var copied = false
    #endif

    private var displayAddress: String {
        let fullAddress = url.absoluteString
        guard let scheme = url.scheme, fullAddress.hasPrefix(scheme + "://") else { return fullAddress }
        return String(fullAddress.dropFirst(scheme.count + 3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if isOriginal {
                        Text("Original server address")
                    } else {
                        Text("Additional address")
                    }
                    if let scheme = url.scheme {
                        Text(verbatim: scheme.uppercased())
                            .font(.caption2.monospaced())
                    }
                }
                .font(.caption.weight(.medium))
                .plozzForeground(.secondary)
                Spacer(minLength: 0)
                #if os(iOS)
                Button {
                    UIPasteboard.general.string = url.absoluteString
                    copied = true
                } label: {
                    if copied {
                        Label("Copied", systemImage: "checkmark")
                    } else {
                        Label("Copy address", systemImage: "doc.on.doc")
                    }
                }
                .labelStyle(.iconOnly)
                .plozzActionButton(role: .secondary)
                #endif
            }
            Text(verbatim: displayAddress)
                .font(.footnote.monospaced())
                .plozzForeground(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(verbatim: url.absoluteString))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ServerAddAddressForm: View {
    @Bindable var model: ServerAddressesModel
    let add: () -> Void

    private var canAdd: Bool {
        !model.isWorking && !model.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SettingsSectionGroup("Add an address") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Server address")
                    .font(.caption.weight(.medium))
                    .plozzForeground(.secondary)
                TextField("Server address", text: $model.address, prompt: Text(verbatim: "https://media.example.com"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("serverAddressInput")
            }
            HStack {
                Button("Verify and add address", systemImage: "plus", action: add)
                    .labelStyle(.titleAndIcon)
                    .plozzActionButton(role: canAdd ? .primary : .secondary)
                    .disabled(!canAdd)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .contain)
            if model.isWorking { ProgressView("Verifying address…") }
            if let error = model.errorMessage {
                Text(error)
                    .plozzForeground(.primary)
                    .accessibilityIdentifier("serverAddressError")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Only add addresses you trust for this server. Your sign-in will be used at each saved address. HTTP connections are not encrypted.")
                if model.account.server.provider == .silo {
                    Text("Approve the new address in Silo, then choose the same account and profile. Your saved sign-in stays unchanged.")
                }
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }
}
#endif
