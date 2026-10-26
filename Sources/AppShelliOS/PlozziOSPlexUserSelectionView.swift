#if os(iOS)
import AppRuntime
import CoreModels
import CoreUI
import SwiftUI

struct PlozziOSPlexUserSelectionView: View {
    let selection: PlexHomeUsersModel.PendingPlexUserSelection
    let onSelect: (PlexHomeUser, Bool) -> Void

    var body: some View {
        NavigationStack {
            PlexHomeOnboardingView(users: selection.users, onSelect: onSelect)
                .id(selection.id)
                .settingsPageSurface()
        }
        .interactiveDismissDisabled()
    }
}
#endif
