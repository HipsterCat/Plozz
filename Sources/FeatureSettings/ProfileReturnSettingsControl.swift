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
    @Binding private var selection: ProfileReturnPolicy
    private let automaticPolicy: ProfileReturnPolicy
    private let automaticallySignIn: Bool

    public init(settings: ProfileReturnSettings, automaticallySignIn: Bool) {
        _selection = settings.selection
        automaticPolicy = settings.automaticPolicy
        self.automaticallySignIn = automaticallySignIn
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.relatedControlSpacing) {
            SettingsMenuRow(title: "Show Profiles on Return", value: summary) {
                Picker("Show Profiles on Return", selection: $selection) {
                    ForEach(ProfileReturnPolicy.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
            }
            .disabled(automaticallySignIn)
            .accessibilityIdentifier("profiles.showOnReturn")
            if automaticallySignIn {
                Text("Disabled by Automatically Sign In.")
                    .settingsHelperText()
            } else if selection == .never {
                Text("Keeps the current profile unlocked.")
                    .settingsHelperText()
            } else {
                Text("Not shown during playback.")
                    .settingsHelperText()
            }
        }
    }

    private var summary: Text {
        if selection == .automatic {
            Text("Automatic (\(String(localized: automaticPolicy.title)))")
        } else {
            Text(selection.title)
        }
    }
}
#endif
