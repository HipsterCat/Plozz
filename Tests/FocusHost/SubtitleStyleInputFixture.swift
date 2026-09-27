import CoreModels
import CoreUI
import SwiftUI
@testable import FeaturePlayback

struct SubtitleStyleInputFixture: View {
    @State private var model = PlayerControlsModel()

    init() {
        let model = PlayerControlsModel()
        model.controlsVisible = true
        model.subtitleStyle = .default
        if ProcessInfo.processInfo.arguments.contains("--minimum-text-size") {
            model.subtitleStyle.fontScale = Double(SubtitleStyle.fontScalePercentages.first!) / 100
        } else if ProcessInfo.processInfo.arguments.contains("--maximum-text-size") {
            model.subtitleStyle.fontScale = Double(SubtitleStyle.fontScalePercentages.last!) / 100
        }
        _model = State(initialValue: model)
        PlayerScreenshotHook.pendingPanel = .subtitleStyle
    }

    var body: some View {
        PlayerControls(
            model: model, palette: .dark,
            actions: PlayerOptionsActions(setSubtitleStyle: { model.subtitleStyle = $0 }),
            onExitToSurface: {}
        )
        .background(.black)
        .overlay(alignment: .leading) {
            if ProcessInfo.processInfo.arguments.contains("--nearby-back") {
                Button("Nearby Back") {}
                    .offset(y: -150)
            }
        }
        .overlay(alignment: .topLeading) {
            Text(verbatim: String(Int((model.subtitleStyle.fontScale * 100).rounded())))
                .accessibilityIdentifier("subtitle-text-size-value")
                .allowsHitTesting(false)
        }
    }
}
