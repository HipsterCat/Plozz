import XCTest
@testable import CoreUI

final class ArtworkMemoryBudgetTests: XCTestCase {
    func testSmallDevicesKeepTheOriginalLimits() {
        let budget = ArtworkMemoryBudget(physicalMemory: 2 << 30)
        XCTAssertEqual(budget.decodedBytes, 96 << 20)
        XCTAssertEqual(budget.compositeBytes, 24 << 20)
        XCTAssertEqual(budget.indicatorBytes, 24 << 20)
        XCTAssertEqual(budget.compositeCount, 64)
    }

    func testAppleTV4KHoldsAReturningRetinaBrowseTraversal() {
        // Seven six-column rows: a 6 Down + 6 Up traversal plus the visible grid,
        // at 2x with 960px decoded sources and 260x390pt composites.
        let posters = 42
        for memory: UInt64 in [3 << 30, 2_900 << 20, 4 << 30] {
            let budget = ArtworkMemoryBudget(physicalMemory: memory)
            XCTAssertGreaterThanOrEqual(budget.decodedBytes, posters * 640 * 960 * 4)
            XCTAssertGreaterThanOrEqual(budget.compositeBytes, posters * 520 * 780 * 4)
            XCTAssertGreaterThanOrEqual(budget.indicatorBytes, posters * 520 * 780 * 4)
            XCTAssertGreaterThanOrEqual(budget.compositeCount, posters)
        }
    }
}
