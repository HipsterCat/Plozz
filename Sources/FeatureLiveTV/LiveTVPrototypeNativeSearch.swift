#if DEBUG && os(tvOS)
import SwiftUI
import UIKit

/// tvOS's inline keyboard and the existing guide share one search surface.
/// A TextField here would open another full-screen text-entry presentation.
struct PrototypeNativeSearch<Results: View>: UIViewControllerRepresentable {
    @Binding var query: String
    let restoresGuideFocus: Bool
    let isPresented: Bool
    let close: () -> Void
    let editing: () -> Void
    @ViewBuilder let results: () -> Results
    @Environment(\.locale) private var locale

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UISearchContainerViewController {
        let host = UIHostingController(rootView: results())
        host.view.backgroundColor = .clear
        let search = PrototypeSearchController(searchResultsController: host)
        search.searchBar.placeholder = String(localized: "Search channels", locale: locale)
        search.searchBar.text = query
        search.searchBar.autocorrectionType = .no
        search.searchBar.autocapitalizationType = .none
        search.searchResultsUpdater = context.coordinator
        search.searchBar.delegate = context.coordinator
        search.delegate = context.coordinator
        search.searchBar.accessibilityIdentifier = "live-tv-search-field"
        search.obscuresBackgroundDuringPresentation = false
        search.hidesNavigationBarDuringPresentation = false
        search.view.backgroundColor = .clear
        search.restoresGuideFocus = restoresGuideFocus
        let container = UISearchContainerViewController(searchController: search)
        container.view.backgroundColor = .clear
        context.coordinator.host = host
        return container
    }

    func updateUIViewController(_ controller: UISearchContainerViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.host?.rootView = results()
        let search = controller.searchController
        if search.searchBar.text != query { search.searchBar.text = query }
        search.view.isUserInteractionEnabled = context.environment.isEnabled
        if let search = search as? PrototypeSearchController,
           search.restoresGuideFocus != restoresGuideFocus {
            search.restoresGuideFocus = restoresGuideFocus
            search.setNeedsFocusUpdate()
        }
        if controller.view.window != nil, search.isActive != isPresented {
            search.isActive = isPresented
        }
    }

    static func dismantleUIViewController(_ controller: UISearchContainerViewController, coordinator: Coordinator) {
        controller.searchController.searchResultsUpdater = nil
        controller.searchController.searchBar.delegate = nil
        controller.searchController.delegate = nil
        controller.searchController.isActive = false
        coordinator.host = nil
    }

    final class Coordinator: NSObject, UISearchResultsUpdating, UISearchBarDelegate, UISearchControllerDelegate {
        var parent: PrototypeNativeSearch
        var host: UIHostingController<Results>?

        init(_ parent: PrototypeNativeSearch) { self.parent = parent }

        func updateSearchResults(for searchController: UISearchController) {
            let text = searchController.searchBar.text ?? ""
            if parent.query != text { parent.query = text }
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            Task { @MainActor [weak self] in
                guard let self, self.parent.isPresented, !self.parent.restoresGuideFocus else { return }
                self.parent.editing()
            }
        }
        func didDismissSearchController(_ searchController: UISearchController) {
            if parent.isPresented { parent.close() }
        }
    }
}

private final class PrototypeSearchController: UISearchController {
    var restoresGuideFocus = false

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        if restoresGuideFocus, let searchResultsController { return [searchResultsController] }
        return super.preferredFocusEnvironments
    }

    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        if restoresGuideFocus, let next = context.nextFocusedView,
           let results = searchResultsController?.view, !next.isDescendant(of: results) {
            return false
        }
        return super.shouldUpdateFocus(in: context)
    }
}
#endif
