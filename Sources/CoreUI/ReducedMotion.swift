import SwiftUI

/// Stops app-owned animation without changing layout, view identity, or focus targets.
public struct ReducedMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func body(content: Content) -> some View {
        content.transaction {
            if reduceMotion {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        }
    }
}
