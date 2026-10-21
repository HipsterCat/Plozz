import CoreModels
import CoreNetworking
import CoreUI
import FeatureAuth
import FeatureAuthCore
import SwiftUI

struct ServerAddressNavigationFixture: View {
    @State private var router = ManagedProviderSetupRouter()
    private let accounts: [Account]
    private let store: AccountStore

    init() {
        let plex = ProcessInfo.processInfo.arguments.contains("--plex-addresses")
        var server = MediaServer(id: "fixture", name: "Example media server",
                                 baseURL: URL(string: plex
                                    ? "https://192-168-68-71.0123456789abcdef0123456789abcdef.plex.direct:32400"
                                    : "https://media.example.test")!, provider: plex ? .plex : .jellyfin)
        if plex {
            server.alternateConnectionURLs = [URL(string: "https://media.example.test/plex")!]
        }
        let names = ProcessInfo.processInfo.arguments.contains("--multiple-address-signins") ? ["Alice", "Bob"] : ["Alice"]
        accounts = names.map { Account(id: $0, server: server, userID: $0, userName: $0, deviceID: "fixture") }
        store = AccountStore(secureStore: InMemorySecureStore())
        do {
            for account in accounts { try store.add(account, token: "fixture-token") }
        } catch {
            fatalError("Could not prepare isolated address-management accounts: \(error)")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Example media server").font(.title)
                SettingsSectionGroup("Connection addresses") {
                    ServerAddressSettingsLink(accounts: accounts)
                }
            }
            .padding(32)
        }
        .environment(\.managedProviderSetupRouter, router)
        .plozzSheet(item: $router.addressAccount) { account in
            ServerAddressesView(account: account, store: store, isAuthorized: { true }, onChanged: {})
                .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--large-address-text") ? .accessibility3 : .large)
        }
        .environment(\.themePalette, ProcessInfo.processInfo.arguments.contains("--light-addresses") ? .light : .dark)
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--light-addresses") ? .light : .dark)
        .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--large-address-text") ? .accessibility3 : .large)
    }
}
