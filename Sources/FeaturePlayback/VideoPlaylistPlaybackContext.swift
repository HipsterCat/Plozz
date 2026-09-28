import CoreModels
import Foundation
import Observation

/// A playback-only, account-owned sparse view of a server playlist. A grid
/// selection seeds its known item; remaining entries are fetched only when
/// visible in the player or needed for advancement.
@MainActor
@Observable
public final class VideoPlaylistPlaybackContext {
    private struct InFlight {
        let id: UUID
        let task: Task<MediaPage, Error>
        var waiters: Set<UUID>
    }

    public let playlistID: String
    public let accountID: String
    public private(set) var currentIndex: Int
    public private(set) var totalCount: Int
    public private(set) var items: [Int: MediaItem]
    public private(set) var loadError: AppError?
    public private(set) var retryGeneration = 0

    private let provider: any MediaProvider
    private let pageSize = 24
    @ObservationIgnored private var inFlight: [Int: InFlight] = [:]

    public init(origin: VideoPlaylistPlaybackOrigin, provider: any MediaProvider) {
        playlistID = origin.playlistID
        accountID = origin.accountID
        currentIndex = origin.index
        totalCount = origin.totalCount
        items = [origin.index: origin.item]
        self.provider = provider
    }

    public func item(at index: Int) async throws -> MediaItem? {
        guard index >= 0, index < totalCount else { return nil }
        if let item = items[index] { return item }
        let pageStart = (index / pageSize) * pageSize
        let waiterID = UUID()
        let request: InFlight
        if var existing = inFlight[pageStart] {
            existing.waiters.insert(waiterID)
            inFlight[pageStart] = existing
            request = existing
        } else {
            let provider = provider
            let playlistID = playlistID
            let requestedSize = pageSize
            request = InFlight(
                id: UUID(),
                task: Task {
                    try await Self.fetchPage(
                        provider: provider, playlistID: playlistID,
                        startIndex: pageStart, limit: requestedSize
                    )
                },
                waiters: [waiterID]
            )
            inFlight[pageStart] = request
        }
        do {
            let page = try await withTaskCancellationHandler {
                try await request.task.value
            } onCancel: {
                Task { @MainActor in
                    self.cancelWaiter(pageStart: pageStart, id: request.id, waiterID: waiterID)
                }
            }
            try Task.checkCancellation()
            guard page.startIndex == pageStart, page.totalCount >= 0,
                  page.items.count <= pageSize, page.endIndex <= page.totalCount else {
                throw AppError.invalidResponse
            }
            if inFlight[pageStart]?.id == request.id {
                totalCount = page.totalCount
                for (offset, member) in page.items.enumerated() {
                    items[pageStart + offset] = member.taggingSource(accountID)
                }
                inFlight[pageStart] = nil
                loadError = nil
            }
            return items[index]
        } catch {
            if Task.isCancelled {
                cancelWaiter(pageStart: pageStart, id: request.id, waiterID: waiterID)
            } else if inFlight[pageStart]?.id == request.id {
                inFlight[pageStart] = nil
            }
            if !(error is CancellationError), !Task.isCancelled {
                loadError = error as? AppError ?? .invalidResponse
            }
            throw error
        }
    }

    private nonisolated static func fetchPage(
        provider: any MediaProvider, playlistID: String, startIndex: Int, limit: Int
    ) async throws -> MediaPage {
        var members: [MediaItem] = []
        var totalCount: Int?
        while members.count < limit {
            try Task.checkCancellation()
            let start = startIndex + members.count
            if let totalCount, start >= totalCount { break }
            let page = try await provider.videoPlaylistMembers(
                of: playlistID,
                page: PageRequest(startIndex: start, limit: limit - members.count)
            )
            guard page.startIndex == start, page.totalCount >= 0,
                  page.items.count <= limit - members.count,
                  page.endIndex <= page.totalCount,
                  !page.items.isEmpty || start >= page.totalCount else {
                throw AppError.invalidResponse
            }
            totalCount = page.totalCount
            members.append(contentsOf: page.items)
            if page.items.isEmpty { break }
        }
        return MediaPage(items: members, startIndex: startIndex, totalCount: totalCount ?? 0)
    }

    private func cancelWaiter(pageStart: Int, id: UUID, waiterID: UUID) {
        guard var request = inFlight[pageStart], request.id == id else { return }
        guard request.waiters.remove(waiterID) != nil else { return }
        if request.waiters.isEmpty {
            inFlight[pageStart] = nil
            request.task.cancel()
        } else {
            inFlight[pageStart] = request
        }
    }

    public func advance(to index: Int) {
        guard index >= 0, index < totalCount, items[index] != nil else { return }
        currentIndex = index
    }

    public func retry() {
        loadError = nil
        retryGeneration &+= 1
    }
}
