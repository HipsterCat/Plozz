#if canImport(SwiftUI)
import CoreModels
import SwiftUI

/// Shared playback chrome. Hosts retain ownership of recovery, navigation and focus.
public struct PlaybackFailureView<Actions: View>: View {
    private let title: LocalizedStringResource
    private let message: LocalizedStringResource
    private let systemImage: String
    private let report: PlaybackDiagnosticReport?
    private let actions: Actions
    @State private var showsDetails = false

    public init(
        title: LocalizedStringResource = "Can’t play this right now",
        message: LocalizedStringResource,
        systemImage: String = "exclamationmark.triangle",
        report: PlaybackDiagnosticReport?,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.report = report
        self.actions = actions()
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    PlaybackFailureHeading(title: title, message: message, systemImage: systemImage)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            PlaybackFailureDetailsButton(isAvailable: report != nil, showsDetails: $showsDetails)
                            actions
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            PlaybackFailureDetailsButton(isAvailable: report != nil, showsDetails: $showsDetails)
                            actions
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Self.cardPadding)
                .frame(maxWidth: Self.cardWidth, alignment: .leading)
                .plozzSurface(.raised, cornerRadius: 28)
                .padding(Self.outerPadding)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityIdentifier("playback-failure")
        .plozzSheet(isPresented: $showsDetails) {
            if let report { PlaybackDiagnosticDetailsSheet(report: report) }
        }
        .environment(\.themePalette, .dark)
        .environment(\.colorScheme, .dark)
    }

    #if os(tvOS)
    private static var cardWidth: CGFloat { 960 }
    private static var cardPadding: CGFloat { 48 }
    private static var outerPadding: CGFloat { 60 }
    #else
    private static var cardWidth: CGFloat { 560 }
    private static var cardPadding: CGFloat { 24 }
    private static var outerPadding: CGFloat { 20 }
    #endif
}

private struct PlaybackFailureHeading: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.yellow)
                    .fixedSize()
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("playback-failure-message")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlaybackFailureDetailsButton: View {
    let isAvailable: Bool
    @Binding var showsDetails: Bool

    var body: some View {
        if isAvailable {
            Button("Details", systemImage: "info.circle") { showsDetails = true }
                .plozzActionButton(role: .secondary)
                .accessibilityIdentifier("playback-failure-details")
        }
    }
}
#endif
