import SwiftUI
import CoreModels

public struct AutomaticSignInSettings {
    public let isEnabled: Binding<Bool>
    public let explanation: LocalizedStringResource?
    public let error: LocalizedStringResource?

    public init(
        isEnabled: Binding<Bool>,
        profile: Profile,
        accounts: [Account],
        error: LocalizedStringResource? = nil
    ) {
        self.isEnabled = isEnabled
        let requiresPIN = profile.isLocked || accounts.contains {
            $0.server.provider == .plex
                && profile.homeUserBinding(forPlexAccount: $0.id)?.requiresPIN == true
        }
        self.explanation = requiresPIN ? "Skip the PIN at startup on this device." : nil
        self.error = error
    }
}

public struct AutomaticSignInToggle: View {
    private let settings: AutomaticSignInSettings

    public init(settings: AutomaticSignInSettings) {
        self.settings = settings
    }

    public var body: some View {
        Toggle("Automatically Sign In", isOn: settings.isEnabled)
            .accessibilityIdentifier("profiles.automaticallySignIn")
    }
}

public struct AutomaticSignInDescription: View {
    private let settings: AutomaticSignInSettings

    public init(settings: AutomaticSignInSettings) {
        self.settings = settings
    }

    public var body: some View {
        if settings.explanation != nil || settings.error != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let explanation = settings.explanation {
                    Text(explanation)
                }
                if let error = settings.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
