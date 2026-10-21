import UIKit
import XCTest
@testable import FeatureHome

@MainActor
final class HomePerfSamplerLifecycleTests: XCTestCase {
    func testStartAndStopAreIdempotent() throws {
        let sampler = HomePerfSampler()
        sampler.start()
        defer { sampler.stop() }
        let link = try XCTUnwrap(sampler.displayLinkForTesting)
        sampler.start()
        XCTAssertTrue(sampler.displayLinkForTesting === link)
        XCTAssertEqual(sampler.lifecycleObserversForTesting.count, 2)
        sampler.stop()
        sampler.stop()
        XCTAssertNil(sampler.displayLinkForTesting)
        XCTAssertTrue(sampler.lifecycleObserversForTesting.isEmpty)
        sampler.start()
        XCTAssertNotNil(sampler.displayLinkForTesting)
        XCTAssertFalse(sampler.displayLinkForTesting === link)
    }

    func testDestroyingRunningSamplerReleasesRunLoopAndObserverResources() async throws {
        for _ in 0..<3 {
            var sampler: HomePerfSampler? = HomePerfSampler()
            sampler?.start()
            weak var weakSampler = sampler
            weak var link = sampler?.displayLinkForTesting
            weak var observer = sampler?.lifecycleObserversForTesting.first as AnyObject?
            XCTAssertNotNil(link)
            XCTAssertNotNil(observer)
            sampler = nil
            let deadline = ContinuousClock.now + .seconds(2)
            while (weakSampler != nil || link != nil || observer != nil), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertNil(weakSampler)
            XCTAssertNil(link, "The run loop must not retain a link after its sampler is destroyed.")
            XCTAssertNil(observer, "The notification center must release its registration.")
        }
    }
}
