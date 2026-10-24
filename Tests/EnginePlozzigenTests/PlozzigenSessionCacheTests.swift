import AetherEngine
import CoreModels
import XCTest
@testable import EnginePlozzigen

final class PlozzigenSessionCacheTests: XCTestCase {
    func testOnlyActiveCachesPublishIncludingValidZeroUsageAndPlaybackFloor() {
        XCTAssertNil(PlozzigenVideoEngine.sessionCacheTelemetry(.inactive))
        XCTAssertNil(PlozzigenVideoEngine.sessionCacheTelemetry(.nativeRemoteHLS(requestedBudgetBytes: Int.max)))
        for resident in [0, 3_000] {
            XCTAssertEqual(
                PlozzigenVideoEngine.sessionCacheTelemetry(status(resident: resident)),
                EngineSessionCache(residentBytes: Int64(resident), effectiveBudgetBytes: 4_000)
            )
        }
    }

    func testCompletedAndFailedCleanupNeverLookLikeAnActiveCache() {
        for reason: SessionCacheCleanupReason in [.sessionStopped, .sourceChanged, .loadFailed] {
            for result: SessionCacheCleanupResult in [.succeeded, .failed] {
                XCTAssertNil(PlozzigenVideoEngine.sessionCacheTelemetry(
                    status(cleanup: reason, result: result)
                ))
            }
        }
    }

    private func status(
        resident: Int = 0,
        cleanup: SessionCacheCleanupReason? = nil,
        result: SessionCacheCleanupResult = .notRun
    ) -> SessionCacheStatus {
        .init(
            route: .loopbackFMP4, capability: .active, requestedBudgetBytes: 2_000,
            volumeSafetyLimitBytes: 10_000, baseEffectiveBudgetBytes: 2_000,
            playbackSafeFloorBytes: 4_000, effectiveBudgetBytes: 4_000,
            currentResidentBytes: resident, currentForwardBytes: resident,
            forwardWindowSegments: 15, backwardWindowSegments: 5, producerParked: false,
            evictionCount: 0, hardWindowFloorExceeded: true, cleanupReason: cleanup,
            cleanupResult: result, lastFailure: result == .failed ? .cleanupFailed : nil
        )
    }
}
