#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct ProfileReturnSettings {
    public let selection: Binding<ProfileReturnPolicy>
    public let automaticPolicy: ProfileReturnPolicy

    public init(selection: Binding<ProfileReturnPolicy>, automaticPolicy: ProfileReturnPolicy) {
        self.selection = selection
        self.automaticPolicy = automaticPolicy
    }
}

public struct ProfileReturnSettingsControl: View {
    private let settings: ProfileReturnSettings
    private let automaticallySignIn: Bool

    public init(settings: ProfileReturnSettings, automaticallySignIn: Bool) {
        self.settings = settings
        self.automaticallySignIn = automaticallySignIn
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsMenuRow(title: "Show Profiles on Return", value: summary) {
                Picker("Show Profiles on Return", selection: settings.selection) {
                    ForEach(ProfileReturnPolicy.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
            }
            .disabled(automaticallySignIn)
            .accessibilityIdentifier("profiles.showOnReturn")
            if automaticallySignIn {
                Text("Turn off Automatically Sign In to use this setting.")
                    .settingsHelperText()
            } else {
                Text("Open players are unaffected. Never keeps your profile unlocked when you return.")
                    .settingsHelperText()
            }
        }
    }

    private var summary: Text {
        if settings.selection.wrappedValue == .automatic {
            Text("Automatic (\(String(localized: settings.automaticPolicy.title)))")
        } else {
            Text(settings.selection.wrappedValue.title)
        }
    }
}
#endif
