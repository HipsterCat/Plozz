import CoreModels

public struct HomeServerRow: Equatable, Sendable {
    public var definition: HomeServerRowDefinition
    public var items: [MediaItem]
    public var isLoading: Bool
    public var failure: AppError?

    public init(
        definition: HomeServerRowDefinition, items: [MediaItem] = [],
        isLoading: Bool = false, failure: AppError? = nil
    ) {
        self.definition = definition
        self.items = items
        self.isLoading = isLoading
        self.failure = failure
    }

    public var row: HomeLibrarySectionGroup.Row {
        .init(
            section: LibrarySection(
                id: definition.id.presentationID,
                title: definition.section.title ?? definition.section.kind.rawValue,
                localizedTitle: definition.section.title == nil ? definition.section.kind.title : nil,
                style: definition.section.kind == .nextUp ? .landscape : .poster,
                items: items
            ),
            isLoading: isLoading, failure: failure
        )
    }
}
