#if canImport(SwiftUI)
import SwiftUI

/// Keeps diagnostics out of the visible transport, Info/Cast card, and menus.
/// Controls own their geometry; the diagnostics never move or take focus from them.
struct TelevisionDiagnosticsPlacement<Content: View>: View {
    let controlsLayout: SubtitleControlsLayout?
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { geometry in
            let bounds = geometry.frame(in: .global)
            let space = Self.availableRect(in: bounds, avoiding: controlsLayout?.frames ?? [])
            if !space.isEmpty {
                ViewThatFits(in: .vertical) {
                    content(space.width)
                    // A tall menu can leave no readable room. Restore the complete
                    // panel when it closes rather than clip data or cover controls.
                    Color.clear
                }
                .frame(width: space.width, height: space.height, alignment: .topLeading)
                .clipped()
                .offset(x: space.minX - bounds.minX, y: space.minY - bounds.minY)
            }
        }
        .allowsHitTesting(false)
    }

    static func availableRect(in bounds: CGRect, avoiding controls: [CGRect]) -> CGRect {
        var inset = bounds.insetBy(dx: min(48, bounds.width / 4), dy: min(32, bounds.height / 4))
        inset.size.width = min(inset.width, 1280)
        let top = controls
            .filter { !$0.isNull && !$0.isEmpty && $0.minY.isFinite && $0.intersects(inset) }
            .map(\.minY).min()
        let bottom = min(inset.maxY, top.map { $0 - 24 } ?? inset.maxY)
        return CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: max(0, bottom - inset.minY))
    }
}
#endif
