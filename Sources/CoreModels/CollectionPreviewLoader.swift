import Foundation

/// A bounded preview, not a sorted or filtered approximation of the full collection.
public enum CollectionPreviewLoader {
    public static func load(
        selection: HeroCollectionSelection, limit: Int,
        provider: any MediaProvider, visibility: HomeLibraryVisibility,
        seed: UInt64 = 0
    ) async throws -> MediaPage {
        guard !selection.collectionID.isEmpty, selection.libraryID?.isEmpty != true, limit > 0 else {
            throw AppError.invalidResponse
        }
        guard selection.libraryKey.map(visibility.isEnabled) != false else {
            return MediaPage(items: [], startIndex: 0, totalCount: 0)
        }
        var items: [MediaItem] = []
        var seen = Set<String>()
        var start = 0
        var total = 0
        var scanned = 0
        var choseWindow = false
        repeat {
            try Task.checkCancellation()
            let request = PageRequest(startIndex: start, limit: min(PageRequest.defaultLimit, limit - scanned))
            let page = try await provider.collectionMembers(of: selection.collectionID, page: request)
            try Task.checkCancellation()
            guard page.startIndex == start, page.totalCount >= 0,
                  page.items.count <= request.limit, page.endIndex <= page.totalCount,
                  !page.items.isEmpty || start >= page.totalCount else {
                throw AppError.invalidResponse
            }
            total = page.totalCount
            if !choseWindow {
                choseWindow = true
                if total > limit {
                    let offset = Int(seed % UInt64(total - limit + 1))
                    if offset > 0 {
                        start = offset
                        continue
                    }
                }
            }
            guard page.items.allSatisfy({ !$0.id.isEmpty && seen.insert($0.id).inserted }) else {
                throw AppError.invalidResponse
            }
            start += page.items.count
            scanned += page.items.count
            items += page.items.map { $0.taggingSource(selection.accountID) }.filter {
                $0.isVisibleOnHome(isLibraryVisible: visibility.isEnabled)
            }
            if page.items.isEmpty { break }
        } while start < total && scanned < limit
        return MediaPage(items: items, startIndex: 0, totalCount: total)
    }
}
