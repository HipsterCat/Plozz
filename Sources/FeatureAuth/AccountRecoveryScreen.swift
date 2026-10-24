import CoreModels
import PlozzCoreUI
import SwiftUI

struct AccountRecoveryScreen: View {
    let provider: ProviderKind
    let name: String
    let message: LocalizedStringResource
    var onSignIn: (() -> Void)? = nil
    let onRetry: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Control?

    private enum Control: Hashable { case signIn, retry, cancel }

    var body: some View {
        RecoveryScreen {
            AccountRecoveryHeading(provider: provider, name: name, message: message)
        } actions: { axis in
            #if os(iOS)
            let actionWidth: CGFloat? = axis == .vertical ? .infinity : nil
            #else
            let actionWidth: CGFloat? = nil
            #endif
            if let onSignIn {
                Button(action: onSignIn) {
                    Text("Sign In Again").fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: actionWidth)
                }
                .plozzActionButton()
                .focused($focused, equals: .signIn)
                .accessibilityIdentifier("plex-recovery-sign-in")
            }
            Button(action: onRetry) {
                Text("Try Again").fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: actionWidth)
            }
            .plozzActionButton(role: onSignIn == nil ? .primary : .secondary)
            .focused($focused, equals: .retry)
            .accessibilityIdentifier("account-recovery-retry")
            Button(role: .cancel, action: onCancel) {
                Text("Cancel").fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: actionWidth)
            }
            .plozzActionButton(role: .secondary)
            .focused($focused, equals: .cancel)
            .accessibilityIdentifier("account-recovery-cancel")
        }
        .controlSize(.large)
        #if os(tvOS)
        .defaultFocus($focused, onSignIn == nil ? .retry : .signIn)
        .onExitCommand(perform: onCancel)
        #endif
    }
}

private struct AccountRecoveryHeading: View {
    let provider: ProviderKind
    let name: String
    let message: LocalizedStringResource
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var logoSize = 64.0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            let identityLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
            identityLayout {
                ProviderBrandMark(provider: provider, size: min(logoSize, 88))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Reconnect to \(provider.displayName)",
                        comment: "Account-recovery heading. The placeholder is a provider name, such as Plex or Jellyfin."
                    )
                        .font(.title2.bold())
                        .plozzForeground(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: name)
                        .font(.subheadline)
                        .plozzForeground(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(message)
                .font(.body)
                .plozzForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account-recovery-message")
        }
    }
}
