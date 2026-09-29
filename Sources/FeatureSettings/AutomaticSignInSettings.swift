import SwiftUI

public struct AutomaticSignInSettings {
    public let isEnabled: Binding<Bool>
    public let error: LocalizedStringResource?

    public init(isEnabled: Binding<Bool>, error: LocalizedStringResource? = nil) {
        self.isEnabled = isEnabled
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Open the last-used profile without a PIN when this app starts on this device. Switching users still requires the Plex Home PIN. Your PIN is not changed or removed.")
            if let error = settings.error {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
    }
}
