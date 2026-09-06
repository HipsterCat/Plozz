import Foundation

/// One process-level application-activity transition.
///
/// Revisions are monotonic. Async consumers use them to reject stale work that
/// returns after a newer scene transition.
public struct ApplicationActivityTransition: Sendable, Equatable {
    public let isActive: Bool
    public let revision: UInt64

    public init(isActive: Bool, revision: UInt64) {
        self.isActive = isActive
        self.revision = revision
    }
}

/// Idempotent ownership for a finite background-execution assertion.
///
/// `expire()` runs its callback and consumes the end action synchronously. The
/// end action may be installed after expiration; this covers APIs whose
/// expiration callback can race the call that returns their identifier.
@MainActor
public final class ApplicationLifecycleLease {
    private let expiration: @MainActor @Sendable () -> Void
    private var endAction: (@MainActor @Sendable () -> Void)?
    public private(set) var isEnded = false
    public private(set) var didExpire = false

    public init(expiration: @escaping @MainActor @Sendable () -> Void) {
        self.expiration = expiration
    }

    public func installEndAction(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        if isEnded {
            action()
        } else {
            endAction = action
        }
    }

    public func expire() {
        guard !isEnded else { return }
        isEnded = true
        didExpire = true
        let action = endAction
        endAction = nil
        expiration()
        action?()
    }

    public func end() {
        guard !isEnded else { return }
        isEnded = true
        let action = endAction
        endAction = nil
        action?()
    }
}

/// Aggregates all SwiftUI scenes and launches each process-level lifecycle
/// transition independently.
///
/// Cancelling an older task never becomes a dependency of the next transition:
/// cancellation-insensitive network cleanup may keep draining, while foreground
/// admission resumes immediately under a newer revision.
@MainActor
public final class ApplicationSceneLifecycle {
    public typealias Operation =
        @MainActor @Sendable (ApplicationActivityTransition) async -> Void
    public typealias SuspensionLeaseFactory =
        @MainActor @Sendable (
            _ expiration: @escaping @MainActor @Sendable () -> Void
        ) -> ApplicationLifecycleLease?

    private let operation: Operation
    private let expirationOperation: Operation
    private let makeSuspensionLease: SuspensionLeaseFactory
    private var knownSceneIDs = Set<UUID>()
    private var activeSceneIDs = Set<UUID>()
    private var hasObservedScene = false
    private var revision: UInt64 = 0
    private var currentTransition: ApplicationActivityTransition
    private var currentTask: (id: UUID, task: Task<Void, Never>)?
    private var currentLease:
        (revision: UInt64, lease: ApplicationLifecycleLease)?

    public init(
        initiallyActive: Bool = true,
        makeSuspensionLease: @escaping SuspensionLeaseFactory = { _ in nil },
        operation: @escaping Operation,
        expirationOperation: Operation? = nil
    ) {
        currentTransition = ApplicationActivityTransition(
            isActive: initiallyActive,
            revision: 0
        )
        self.makeSuspensionLease = makeSuspensionLease
        self.operation = operation
        self.expirationOperation = expirationOperation ?? operation
    }

    public var isActive: Bool { currentTransition.isActive }
    public var currentRevision: UInt64 { currentTransition.revision }

    /// Reconciles one authoritative connected-scene snapshot without transient
    /// inactive states when activity moves between windows in the same update.
    @discardableResult
    public func replaceScenes(_ scenes: [UUID: Bool]) -> ApplicationActivityTransition? {
        knownSceneIDs = Set(scenes.keys)
        activeSceneIDs = Set(scenes.compactMap { $0.value ? $0.key : nil })
        return submitIfNeeded(isActive: !activeSceneIDs.isEmpty)
    }

    @discardableResult
    public func setScene(_ sceneID: UUID, isActive: Bool)
        -> ApplicationActivityTransition?
    {
        knownSceneIDs.insert(sceneID)
        if isActive {
            activeSceneIDs.insert(sceneID)
        } else {
            activeSceneIDs.remove(sceneID)
        }
        return submitIfNeeded(isActive: !activeSceneIDs.isEmpty)
    }

    @discardableResult
    public func removeScene(_ sceneID: UUID)
        -> ApplicationActivityTransition?
    {
        guard knownSceneIDs.remove(sceneID) != nil else { return nil }
        activeSceneIDs.remove(sceneID)
        return submitIfNeeded(isActive: !activeSceneIDs.isEmpty)
    }

    public func isCurrent(_ transition: ApplicationActivityTransition) -> Bool {
        transition == currentTransition
    }

    private func submitIfNeeded(isActive: Bool)
        -> ApplicationActivityTransition?
    {
        guard !hasObservedScene || currentTransition.isActive != isActive else {
            return nil
        }
        hasObservedScene = true
        revision &+= 1
        let transition = ApplicationActivityTransition(
            isActive: isActive,
            revision: revision
        )
        currentTransition = transition

        currentTask?.task.cancel()
        currentTask = nil
        currentLease?.lease.end()
        currentLease = nil

        let lease: ApplicationLifecycleLease?
        if isActive {
            lease = nil
        } else {
            lease = makeSuspensionLease { [weak self] in
                self?.suspensionLeaseExpired(for: transition)
            }
            if let lease {
                currentLease = (transition.revision, lease)
            }
        }

        let taskID = UUID()
        let operation = self.operation
        let task = Task { @MainActor [weak self, lease] in
            guard self?.isCurrent(transition) == true,
                  !Task.isCancelled else {
                lease?.end()
                return
            }
            await operation(transition)
            lease?.end()
            self?.transitionFinished(id: taskID, revision: transition.revision)
        }
        currentTask = (taskID, task)
        return transition
    }

    private func suspensionLeaseExpired(
        for transition: ApplicationActivityTransition
    ) {
        guard isCurrent(transition), !transition.isActive else { return }
        currentTask?.task.cancel()
        currentTask = nil
        currentLease = nil

        // Reissue the local-safety path independently. It must never wait for the
        // cancelled transition, which may still be stuck in transport teardown.
        let expirationOperation = self.expirationOperation
        Task { @MainActor [weak self] in
            guard self?.isCurrent(transition) == true else { return }
            await expirationOperation(transition)
        }
    }

    private func transitionFinished(id: UUID, revision: UInt64) {
        if currentTask?.id == id {
            currentTask = nil
        }
        if currentLease?.revision == revision {
            currentLease = nil
        }
    }
}
