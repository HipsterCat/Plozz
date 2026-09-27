#if os(tvOS)
import SwiftUI
import UIKit

/// Adjustable subtitle rows own horizontal movement even when UIKit finds a
/// diagonal Back button. Vertical movement and non-adjustable rows stay native.
struct SubtitleStyleFocusScope<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let canAdjust: () -> Bool

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller(rootView: AnyView(content.environment(\.self, context.environment)))
        controller.view.backgroundColor = .clear
        controller.safeAreaRegions = []
        controller.canAdjust = canAdjust
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.rootView = AnyView(content.environment(\.self, context.environment))
        controller.canAdjust = canAdjust
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: Controller, context: Context) -> CGSize? {
        uiViewController.sizeThatFits(in: CGSize(
            width: proposal.width ?? SubtitleStylePanel.panelWidth,
            height: proposal.height ?? .greatestFiniteMagnitude
        ))
    }

    final class Controller: UIHostingController<AnyView> {
        var canAdjust: (() -> Bool)?

        override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
            if owns(context.previouslyFocusedItem), canAdjust?() == true,
               !context.focusHeading.intersection([.left, .right]).isEmpty {
                // A rejected focus move falls through to the content's move
                // command. Adjust there, once, not during focus eligibility.
                return false
            }
            return super.shouldUpdateFocus(in: context)
        }

        private func owns(_ item: (any UIFocusItem)?) -> Bool {
            var environment: (any UIFocusEnvironment)? = item
            while let current = environment {
                if current === self || current === view { return true }
                environment = current.parentFocusEnvironment
            }
            return false
        }
    }
}
#endif
