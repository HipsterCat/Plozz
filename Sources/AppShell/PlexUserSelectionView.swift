#if canImport(SwiftUI)
import SwiftUI
import AppRuntime
import CoreModels
import CoreUI

/// Shared Plex Home import/identity page. The selected user's PIN is deferred
/// until onboarding completes; other imported users are never authenticated here.
struct PlexUserSelectionView: View {
    let selection: PlexHomeUsersModel.PendingPlexUserSelection
    let onSelect: (PlexHomeUser, Bool) -> Void

    var body: some View {
        PlexHomeOnboardingView(users: selection.users, onSelect: onSelect)
            .id(selection.id)
    }
}
#endif
