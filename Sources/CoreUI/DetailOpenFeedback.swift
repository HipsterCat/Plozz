#if canImport(SwiftUI)
import SwiftUI
#if os(iOS)
import UIKit

@MainActor
struct DetailOpenFeedbackModifier: ViewModifier {
    let playFeedback: @MainActor () -> Void
    @State private var hasOpened = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !hasOpened else { return }
            hasOpened = true
            playFeedback()
        }
    }
}
#endif

public extension View {
    /// One soft tap per presentation, not when an existing page reappears.
    @MainActor
    @ViewBuilder
    func detailOpenFeedback() -> some View {
        #if os(iOS)
        modifier(DetailOpenFeedbackModifier {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        })
        #else
        self
        #endif
    }
}
#endif
