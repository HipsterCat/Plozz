#if canImport(SwiftUI)
import CoreModels
import PlozzCoreUI
import FeatureProfiles
import SwiftUI

/// The Parental PIN prompt that unseals a Kids Profile's restricted settings.
///
/// A pushed page rather than a modal. Modals asked for from inside the Settings
/// tab are unreliable — `RootView` stacks several `fullScreenCover` modifiers on
/// one host and a contested slot is silently dropped, which is exactly how the
/// profile Edit button ended up doing nothing. Pushing uses the navigation stack
/// this page already lives in.
///
/// Pushed prompts pop on success. The workspace instead opens the selected
/// protected section in place.
struct GrownUpsUnlockView: View {
    let context: SettingsContext
    var onCancel: (() -> Void)?
    var onUnlock: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: LocalizedStringResource?
    #if os(tvOS)
    @Environment(\.settingsInWorkspace) private var inWorkspace
    #endif

    var body: some View {
        ParentalPINView(
            errorMessage: errorMessage,
            isCompact: usesCompactLayout,
            onSubmit: submit,
            onCancel: { if let onCancel { onCancel() } else { dismiss() } }
        )
        .settingsWorkspaceEntry()
    }

    private var usesCompactLayout: Bool {
        #if os(tvOS)
        inWorkspace
        #else
        false
        #endif
    }

    private func submit(_ pin: String) {
        guard context.matchesParentalPIN(pin) else {
            errorMessage = ProfileLockCopy.incorrectPIN
            return
        }
        errorMessage = nil
        context.onParentalUnlock()
        if let onUnlock { onUnlock() } else { dismiss() }
    }
}
#endif
