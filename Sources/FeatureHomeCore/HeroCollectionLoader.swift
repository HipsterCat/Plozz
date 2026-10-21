import CoreModels
import Foundation

/// Samples a bounded window, retaining the server's order within that window.
public enum HeroCollectionLoader {
    public static func load(
        selection: HeroCollectionSelection,
        limit: Int,
        provider: any MediaProvider,
        visibility: HomeLibraryVisibility,
        seed: UInt64 = 0
    ) async throws -> MediaPage {
        guard !selection.collectionID.isEmpty, selection.libraryID?.isEmpty != true, limit > 0 else {
            throw AppError.invalidResponse
        }
        guard selection.libraryKey.map(visibility.isEnabled) != false else {
            return MediaPage(items: [], startIndex: 0, totalCount: 0)
        }
        let budget = min(limit, HeroFreshnessSnapshot.rawDiscoveryLimit)
        var items: [MediaItem] = []
        var seen = Set<String>()
        var start = 0
        var total = 0
        var scanned = 0
        var choseWindow = false
        repeat {
            try Task.checkCancellation()
            let page = try await provider.collectionMembers(
                of: selection.collectionID,
                page: PageRequest(startIndex: start, limit: min(PageRequest.defaultLimit, budget - scanned))
            )
            try Task.checkCancellation()
            guard page.startIndex == start, page.totalCount >= 0,
                  page.items.count <= budget - scanned,
                  page.endIndex <= page.totalCount,
                  !page.items.isEmpty || start >= page.totalCount else {
                throw AppError.invalidResponse
            }
            total = page.totalCount
            if !choseWindow {
                choseWindow = true
                if total > budget {
                    let offset = Int(seed % UInt64(total - budget + 1))
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
        } while start < total && scanned < budget
        return MediaPage(items: items, startIndex: 0, totalCount: total)
    }
}
