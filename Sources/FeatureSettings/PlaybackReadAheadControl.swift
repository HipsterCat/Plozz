#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct PlaybackReadAheadControl: View {
    @AppStorage private var selection: PlaybackReadAhead

    public init(defaults: UserDefaults = .standard) {
        _selection = AppStorage(
            wrappedValue: PlaybackReadAhead.default,
            PlaybackReadAheadStore.storageKey,
            store: defaults
        )
    }

    public var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 28) {
            SettingsOptionList(options: PlaybackReadAhead.allCases, selection: $selection) {
                Text($0.title)
            }
            PlaybackReadAheadHelp()
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        #else
        SettingsSectionGroup {
            Picker("Video buffer", selection: $selection) {
                ForEach(PlaybackReadAhead.allCases, id: \.self) {
                    Text($0.title).tag($0)
                }
            }
            .accessibilityIdentifier("playback-read-ahead")
        } footer: {
            PlaybackReadAheadHelp()
        }
        #endif
    }
}

private struct PlaybackReadAheadHelp: View {
    var body: some View {
        Text("Larger buffers use more storage. Unavailable with Apple’s native player.")
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
