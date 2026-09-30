#if canImport(SwiftUI)
import Observation
import SwiftUI

enum SystemCaptionStyleCopy {
    static var optionTitle: LocalizedStringResource {
        #if os(tvOS)
        LocalizedStringResource(
            "Match Apple TV Subtitle Style",
            comment: "Toggle: use this Apple TV's system subtitle appearance instead of a custom Plozz appearance."
        )
        #else
        LocalizedStringResource(
            "Match Device Subtitle Style",
            comment: "Toggle: use this iPhone or iPad's system subtitle appearance instead of a custom Plozz appearance."
        )
        #endif
    }

    static var confirmationTitle: LocalizedStringResource {
        #if os(tvOS)
        LocalizedStringResource(
            "Match Apple TV Subtitle Style?",
            comment: "Confirmation title before replacing the custom subtitle appearance with this Apple TV's system appearance."
        )
        #else
        LocalizedStringResource(
            "Match Device Subtitle Style?",
            comment: "Confirmation title before replacing the custom subtitle appearance with this iPhone or iPad's system appearance."
        )
        #endif
    }
}

@MainActor
@Observable
final class SystemCaptionStyleConfirmation {
    var isPresented = false
    @ObservationIgnored private var pendingEnable = false

    func request(_ enabled: Bool, currentlyMatching: Bool, apply: (Bool) -> Void) {
        guard enabled != currentlyMatching else { return }
        if enabled {
            pendingEnable = true
            isPresented = true
        }
        else { apply(false) }
    }

    func confirm(apply: (Bool) -> Void) {
        guard pendingEnable else { return }
        pendingEnable = false
        isPresented = false
        apply(true)
    }

    func cancel() {
        pendingEnable = false
        isPresented = false
    }
}

struct SystemCaptionStyleConfirmationDialog: ViewModifier {
    @Bindable var confirmation: SystemCaptionStyleConfirmation
    let apply: (Bool) -> Void

    func body(content: Content) -> some View {
        content.alert(Text(SystemCaptionStyleCopy.confirmationTitle), isPresented: $confirmation.isPresented) {
            Button("Cancel", role: .cancel) { confirmation.cancel() }
            Button(role: .destructive) { confirmation.confirm(apply: apply) } label: {
                Text("Match Style", comment: "Confirm replacing the custom subtitle appearance with this device's system subtitle appearance.")
            }
        } message: {
            Text("This will replace your custom subtitle style with your device's system subtitle style.")
        }
    }
}
#endif
