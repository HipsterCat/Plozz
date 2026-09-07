#if DEBUG && os(iOS)
import CoreUI
import FeatureLiveTVCore
import SwiftUI

struct PrototypeSearchHeader: View {
    @Binding var query: String
    let channelCount: Int
    let category: String?
    let focusRequest: Int
    let browse: () -> Void
    let close: () -> Void
    let focusChanged: (Bool) -> Void
    @FocusState private var focused: Control?
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Control: Hashable { case query, clear }

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeLayout.gap) {
            HStack(spacing: PrototypeLayout.gap) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityHidden(true)
                TextField("Search channels", text: $query)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($focused, equals: .query)
                    .accessibilityIdentifier("live-tv-search-field")
                    .onSubmit {
                        focused = nil
                        browse()
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        focused = .query
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("Clear search")
                    .buttonStyle(PrototypeButtonStyle(surface: .control))
                    .focused($focused, equals: .clear)
                }
            }
            .font(.title2.weight(.semibold))
            .padding(PrototypeLayout.gap)
            .background { PrototypeControlSurface() }

            PrototypeSearchSummary(channelCount: channelCount, category: category)
        }
        .task(id: focusRequest) {
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(340)) }
            guard !Task.isCancelled else { return }
            focused = .query
        }
        .onChange(of: focused) { _, value in focusChanged(value != nil) }
        #if os(tvOS)
        .onMoveCommand { direction in
            if direction == .down, focused != nil {
                focused = nil
                browse()
            }
        }
        .onExitCommand(perform: close)
        #endif
    }
}
#endif
