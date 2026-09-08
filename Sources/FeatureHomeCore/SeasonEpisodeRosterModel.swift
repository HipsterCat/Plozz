import CoreModels
import Foundation
import Observation

/// View-scoped metadata state, separate from playable episodes and their cache.
@Observable
@MainActor
final class SeasonEpisodeRosterModel {
    private var states: [Int: SeasonEpisodeRosterLoadState] = [:]
    private struct Load: Sendable {
        let token: UUID
        let task: Task<Void, Never>
    }
    @ObservationIgnored private nonisolated(unsafe) var loads: [Int: Load] = [:]

    deinit {
        loads.values.forEach { $0.task.cancel() }
    }

    func state(for number: Int) -> SeasonEpisodeRosterLoadState {
        states[number] ?? .notLoaded
    }

    func reset() {
        let cancelled = loads.values
        loads.removeAll()
        cancelled.forEach { $0.task.cancel() }
        states = [:]
    }

    func markUnavailable(for number: Int) {
        loads.removeValue(forKey: number)?.task.cancel()
        states[number] = .unavailable
    }

    func load(
        item: MediaItem,
        number: Int,
        seriesTMDbID: Int,
        forceRefresh: Bool,
        loader: @escaping @Sendable (MediaItem, Int) async -> SeasonEpisodeRosterResult,
        isCurrent: @escaping @MainActor () -> Bool
    ) async {
        guard !Task.isCancelled else { return }
        if let existing = loads[number] {
            if !forceRefresh {
                await existing.task.value
                return
            }
            loads.removeValue(forKey: number)
            existing.task.cancel()
        }
        if !forceRefresh {
            switch state(for: number) {
            case .loaded, .unavailable, .failed: return
            case .notLoaded, .loading: break
            }
        }

        let token = UUID()
        states[number] = .loading
        let task = Task { @MainActor [weak self] in
            defer {
                if let self, self.loads[number]?.token == token {
                    self.loads.removeValue(forKey: number)
                    if self.states[number] == .loading {
                        self.states.removeValue(forKey: number)
                    }
                }
            }
            let result = await loader(item, number)
            guard !Task.isCancelled,
                  let self, self.loads[number]?.token == token,
                  isCurrent() else { return }
            switch result {
            case .loaded(let roster)
                where roster.seriesTMDbID == seriesTMDbID && roster.seasonNumber == number:
                self.states[number] = .loaded(roster)
            case .loaded, .failed:
                self.states[number] = .failed
            case .unavailable:
                self.states[number] = .unavailable
            }
        }
        loads[number] = Load(token: token, task: task)
        await task.value
    }
}
