#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import PlozzCoreUI

/// Library availability belongs to Libraries; this screen only configures Home.
struct CustomizeHomeDetailView: View {
    let discoveredLibraries: LoadState<[AggregatedLibrary]>
    let homeVisibility: HomeLibraryVisibilityModel
    let accounts: [ResolvedAccount]

    init(
        discoveredLibraries: LoadState<[AggregatedLibrary]>,
        homeVisibility: HomeLibraryVisibilityModel,
        seerConfigured _: Bool,
        accounts: [ResolvedAccount] = []
    ) {
        self.discoveredLibraries = discoveredLibraries
        self.homeVisibility = homeVisibility
        self.accounts = accounts
    }

    var body: some View {
        HomeRowsSettingsView(
            libraries: discoveredLibraries.value ?? [], accounts: accounts, visibility: homeVisibility
        )
        .id(ObjectIdentifier(homeVisibility))
    }
}
#endif
