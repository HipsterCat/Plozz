#if canImport(SwiftUI)
import SwiftUI

/// Place this heading inside ordinary pages' scrollable content. Full-screen
/// editors may keep it outside their independently scrolling tool pane.
/// Add a subtitle only when the title cannot communicate the scope of the page.
public struct SettingsPageHeader: View {
    private let title: Text
    private let subtitle: Text?
    #if os(tvOS)
    @Environment(\.settingsPageBackButton) private var backButton
    #endif

    public init(_ title: Text, subtitle: Text? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public init(_ title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil) {
        self.title = Text(title)
        self.subtitle = subtitle.map(Text.init)
    }

    public init(verbatim title: String, subtitle: LocalizedStringResource? = nil) { // l10n:content
        self.title = Text(verbatim: title)
        self.subtitle = subtitle.map(Text.init)
    }

    public var body: some View {
        HStack(alignment: .center, spacing: SettingsFormMetrics.controlSpacing) {
            #if os(tvOS)
            if let backButton {
                backButton.fixedSize()
            }
            #endif
            heading
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                subtitle
                    #if os(tvOS)
                    .font(SettingsRowMetrics.helperFont)
                    #else
                    .font(.subheadline)
                    #endif
                    .plozzForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

public struct SettingsBackButton: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label("Back", systemImage: "chevron.backward")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .fixedSize()
    }
}
#endif
