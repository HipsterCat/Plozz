import SwiftUI
import CoreModels

public struct BrowseQueryControls<Content: View>: View {
    @Environment(\.themePalette) private var palette
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        #if os(tvOS)
        HStack(spacing: PlozzTheme.Spacing.medium) { content }
        #else
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { content.fixedSize() }
            VStack(alignment: .leading, spacing: 4) { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.subheadline)
        .tint(palette.primaryText)
        #endif
    }
}

public struct BrowseSortMenu: View {
    private let sort: CoreModels.SortDescriptor
    private let fields: [SortField]
    private let onChange: (CoreModels.SortDescriptor) -> Void

    public init(
        sort: CoreModels.SortDescriptor,
        fields: [SortField],
        onChange: @escaping (CoreModels.SortDescriptor) -> Void
    ) {
        self.sort = sort
        self.fields = fields
        self.onChange = onChange
    }

    public var body: some View {
        Menu {
            Picker("Sort By", selection: Binding(
                get: { sort.field },
                set: { onChange(.init(field: $0, direction: $0.defaultDirection)) }
            )) {
                ForEach(fields, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Order", selection: Binding(
                get: { sort.direction },
                set: { onChange(.init(field: sort.field, direction: $0)) }
            )) {
                ForEach(SortDirection.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        } label: {
            Label {
                Text(sort.field.displayName)
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
            #if os(iOS)
            .frame(minWidth: 44, minHeight: 44)
            #endif
        }
        .accessibilityLabel(Text("Sort: \(sort.field.displayName)"))
    }
}

public struct BrowseFilterMenu<Content: View>: View {
    private let activeCount: Int
    private let summary: String
    private let content: Content

    public init(activeCount: Int, summary: String, @ViewBuilder content: () -> Content) {
        self.activeCount = activeCount
        self.summary = summary
        self.content = content()
    }

    public var body: some View {
        Menu {
            content
        } label: {
            BrowseFilterLabel(activeCount: activeCount, summary: summary)
        }
    }
}

public struct BrowseFilterLabel: View {
    @Environment(\.locale) private var locale
    private let activeCount: Int
    private let summary: String

    public init(activeCount: Int, summary: String) {
        self.activeCount = activeCount
        self.summary = summary
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            Label {
                Text(verbatim: selection)
            } icon: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .fixedSize()
            if activeCount > 0 {
                Label {
                    Text(activeCount, format: .number)
                } icon: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .fixedSize()
            }
        }
        .accessibilityLabel(Text("Filter: \(selection)"))
    }

    private var selection: String {
        if activeCount == 0 {
            return String(localized: "All", locale: locale) // l10n:content — resolves the shared unfiltered choice
        }
        return summary
    }
}
