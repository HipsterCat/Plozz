import Foundation

public final class TrackerProfileGeneration: @unchecked Sendable {
    public init() {}

    private let lock = NSLock()
    private var storage: UInt64 = 0

    public func advance(
        performing update: () -> Void = {}
    ) -> UInt64 {
        lock.lock()
        storage &+= 1
        update()
        let value = storage
        lock.unlock()
        return value
    }

    public func performIfCurrent(
        _ generation: UInt64,
        operation: () -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == storage else { return false }
        operation()
        return true
    }

    public var current: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
