import Foundation

/// Content and presentation are independent of the page's order and visibility.
public struct CollectionSection: Codable, Equatable, Sendable, Identifiable {
    public enum CardStyle: String, Codable, CaseIterable, Sendable {
        case poster, landscape, featured

        public var title: LocalizedStringResource {
            switch self {
            case .poster: "Posters"
            case .landscape: "Landscape"
            case .featured: "Featured"
            }
        }
    }

    public let id: String
    public var name: String // l10n:content — user-authored section name
    public var source: HeroCollectionSelection
    public var cardStyle: CardStyle

    public init(
        id: String = UUID().uuidString, name: String = "",
        source: HeroCollectionSelection, cardStyle: CardStyle = .poster
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.cardStyle = cardStyle
    }

    public var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? source.title : trimmed
    }

    public var rowID: HomeRowID { .section(id) }

    public var collectionItem: MediaItem {
        MediaItem(id: source.collectionID, title: source.title, kind: .collection)
            .taggingSource(source.accountID)
            .taggingLibrary(source.libraryID)
    }
}
