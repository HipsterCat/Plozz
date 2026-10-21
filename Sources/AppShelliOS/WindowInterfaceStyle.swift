#if canImport(UIKit)
import SwiftUI
import UIKit

/// Explicit themes also style UIKit menus and sheets. System must leave the
/// window unspecified so the root can keep observing real device changes.
private struct WindowInterfaceStyleModifier: ViewModifier {
    let colorScheme: ColorScheme?

    func body(content: Content) -> some View {
        content.background(WindowInterfaceStyleApplier(style: colorScheme.map {
            $0 == .light ? .light : .dark
        } ?? .unspecified))
    }
}

private struct WindowInterfaceStyleApplier: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> StyleApplierView {
        StyleApplierView(style: style)
    }

    func updateUIView(_ uiView: StyleApplierView, context: Context) {
        uiView.apply(style)
    }

    final class StyleApplierView: UIView {
        private var style: UIUserInterfaceStyle

        init(style: UIUserInterfaceStyle) {
            self.style = style
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func apply(_ style: UIUserInterfaceStyle) {
            self.style = style
            if window?.overrideUserInterfaceStyle != style {
                window?.overrideUserInterfaceStyle = style
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.overrideUserInterfaceStyle = style
        }
    }
}

extension View {
    /// Pass the selected theme's preference, never the resolved device scheme.
    func syncsWindowInterfaceStyle(_ colorScheme: ColorScheme?) -> some View {
        modifier(WindowInterfaceStyleModifier(colorScheme: colorScheme))
    }
}
#endif
