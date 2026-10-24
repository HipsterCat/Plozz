#if os(iOS)
import AppRuntime
import CoreModels
import PlozzCoreUI
import FeatureAuth
import FeatureProfiles
import SwiftUI

struct PlozziOSPlexPINView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: PlexHomeUsersModel
    let request: PlexHomeUsersModel.PlexPINRequest
    var profile: Profile?
    var sequenceStep: PINSequenceStep? = nil
    var dismissOnSuccess = true
    var onCancel: () -> Void = {}
    @Environment(\.pinProfileTransition) private var profileTransition
    @State private var lastAvailability: PINEntryAvailability = .checking

    var body: some View {
        let pendingRequest = model.pendingPlexPINRequest
        ZStack {
            if pendingRequest == request, model.plexPINEntryAvailability == .unavailable {
                PlexAccountRecoveryView(
                    name: profile?.name ?? request.homeUserName,
                    message: model.plexPINError ?? ProfileLockCopy.plexSwitchFailed,
                    signIn: model.plexReauthentication,
                    onSignIn: { model.beginPlexReauthentication() },
                    onRetry: { model.retryPlexPINRequirement() },
                    onCancel: {
                        onCancel()
                        model.cancelPlexPIN()
                    },
                    onCancelSignIn: { model.cancelPlexReauthentication() }
                )
            } else {
                PINEntryScaffold(
                    title: profile == nil ? "Enter your Plex PIN" : "Plex PIN",
                    name: Text(verbatim: profile?.name ?? request.homeUserName),
                    showsLock: true,
                    errorMessage: model.plexPINError,
                    isSubmitting: model.isSubmittingPlexPIN || pendingRequest != request,
                    availability: pendingRequest == request ? model.plexPINEntryAvailability : lastAvailability,
                    onRetry: {
                        guard model.pendingPlexPINRequest == request else { return }
                        model.retryPlexPINRequirement()
                    },
                    sequenceStep: sequenceStep,
                    onSubmit: { pin in
                        guard model.pendingPlexPINRequest == request,
                            model.plexPINEntryAvailability == .available
                        else { return }
                        model.submitPlexPIN(pin)
                    },
                    onCancel: {
                        guard model.pendingPlexPINRequest == request else { return }
                        onCancel()
                        model.cancelPlexPIN()
                        if dismissOnSuccess, model.pendingPlexPINRequest == nil { dismiss() }
                    }
                ) {
                    if let profile {
                        ProfileAvatarView(
                            profile: profile, size: profileTransition?.avatarSize ?? PINLayout.badgeSize)
                    } else {
                        PINBadge {
                            if let url = request.homeUserAvatarURL.flatMap(URL.init(string:)) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case let .success(image):
                                        image.resizable().scaledToFill()
                                    default:
                                        Image(systemName: "person.fill")
                                            .font(.title)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .id([request.id, request.accountID, request.homeUserID])
            }
        }
        .interactiveDismissDisabled(pendingRequest != nil)
        .onChange(of: model.plexPINEntryAvailability, initial: true) { _, availability in
            if model.pendingPlexPINRequest == request { lastAvailability = availability }
        }
        .onChange(of: pendingRequest?.id) { _, requestID in
            if requestID == nil, dismissOnSuccess {
                dismiss()
            }
        }
    }
}
#endif
