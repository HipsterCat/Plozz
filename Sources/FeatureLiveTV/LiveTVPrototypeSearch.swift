import PlozzCoreUI
import FeatureLiveTVCore
import SwiftUI

#if os(iOS)
import UIKit

struct PrototypeSearchHeader: View {
    @Binding var query: String
    let channelCount: Int
    let category: String?
    let focusRequest: Int
    let browse: () -> Void
    let close: () -> Void
    let focusChanged: (Bool) -> Void
    var showsSummary = true
    @State private var isEditing = false
    @State private var dismissRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
            HStack(spacing: PrototypeLayout.smallGap) {
                PrototypeMobileSearchField(
                    query: $query, focusRequest: focusRequest, dismissRequest: dismissRequest,
                    submit: browse,
                    focusChanged: {
                        isEditing = $0
                        focusChanged($0)
                    }
                )
                .frame(height: 44)
                if isEditing {
                    Button("Cancel") {
                        dismissRequest &+= 1
                        query = ""
                        close()
                    }
                }
            }
            if showsSummary {
                PrototypeSearchSummary(channelCount: channelCount, category: category)
            }
        }
    }
}

private struct PrototypeMobileSearchField: UIViewRepresentable {
    @Binding var query: String
    @Environment(\.locale) private var locale
    let focusRequest: Int
    let dismissRequest: Int
    let submit: () -> Void
    let focusChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISearchTextField {
        let field = UISearchTextField()
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.accessibilityIdentifier = "live-tv-search-field"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UISearchTextField, context: Context) {
        context.coordinator.parent = self
        let placeholder = LocalizedStringResource("Search", locale: locale)
        field.placeholder = String(localized: placeholder) // l10n:content - UIKit boundary, refreshed with the current environment locale.
        if field.text != query { field.text = query }
        if dismissRequest > context.coordinator.dismissRequest {
            context.coordinator.dismissRequest = dismissRequest
            DispatchQueue.main.async { [weak field] in
                field?.resignFirstResponder()
            }
        }
        if focusRequest > context.coordinator.focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { [weak field] in
                guard let field, field.window != nil else { return }
                field.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PrototypeMobileSearchField
        var focusRequest = 0
        var dismissRequest = 0
        init(_ parent: PrototypeMobileSearchField) { self.parent = parent }
        @objc func textChanged(_ field: UISearchTextField) {
            parent.query = field.text ?? ""
        }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.focusChanged(true)
        }
        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.focusChanged(false)
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.submit()
            return true
        }
        func textFieldShouldClear(_ textField: UITextField) -> Bool {
            parent.query = ""
            return true
        }
    }
}
#endif

struct PrototypeCategorySearchResults: View {
    let categories: [LiveTVBrowseCategory]
    let select: (String) -> Void
    @Environment(\.themePalette) private var palette
    #if os(tvOS)
    @ScaledMetric(relativeTo: .headline) private var tileHeight: CGFloat = 128
    #else
    @ScaledMetric(relativeTo: .headline) private var tileHeight: CGFloat = 68
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
            Text("Categories")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            ScrollView(.horizontal) {
                LazyHStack(spacing: PrototypeLayout.gap) {
                    ForEach(categories) { category in
                        PrototypeCategoryTile(name: category.name, count: category.channelCount) {
                            select(category.name)
                        }
                        .frame(width: PrototypeCategoryTile.searchWidth)
                        .accessibilityIdentifier("live-tv-search-category-\(category.name)")
                    }
                }
                .padding(PrototypeLayout.gap)
            }
            .scrollIndicators(.hidden)
            .frame(height: tileHeight + PrototypeLayout.gap * 4)
            .padding(.horizontal, -PrototypeLayout.gap)
        }
        .accessibilityIdentifier("live-tv-search-categories")
    }
}

private struct PrototypeSearchResultsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var prototypeSearchResults: Bool {
        get { self[PrototypeSearchResultsKey.self] }
        set { self[PrototypeSearchResultsKey.self] = newValue }
    }
}

struct PrototypeSearchResults<Content: View>: View {
    let content: Content
    var body: some View { content.environment(\.prototypeSearchResults, true) }
}

struct PrototypeSearchFocusBoundary<Content: View>: View {
    @Environment(\.prototypeSearchResults) private var isSearchResult
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(tvOS)
        if isSearchResult {
            PrototypeSearchRowHost(content: content())
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

#if os(tvOS)
import UIKit

/// Give native Search a row-sized focused UIView, not the entire lazy stack.
/// Its keyboard-collapse scrolling still runs unchanged using this real boundary.
struct PrototypeSearchRowHost<Content: View>: UIViewControllerRepresentable {
    let content: Content

    struct HostedContent: View {
        let content: Content
        let environment: EnvironmentValues
        var body: some View { content.environment(\.self, environment) }
    }

    func makeUIViewController(context: Context) -> UIHostingController<HostedContent> {
        let controller = UIHostingController(rootView: HostedContent(content: content, environment: context.environment))
        controller.view.backgroundColor = .clear
        controller.safeAreaRegions = []
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<HostedContent>, context: Context) {
        controller.rootView = HostedContent(content: content, environment: context.environment)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, uiViewController: UIHostingController<HostedContent>, context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiViewController.sizeThatFits(in: CGSize(width: width, height: UIView.layoutFittingExpandedSize.height))
    }
}
#endif
