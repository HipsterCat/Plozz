import CoreModels
import SwiftUI

public struct ServerAddressSettingsLink: View {
    private let accounts: [Account]
    @Environment(\.managedProviderSetupRouter) private var router
    @State private var choosingSignIn = false

    public init(accounts: [Account]) {
        self.accounts = accounts
    }

    public var body: some View {
        Button {
            if accounts.count == 1 {
                router?.addressAccount = accounts.first
            } else {
                choosingSignIn = true
            }
        } label: {
            SettingsDisclosureLabel {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add or manage addresses")
                    Text("Use a local or remote address to reach this server.")
                        .font(.caption)
                        .plozzForeground(.secondary)
                }
            }
        }
        #if os(tvOS)
        .buttonStyle(SettingsFormButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .disabled(accounts.isEmpty || router == nil)
        .accessibilityIdentifier("manageServerAddresses")
        .confirmationDialog("Choose a sign-in", isPresented: $choosingSignIn, titleVisibility: .visible) {
            ForEach(accounts) { account in
                Button {
                    router?.addressAccount = account
                } label: {
                    if account.userName.isEmpty {
                        Text("Guest")
                    } else {
                        Text(verbatim: account.userName)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Addresses are saved separately for each sign-in. Choose which one to update.")
        }
    }
}
