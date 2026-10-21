#if canImport(SwiftUI)
import CoreModels
import SwiftUI

public struct PlaybackDiagnosticDetailsView: View {
    public let report: PlaybackDiagnosticReport

    public init(report: PlaybackDiagnosticReport) { self.report = report }

    private var supportText: String { // l10n:content — technical support report
        let version = AppVersionIdentity.current
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if os(tvOS)
        let platform = "tvOS"
        #elseif os(iOS)
        let platform = "iOS"
        #else
        let platform = "macOS"
        #endif
        return report.supportText
            + "\napp_version=\(version.displayVersion)\napp_build=\(version.build)"
            + "\nplatform=\(platform)\nos_version=\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if !os(iOS)
                Text("Details")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                #endif
                if let message = report.message {
                    Text(message).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                if case .library(let diagnostic) = report {
                    ForEach(Array(diagnostic.failures.enumerated()), id: \.offset) { _, failure in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(failure.section.title).font(.headline)
                            InlineErrorMessage(Text(failure.error.userMessage))
                        }
                    }
                }
                if case .onDemand(let error, _, _, _, _, _) = report,
                   case .playback(let failure) = error,
                   failure.engineFailure != .sourceRefused, failure.engineFailure != .nativeItemFailed,
                   let reason = failure.engineFailure?.message, reason != report.message {
                    Text(reason).font(.callout).foregroundStyle(.secondary)
                }
                Text(verbatim: supportText)
                    #if os(tvOS)
                    .font(.system(.body, design: .monospaced))
                    #else
                    .font(.system(.callout, design: .monospaced))
                    #endif
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
                    #if os(iOS)
                    .textSelection(.enabled)
                    #elseif os(tvOS)
                    .focusable()
                    #endif
                    .accessibilityIdentifier("playback-diagnostic-report")
                Text("Sharing is optional. This report excludes server addresses, credentials, account names, and media titles.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                #if os(iOS)
                ShareLink(item: supportText) { Label("Share details", systemImage: "square.and.arrow.up") }
                    .plozzActionButton(role: .primary)
                #endif
            }
            .frame(maxWidth: 1_000, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background { SettingsPageBackground() }
        #if os(iOS)
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

public struct PlaybackDiagnosticDetailsSheet: View {
    private let report: PlaybackDiagnosticReport
    @Environment(\.dismiss) private var dismiss

    public init(report: PlaybackDiagnosticReport) { self.report = report }

    public var body: some View {
        NavigationStack {
            PlaybackDiagnosticDetailsView(report: report)
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("playback-diagnostics-close")
                    }
                    #else
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                    #endif
                }
        }
    }
}
#endif
