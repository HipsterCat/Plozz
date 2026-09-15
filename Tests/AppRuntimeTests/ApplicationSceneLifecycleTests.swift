import Foundation
import XCTest
@testable import AppRuntime

final class ApplicationSceneLifecycleTests: XCTestCase {
    private actor Recorder {
        private(set) var transitions: [ApplicationActivityTransition] = []

        func append(_ transition: ApplicationActivityTransition) {
            transitions.append(transition)
        }

        func contains(active: Bool) -> Bool {
            transitions.contains { $0.isActive == active }
        }
    }

    private actor CancellationInsensitiveGate {
        private var started = false
        private var continuation: CheckedContinuation<Void, Never>?
        private var startWaiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            started = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation = $0 }
        }

        func waitUntilStarted() async {
            guard !started else { return }
            await withCheckedContinuation { startWaiters.append($0) }
        }

        func open() {
            continuation?.resume()
            continuation = nil
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ predicate: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await predicate() { return true }
            try? await clock.sleep(for: .milliseconds(5))
        }
        return await predicate()
    }

    @MainActor
    func testAuthoritativeSceneReplacementDoesNotSuspendDuringWindowHandoff() async {
        let recorder = Recorder()
        let lifecycle = ApplicationSceneLifecycle(operation: { await recorder.append($0) })
        let first = UUID()
        let second = UUID()

        XCTAssertEqual(lifecycle.replaceScenes([first: true])?.isActive, true)
        let initialRecorded = await waitUntil { await recorder.transitions.count == 1 }
        XCTAssertTrue(initialRecorded)
        XCTAssertNil(lifecycle.replaceScenes([first: true]))
        XCTAssertNil(lifecycle.replaceScenes([first: false, second: true]))
        XCTAssertNil(lifecycle.replaceScenes([second: true]))
        XCTAssertEqual(lifecycle.replaceScenes([:])?.isActive, false)

        let disconnectedRecorded = await waitUntil { await recorder.transitions.count == 2 }
        XCTAssertTrue(disconnectedRecorded)
        let transitions = await recorder.transitions
        XCTAssertEqual(transitions.map(\.isActive), [true, false])
    }

    @MainActor
    func testSceneAggregationKeepsProcessActiveWhileAnySceneIsActive() async {
        let recorder = Recorder()
        let lifecycle = ApplicationSceneLifecycle(
            operation: { transition in
                await recorder.append(transition)
            }
        )
        let first = UUID()
        let second = UUID()

        lifecycle.setScene(first, isActive: true)
        let firstRecorded = await waitUntil {
            await recorder.transitions.count == 1
        }
        XCTAssertTrue(firstRecorded)
        lifecycle.setScene(second, isActive: false)
        lifecycle.setScene(first, isActive: false)
        let inactiveRecorded = await waitUntil {
            await recorder.transitions.count == 2
        }
        XCTAssertTrue(inactiveRecorded)
        lifecycle.setScene(second, isActive: true)

        let recorded = await waitUntil {
            await recorder.transitions.count == 3
        }
        XCTAssertTrue(recorded)
        lifecycle.removeScene(second)
        let removalRecorded = await waitUntil {
            await recorder.transitions.count == 4
        }
        XCTAssertTrue(removalRecorded)
        let transitions = await recorder.transitions
        XCTAssertEqual(transitions.map(\.isActive), [true, false, true, false])
        XCTAssertEqual(transitions.map(\.revision), [1, 2, 3, 4])
    }

    @MainActor
    func testForegroundDoesNotWaitForCancellationInsensitiveSuspension() async {
        let recorder = Recorder()
        let gate = CancellationInsensitiveGate()
        let lifecycle = ApplicationSceneLifecycle(
            operation: { transition in
                if transition.isActive {
                    await recorder.append(transition)
                } else {
                    await gate.wait()
                    await recorder.append(transition)
                }
            }
        )
        let sceneID = UUID()

        lifecycle.setScene(sceneID, isActive: false)
        await gate.waitUntilStarted()
        lifecycle.setScene(sceneID, isActive: true)

        let foregroundRan = await waitUntil {
            await recorder.contains(active: true)
        }
        XCTAssertTrue(foregroundRan)
        await gate.open()
    }

    @MainActor
    func testCancelledTransitionCannotStartAfterNewerStateWasSubmitted() async {
        let recorder = Recorder()
        let lifecycle = ApplicationSceneLifecycle(
            operation: { transition in
                await recorder.append(transition)
            }
        )
        let sceneID = UUID()

        lifecycle.setScene(sceneID, isActive: false)
        lifecycle.setScene(sceneID, isActive: true)

        let foregroundRan = await waitUntil {
            await recorder.contains(active: true)
        }
        XCTAssertTrue(foregroundRan)
        let transitions = await recorder.transitions
        XCTAssertEqual(transitions, [
            ApplicationActivityTransition(isActive: true, revision: 2)
        ])
    }

    @MainActor
    func testStaleLeaseExpirationCannotOverrideForeground() async {
        let recorder = Recorder()
        var leases: [ApplicationLifecycleLease] = []
        let lifecycle = ApplicationSceneLifecycle(
            makeSuspensionLease: { expiration in
                let lease = ApplicationLifecycleLease(
                    expiration: expiration
                )
                lease.installEndAction {}
                leases.append(lease)
                return lease
            },
            operation: { transition in
                await recorder.append(transition)
            },
            expirationOperation: { transition in
                await recorder.append(transition)
            }
        )
        let sceneID = UUID()

        lifecycle.setScene(sceneID, isActive: false)
        let lease = try! XCTUnwrap(leases.first)
        let inactiveRan = await waitUntil {
            await recorder.contains(active: false)
        }
        XCTAssertTrue(inactiveRan)
        lifecycle.setScene(sceneID, isActive: true)
        lease.expire()

        let foregroundRan = await waitUntil {
            await recorder.contains(active: true)
        }
        XCTAssertTrue(foregroundRan)
        try? await Task.sleep(for: .milliseconds(20))
        let transitions = await recorder.transitions
        XCTAssertEqual(
            transitions.filter { !$0.isActive }.count,
            1,
            "an ended stale lease must not reissue inactive work"
        )
    }

    @MainActor
    func testCurrentLeaseExpirationReissuesSafetyWithoutWaitingForStalledWork() async {
        let expirationRecorder = Recorder()
        let gate = CancellationInsensitiveGate()
        var lease: ApplicationLifecycleLease?
        let lifecycle = ApplicationSceneLifecycle(
            makeSuspensionLease: { expiration in
                let created = ApplicationLifecycleLease(expiration: expiration)
                created.installEndAction {}
                lease = created
                return created
            },
            operation: { transition in
                if !transition.isActive {
                    await gate.wait()
                }
            },
            expirationOperation: { transition in
                await expirationRecorder.append(transition)
            }
        )

        lifecycle.setScene(UUID(), isActive: false)
        await gate.waitUntilStarted()
        lease?.expire()

        let safetyReissued = await waitUntil {
            await expirationRecorder.contains(active: false)
        }
        XCTAssertTrue(safetyReissued)
        XCTAssertTrue(lease?.isEnded == true)
        XCTAssertTrue(lease?.didExpire == true)
        await gate.open()
    }

    @MainActor
    func testQueuedExpirationSafetyIsDroppedAfterForegroundWins() async {
        let transitionRecorder = Recorder()
        let expirationRecorder = Recorder()
        let gate = CancellationInsensitiveGate()
        var lease: ApplicationLifecycleLease?
        let lifecycle = ApplicationSceneLifecycle(
            makeSuspensionLease: { expiration in
                let created = ApplicationLifecycleLease(expiration: expiration)
                created.installEndAction {}
                lease = created
                return created
            },
            operation: { transition in
                if transition.isActive {
                    await transitionRecorder.append(transition)
                } else {
                    await gate.wait()
                }
            },
            expirationOperation: { transition in
                await expirationRecorder.append(transition)
            }
        )
        let sceneID = UUID()

        lifecycle.setScene(sceneID, isActive: false)
        await gate.waitUntilStarted()
        lease?.expire()
        lifecycle.setScene(sceneID, isActive: true)

        let foregroundRan = await waitUntil {
            await transitionRecorder.contains(active: true)
        }
        XCTAssertTrue(foregroundRan)
        try? await Task.sleep(for: .milliseconds(20))
        let expirationTransitions = await expirationRecorder.transitions
        XCTAssertTrue(expirationTransitions.isEmpty)
        await gate.open()
    }

    @MainActor
    func testLeaseExpirationAndInvalidIdentifierEndExactlyOnce() {
        var expirationCount = 0
        var endCount = 0
        let expiring = ApplicationLifecycleLease {
            expirationCount += 1
        }

        expiring.expire()
        expiring.installEndAction { endCount += 1 }
        expiring.expire()
        expiring.end()

        XCTAssertEqual(expirationCount, 1)
        XCTAssertEqual(endCount, 1)
        XCTAssertTrue(expiring.didExpire)

        var invalidEndCount = 0
        let invalid = ApplicationLifecycleLease {
            XCTFail("an invalid lease must not expire")
        }
        invalid.end()
        invalid.installEndAction { invalidEndCount += 1 }
        invalid.end()

        XCTAssertEqual(invalidEndCount, 1)
        XCTAssertFalse(invalid.didExpire)
    }

    @MainActor
    func testMissingBackgroundLeaseDoesNotSuppressSafetyTransition() async {
        let recorder = Recorder()
        let lifecycle = ApplicationSceneLifecycle(
            makeSuspensionLease: { _ in nil },
            operation: { transition in
                await recorder.append(transition)
            }
        )

        lifecycle.setScene(UUID(), isActive: false)

        let ran = await waitUntil {
            await recorder.contains(active: false)
        }
        XCTAssertTrue(ran)
    }
}
