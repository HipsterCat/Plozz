#if DEBUG
import FeatureLiveTVCore
import XCTest
@testable import FeatureLiveTV

final class LiveTVMultiviewGeometryTests: XCTestCase {
    func testSideBySideAndPortraitFramesAreDisjointAndContained() {
        let first = UUID()
        let second = UUID()
        for size in [CGSize(width: 1920, height: 1080), CGSize(width: 390, height: 844),
                     CGSize(width: 768, height: 1024)] {
            let bounds = CGRect(origin: .zero, size: size)
            let a = LiveTVMultiviewGeometry.frame(
                for: first, panes: [first, second], primary: first, layout: .sideBySide,
                corner: .bottomTrailing, insetSize: .medium, expanded: nil, size: size
            )
            let b = LiveTVMultiviewGeometry.frame(
                for: second, panes: [first, second], primary: first, layout: .sideBySide,
                corner: .bottomTrailing, insetSize: .medium, expanded: nil, size: size
            )
            XCTAssertTrue(bounds.contains(a))
            XCTAssertTrue(bounds.contains(b))
            XCTAssertFalse(a.intersects(b))
            XCTAssertEqual(a.width / a.height, 16 / 9, accuracy: 0.001)
        }
    }

    func testEveryCornerAndInsetSizeStaysInsideMainPicture() {
        let first = UUID()
        let second = UUID()
        let size = CGSize(width: 1920, height: 1080)
        for corner in LiveTVMultiviewCorner.allCases {
            for inset in LiveTVMultiviewInsetSize.allCases {
                let main = LiveTVMultiviewGeometry.frame(
                    for: first, panes: [first, second], primary: first, layout: .corner,
                    corner: corner, insetSize: inset, expanded: nil, size: size
                )
                let overlay = LiveTVMultiviewGeometry.frame(
                    for: second, panes: [first, second], primary: first, layout: .corner,
                    corner: corner, insetSize: inset, expanded: nil, size: size
                )
                XCTAssertTrue(main.contains(overlay))
                XCTAssertLessThan(overlay.width, main.width)
            }
        }
    }
}
#endif
