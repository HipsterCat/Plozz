import CoreModels

/// One library's unmerged Home block: the library itself (for the tappable
/// section header + routing into full browse) paired with its ordered content
/// rows (uniform base sections + any provider-native discovery hubs).
///
/// Produced by the aggregator only in **unmerged** mode; merged mode continues to
/// use the fixed `HomeRow`/`HomeRowKind` model untouched. Kept SwiftUI-free so it
/// stays testable on any platform.
public struct HomeLibrarySectionGroup: Identifiable, Equatable, Sendable {
    /// The owning library — drives the section heading (name + provider mark) and
    /// the "browse everything" destination when the header is selected.
    public let library: AggregatedLibrary

    /// The library's completed, nonempty rows in display order.
    public var sections: [LibrarySection]
    public var loadingRows: Set<LibraryHomeRowKind>
    public var failures: [LibraryHomeRowKind: AppError]

    /// Stable identity for SwiftUI — the library's cross-account key.
    public var id: String { library.key }

    public init(
        library: AggregatedLibrary,
        sections: [LibrarySection],
        loadingRows: Set<LibraryHomeRowKind> = [],
        failures: [LibraryHomeRowKind: AppError] = [:]
    ) {
        self.library = library
        self.sections = sections
        self.loadingRows = loadingRows
        self.failures = failures
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public let section: LibrarySection
        public let isLoading: Bool
        public let failure: AppError?
        public var id: String { section.id }
    }

    /// Loading and loaded Recently Added share a slot, including in Showcase.
    public var rows: [Row] {
        var result = sections.map { Row(section: $0, isLoading: false, failure: nil) }
        for kind in LibraryHomeRowKind.allCases {
            guard loadingRows.contains(kind) || failures[kind] != nil else { continue }
            let row = Row(
                section: LibrarySection(
                    id: kind == .recentlyAdded ? "recentlyAdded" : "pending-hubs",
                    title: library.library.title, style: .poster, items: []
                ),
                isLoading: loadingRows.contains(kind),
                failure: failures[kind]
            )
            if kind == .recentlyAdded {
                result.insert(row, at: 0)
            } else {
                result.append(row)
            }
        }
        return result
    }

    /// Total cards across all of the group's rows — used for skeleton sizing and
    /// telemetry.
    public var cardCount: Int { sections.reduce(0) { $0 + $1.items.count } }

    /// Whether the group has anything to show (at least one non-empty row).
    public var isEmpty: Bool {
        sections.allSatisfy { $0.items.isEmpty } && loadingRows.isEmpty && failures.isEmpty
    }
}
