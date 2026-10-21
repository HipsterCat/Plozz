#if os(iOS)
import AppRuntime
import PlozzCoreUI
import SwiftUI

struct PlozziOSPlexPINView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: PlexHomeUsersModel
    let request: PlexHomeUsersModel.PlexPINRequest
    var sequenceStep: PINSequenceStep? = nil
    var dismissOnSuccess = true
    var onCancel: () -> Void = {}

    var body: some View {
        let pendingRequest = model.pendingPlexPINRequest
        PINEntryScaffold(
            title: "Enter your Plex PIN",
            name: Text(verbatim: request.homeUserName),
            errorMessage: model.plexPINError,
            isSubmitting: model.isSubmittingPlexPIN,
            availability: pendingRequest == nil ? .checking : model.plexPINEntryAvailability,
            onRetry: {
                guard model.pendingPlexPINRequest == request else { return }
                model.retryPlexPINRequirement()
            },
            sequenceStep: sequenceStep,
            onSubmit: { pin in
                guard model.pendingPlexPINRequest == request,
                      model.plexPINEntryAvailability == .available else { return }
                model.submitPlexPIN(pin)
            },
            onCancel: {
                guard model.pendingPlexPINRequest == request else { return }
                onCancel()
                model.cancelPlexPIN()
                if dismissOnSuccess, model.pendingPlexPINRequest == nil { dismiss() }
            }
        ) {
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
        .id([request.id, request.accountID, request.homeUserID])
        .interactiveDismissDisabled(pendingRequest != nil)
        .onChange(of: pendingRequest?.id) { _, requestID in
            if requestID == nil, dismissOnSuccess {
                dismiss()
            }
        }
    }
}
#endif
