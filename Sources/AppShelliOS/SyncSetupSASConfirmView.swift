#if os(iOS)
import SwiftUI
import PlozzCoreUI
import FeatureSyncSetup

extension View {
    /// Native primary actions shared with the other setup flows.
    func syncPrimaryButtonStyle() -> some View {
        plozzActionButton()
    }
}

/// Numeric-comparison (SAS) confirmation shown on the SENDER during a non-QR pair
/// (tap-to-pair, typed code, or universal link). The user checks the same number
/// appears on the other device before any credentials are trusted — this defeats a
/// man-in-the-middle on the cameraless paths. Confirming drives `confirmSASMatch`.
@MainActor
struct SyncSetupSASConfirmView: View {
    let code: String
    let onResult: (Bool) -> Void

    var body: some View {
        ScrollView {
            SetupCodeComparisonView(code: SyncPairingSAS.grouped(code), onResult: onResult)
                .frame(maxWidth: 520)
                .padding(24)
                .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
    }
}
#endif
