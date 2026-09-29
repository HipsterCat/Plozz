import SwiftUI

public struct AutomaticSignInSettings {
    public let isEnabled: Binding<Bool>
    public let error: LocalizedStringResource?

    public init(
        isEnabled: Binding<Bool>,
        error: LocalizedStringResource? = nil
    ) {
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

public struct AutomaticSignInErrorMessage: View {
    private let settings: AutomaticSignInSettings

    public init(settings: AutomaticSignInSettings) {
        self.settings = settings
    }

    public var body: some View {
        if let error = settings.error {
            Text(error)
                .foregroundStyle(.red)
        }
    }
}
