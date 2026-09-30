import XCTest
@testable import FeatureHome

@MainActor
final class DetailStackDepthTests: XCTestCase {
    func testRepeatedAppearanceCannotCoverTheVisibleMovie() {
        let stack = DetailStackDepth()
        let page = UUID()
        for _ in 0..<5 { stack.pageAppeared(page) }
        XCTAssertEqual(stack.depth, 1)
        XCTAssertEqual(stack.pagesCovering(page), 0)
        stack.pageDismissed(page)
        XCTAssertEqual(stack.depth, 0)
    }

    func testLateDismissalCannotRemoveANewerMovie() {
        let stack = DetailStackDepth()
        let first = UUID(), second = UUID(), third = UUID()
        stack.pageAppeared(first)
        stack.pageDismissed(first)
        stack.pageAppeared(second)
        stack.pageDismissed(first)
        stack.pageAppeared(third)
        stack.pageDismissed(second)
        XCTAssertEqual(stack.depth, 1)
        XCTAssertEqual(stack.pagesCovering(third), 0)
        stack.pageDismissed(third)
        XCTAssertEqual(stack.depth, 0)
    }

    func testCoveredParentReappearanceDoesNotChangeTheTopPage() {
        let stack = DetailStackDepth()
        let parent = UUID(), child = UUID(), grandchild = UUID()
        stack.pageAppeared(parent)
        stack.pageAppeared(child)
        stack.pageAppeared(grandchild)
        stack.pageAppeared(parent)
        stack.pageAppeared(child)
        XCTAssertEqual(stack.depth, 3)
        XCTAssertEqual(stack.pagesCovering(parent), 2)
        XCTAssertEqual(stack.pagesCovering(child), 1)
        XCTAssertEqual(stack.pagesCovering(grandchild), 0)
        stack.pageDismissed(grandchild)
        XCTAssertEqual(stack.pagesCovering(parent), 1)
        XCTAssertEqual(stack.pagesCovering(child), 0)
    }

    func testReturningPageMayRegisterBeforeDepartingChildDisappears() {
        let stack = DetailStackDepth()
        let parent = UUID(), child = UUID()
        stack.pageAppeared(parent)
        stack.pageDismissed(parent)
        stack.pageAppeared(child)
        stack.pageAppeared(parent)
        stack.pageDismissed(child)
        XCTAssertEqual(stack.depth, 1)
        XCTAssertEqual(stack.pagesCovering(parent), 0)
    }
}
