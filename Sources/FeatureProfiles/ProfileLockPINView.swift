#if canImport(SwiftUI)
import CoreModels
import PlozzCoreUI
import SwiftUI

/// The PIN screen for a profile's own `ProfileLock`, shown before switching into
/// a locked profile.
///
/// One view for both shells. It was two identical copies — same scaffold, same
/// copy, same footnote condition — which is a standing invitation for the lock
/// to behave differently on iPhone than on the Apple TV depending on which copy
/// someone happened to edit. There is nothing platform-specific here to justify
/// that: `PINEntryScaffold` already adapts.
///
/// Uses the same scaffold as the Plex Home PIN prompt on purpose. When someone
/// sets their profile lock to "same PIN as Plex" the two gates become one
/// experience, and a screen that looked different would give away that two
/// separate systems are involved.
///
/// The dial pad is kept on iOS rather than swapped for a text field: it's the
/// same gesture on both platforms, it can't summon a keyboard over the dots, and
/// it restricts entry to digits by construction.
///
/// Local verification runs away from the UI executor. The entered keypad stays
/// visible through verification and any continuation into Plex authentication.
public struct ProfileLockPINView: View {
    private let profile: Profile
    private let errorMessage: LocalizedStringResource?
    private let isSyncEnabled: Bool
    private let sequenceStep: PINSequenceStep?
    private let isSubmitting: Bool
    private let onSubmit: (String) async -> Void
    private let onCancel: () -> Void
    @Environment(\.pinProfileTransition) private var profileTransition
    @State private var submission: Task<Void, Never>?

    /// - Parameter isSyncEnabled: whether these settings currently reach the
    ///   user's other devices. Drives the caveat: with Sync off the lock only
    ///   exists here, and the same profile is unlocked everywhere else. Passed in
    ///   rather than read here so this stays a view over its inputs.
    public init(
        profile: Profile,
        errorMessage: LocalizedStringResource?,
        isSyncEnabled: Bool,
        sequenceStep: PINSequenceStep? = nil,
        isSubmitting: Bool = false,
        onSubmit: @escaping (String) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.profile = profile
        self.errorMessage = errorMessage
        self.isSyncEnabled = isSyncEnabled
        self.sequenceStep = sequenceStep
        self.isSubmitting = isSubmitting
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        PINEntryScaffold(
            title: ProfileLockCopy.unlockTitle,
            name: Text(verbatim: profile.name),
            showsLock: true,
            errorMessage: errorMessage,
            isSubmitting: isSubmitting || submission != nil,
            footnote: isSyncEnabled ? nil : ProfileLockCopy.lockIsDeviceOnly,
            sequenceStep: sequenceStep,
            onSubmit: { pin in
                guard submission == nil, !isSubmitting else { return }
                submission = Task {
                    await onSubmit(pin)
                    submission = nil
                }
            },
            onCancel: {
                submission?.cancel()
                onCancel()
            }
        ) {
            ProfileAvatarView(profile: profile, size: profileTransition?.avatarSize ?? PINLayout.badgeSize)
        }
        .onDisappear { submission?.cancel() }
    }
}
#endif
