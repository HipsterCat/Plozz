#if os(tvOS)
import CoreUI
import FeatureSyncSetup
import SwiftUI

struct SyncSetupSenderPicker: View {
    let invite: SyncSetupSourceInvite?
    let inviteExpired: Bool
    let devices: [DiscoveredPairingDevice]
    @Binding var code: String
    let onRefresh: () -> Void
    let onSelect: (DiscoveredPairingDevice) -> Void
    let onSendCode: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                OnboardingHeader(Text("Set up another device"))
                HStack(alignment: .top, spacing: 36) {
                    SyncSetupSourceQR(invite: invite, expired: inviteExpired, onRefresh: onRefresh)
                        .frame(width: 520)
                    SetupSectionCard("Nearby devices") {
                        VStack(alignment: .leading, spacing: 28) {
                            SyncSetupNearbyDevices(devices: devices, onSelect: onSelect)
                                .frame(minHeight: 140, alignment: .topLeading)
                            Divider()
                            SyncSetupManualCodeEntry(code: $code, onSend: onSendCode)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Text("Keep both devices on the same Wi-Fi.")
                    .font(.caption).plozzForeground(.secondary)
            }
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .scrollClipDisabled()
        .defaultScrollAnchor(.center, for: .alignment)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Cancel", role: .cancel, action: onClose)
                .plozzActionButton(role: .secondary)
                .padding(.top, 20)
                .frame(maxWidth: .infinity)
                .focusSection()
        }
    }
}

private struct SyncSetupSourceQR: View {
    let invite: SyncSetupSourceInvite?
    let expired: Bool
    let onRefresh: () -> Void

    var body: some View {
        SetupSectionCard("iPhone or iPad") {
            VStack(spacing: 20) {
                if let invite, !expired {
                    QRCodeView(invite.encoded())
                        .frame(width: 340, height: 340)
                        .padding(20)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityLabel("Scan to set up your iPhone or iPad")
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "qrcode").font(.system(size: 64))
                            .plozzForeground(.secondary)
                        Text("This QR code expired.").plozzForeground(.secondary)
                        Button("New QR Code", action: onRefresh)
                            .plozzActionButton(role: .secondary)
                    }
                    .frame(height: 380)
                }
                Text("Scan with Camera")
                    .font(.caption).plozzForeground(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SyncSetupNearbyDevices: View {
    let devices: [DiscoveredPairingDevice]
    let onSelect: (DiscoveredPairingDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if devices.isEmpty {
                HStack(spacing: 16) {
                    ProgressView()
                    Text("Looking for devices…").plozzForeground(.secondary)
                }
                .padding(.vertical, 20)
            } else {
                ForEach(devices) { device in
                    Button { onSelect(device) } label: {
                        SyncSetupNearbyDeviceLabel(device: device)
                    }
                }
            }
        }
    }
}

struct SyncSetupNearbyDeviceLabel: View {
    let device: DiscoveredPairingDevice

    var body: some View {
        HStack(spacing: 22) {
            Image(systemName: "display.2").font(.title2)
            VStack(alignment: .leading, spacing: 8) {
                Text(device.displayName).font(.title3.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                // Inherit the native button's foreground, including focus inversion.
                Text(verbatim: SyncPairingCode.grouped(device.serviceName))
                    .font(.caption.monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SyncSetupManualCodeEntry: View {
    @Binding var code: String
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter a code").font(.headline).plozzForeground(.primary)
            HStack(spacing: 20) {
                TextField("Code", text: $code)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .frame(maxWidth: .infinity)
                Button("Set Up", action: onSend)
                    .plozzActionButton(role: .secondary)
                    .disabled(SyncPairingCode.normalize(code).count < 4)
            }
        }
    }
}
#endif
