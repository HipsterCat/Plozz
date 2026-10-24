@testable import PlozzCoreUI
import XCTest

final class HeroDescriptionFactsLayoutTests: XCTestCase {
    func testDescriptionGrowsWithFactsAndShrinksAgainWhenTheyChange() {
        let layout = HeroDescriptionFactsLayout()
        for width: CGFloat in [0, 400, 800, 960, 1150, 1500, 400] {
            XCTAssertEqual(
                layout.columnWidth(factsWidth: width, availableWidth: 1600),
                min(1200, max(800, width))
            )
        }
    }

    func testAvailableColumnBoundsBothDescriptionAndFacts() {
        let layout = HeroDescriptionFactsLayout()
        XCTAssertEqual(layout.columnWidth(factsWidth: 1000, availableWidth: 900), 900)
        XCTAssertEqual(layout.columnWidth(factsWidth: 1000, availableWidth: 600), 600)
        XCTAssertEqual(layout.columnWidth(factsWidth: 1000, availableWidth: nil), 1000)
    }
}
