import CoreModels
import Foundation
import Observation

@MainActor
@Observable
final class DetailPlaybackInventoryState {
    var noStreamItemIDs: Set<String> = []
    var retryingItemIDs: Set<String> = []
    var retryError: LocalizedStringResource?

    func reset() {
        noStreamItemIDs.removeAll()
        retryingItemIDs.removeAll()
        retryError = nil
    }
}

@MainActor
@Observable
final class EpisodeBadgeEnrichmentModel {
    private var itemsByID: [String: MediaItem] = [:]

    subscript(id: String) -> MediaItem? { itemsByID[id] }

    func store(_ item: MediaItem) {
        itemsByID[item.id] = item
    }

    func reset() {
        itemsByID.removeAll()
    }
}
