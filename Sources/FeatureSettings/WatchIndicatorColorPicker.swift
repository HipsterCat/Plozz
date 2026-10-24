#if canImport(SwiftUI)
import CoreModels
import PlozzCoreUI
import SwiftUI

struct WatchIndicatorColorPicker: View {
    @Binding var selection: WatchIndicatorColor
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Color")
                Spacer(minLength: 0)
                Text(selection.displayName)
                    .foregroundStyle(palette.secondaryText)
            }
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(WatchIndicatorColor.allCases) { color in
                            ColorSwatchButton(
                                title: color.displayName,
                                color: MediaWatchIndicatorStyle.fill(color),
                                foreground: MediaWatchIndicatorStyle.foreground(color),
                                isSelected: selection == color
                            ) {
                                selection = color
                            }
                            .id(color)
                            .accessibilityIdentifier("watch-indicator-color-\(color.rawValue)")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                #if os(tvOS)
                .scrollClipDisabled()
                #endif
                .onAppear { proxy.scrollTo(selection) }
                .onChange(of: selection) { _, color in proxy.scrollTo(color) }
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .accessibilityIdentifier("watch-indicator-color")
    }
}
#endif
