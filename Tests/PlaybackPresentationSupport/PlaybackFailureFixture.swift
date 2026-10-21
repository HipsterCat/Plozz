import CoreModels
import CoreUI
@testable import FeaturePlayback
import SwiftUI

struct PlaybackFailureFixture: View {
    @State private var closed = false
    @State private var action = ""
    private var arguments: [String] { ProcessInfo.processInfo.arguments }

    private var report: PlaybackDiagnosticReport {
        if arguments.contains("--failure-live") {
            return .playback(.init(failure: .startupTimedOut))
        }
        let error: StreamingQualityError = arguments.contains("--failure-long")
            ? .serverRefusal(
                "Silo returned a different file than the selected version. Plozz stopped playback to avoid playing the wrong file.",
                reason: .sourceMismatch
            )
            : .playback(.init(kind: .unavailable, httpStatus: 410, engineFailure: .sourceRefused))
        return .onDemand(error: error, provider: .silo, engine: .plozzigen, stage: .opening)
    }

    var body: some View {
        Group {
            if closed {
                Text(verbatim: "Playback closed").accessibilityIdentifier("failure-fixture-closed")
            } else if arguments.contains("--failure-live") {
                PlaybackFailureView(title: "Playback timed out", message: report.message!, report: report) {
                    Button("Retry") { action = "Retried" }.plozzActionButton(role: .primary)
                        .accessibilityIdentifier("playback-failure-retry")
                    Button("Close") { closed = true }.plozzActionButton(role: .secondary)
                }
            } else {
                StreamingPlaybackFailureView(
                    message: report.message!, report: report,
                    onRetry: { action = "Retried" }, onDismiss: { closed = true }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .overlay(alignment: .bottom) {
            Text(verbatim: action).foregroundStyle(.white).accessibilityIdentifier("failure-fixture-action")
        }
        .environment(\.themePalette, arguments.contains("--failure-light") ? .light : .dark)
        .environment(\.colorScheme, arguments.contains("--failure-light") ? .light : .dark)
        .environment(\.layoutDirection, arguments.contains("--failure-rtl") ? .rightToLeft : .leftToRight)
        .environment(\.plozzReducePanelGlass, arguments.contains("--failure-reduced"))
        .environment(\.plozzReduceTransparency, arguments.contains("--failure-reduced"))
        #if os(iOS)
        .dynamicTypeSize(arguments.contains("--failure-large") ? .accessibility3 : .large)
        #endif
    }
}
