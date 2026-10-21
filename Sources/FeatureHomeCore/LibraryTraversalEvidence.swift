import Foundation

public struct LibraryTraversalSnapshot: Codable, Sendable {
    public struct Event: Codable, Sendable {
        public let sequence: Int
        public let uptime: TimeInterval
        public let from: Int?
        public let to: Int?
        public let loaded: Bool
    }

    public let identity: UUID
    public let generation: Int
    public let columns: Int
    public let total: Int
    public let sequence: Int
    public let focusedIndex: Int?
    public let events: [Event]
}

/// Controller-local, opt-in recording. Encoding and validation happen outside input windows.
public struct LibraryTraversalRecorder {
    private let identity = UUID()
    private let capacity: Int
    private var sequence = 0
    private var focusedIndex: Int?
    private var events: [LibraryTraversalSnapshot.Event] = []

    public init(capacity: Int = 512) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public mutating func record(from: Int?, to: Int?, loaded: Bool, uptime: TimeInterval) {
        focusedIndex = to
        guard from != to else { return }
        sequence += 1
        if events.count == capacity { events.removeFirst() }
        events.append(.init(sequence: sequence, uptime: uptime, from: from, to: to, loaded: loaded))
    }

    public func snapshot(generation: Int, columns: Int, total: Int) -> LibraryTraversalSnapshot {
        .init(
            identity: identity, generation: generation, columns: columns, total: total,
            sequence: sequence, focusedIndex: focusedIndex, events: events
        )
    }
}

public enum LibraryTraversalValidation {
    public enum Mode {
        case idle
        case stepped(path: [Int])
        case held(minimumRows: Int)
    }

    public enum Failure: String, Error {
        case invalidWindow
        case changedGrid
        case incompleteHistory
        case invalidFocus
        case incompleteTraversal
    }

    public struct Evidence: Codable, Sendable {
        public let transitions: Int
        public let deepestRow: Int
        public let events: [LibraryTraversalSnapshot.Event]
    }

    public static func validate(
        before: LibraryTraversalSnapshot,
        after: LibraryTraversalSnapshot,
        start: TimeInterval,
        end: TimeInterval,
        mode: Mode
    ) throws -> Evidence {
        guard start.isFinite, end.isFinite, start < end else { throw Failure.invalidWindow }
        guard before.identity == after.identity, before.generation == after.generation,
              before.columns > 0, before.columns == after.columns,
              before.total > 0, before.total == after.total else { throw Failure.changedGrid }
        let history = after.events.filter { $0.sequence > before.sequence }
        guard after.sequence >= before.sequence, history.count == after.sequence - before.sequence,
              history.enumerated().allSatisfy({ $0.element.sequence == before.sequence + $0.offset + 1 }),
              history.allSatisfy({ $0.uptime.isFinite }),
              zip(history, history.dropFirst()).allSatisfy({ $0.uptime <= $1.uptime }) else {
            throw Failure.incompleteHistory
        }
        let events = history.filter { $0.uptime >= start && $0.uptime <= end }
        guard let initial = before.focusedIndex, initial >= 0, initial < before.total,
              after.focusedIndex == initial else { throw Failure.invalidFocus }
        var current = initial
        var deepest = initial
        for event in events {
            guard event.from == current, let next = event.to, event.loaded,
                  next >= initial, next < before.total,
                  next % before.columns == initial % before.columns else {
                throw Failure.invalidFocus
            }
            current = next
            deepest = max(deepest, next)
        }
        guard current == initial else { throw Failure.incompleteTraversal }
        switch mode {
        case .idle:
            guard events.isEmpty else { throw Failure.incompleteTraversal }
        case let .stepped(path):
            guard path.count > 1, path.first == initial,
                  zip(path, path.dropFirst()).allSatisfy({ $1 - $0 == before.columns }),
                  events.compactMap(\.to) == Array(path.dropFirst()) + Array(path.dropLast().reversed()) else {
                throw Failure.incompleteTraversal
            }
        case let .held(minimumRows):
            guard minimumRows > 0, (deepest - initial) / before.columns >= minimumRows else {
                throw Failure.incompleteTraversal
            }
            var returning = false
            for event in events {
                guard let from = event.from, let to = event.to, to != from else {
                    throw Failure.invalidFocus
                }
                if to < from { returning = true }
                if returning, to > from { throw Failure.incompleteTraversal }
            }
        }
        return Evidence(transitions: events.count, deepestRow: (deepest - initial) / before.columns, events: events)
    }
}
