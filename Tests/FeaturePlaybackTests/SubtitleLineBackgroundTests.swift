import CoreModels
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class SubtitleLineBackgroundTests: XCTestCase {
    private func height(_ text: String, family: SubtitleFontFamily = .system, background: Bool = true) -> CGFloat {
        let view = SubtitleLineView()
        view.configure(SubtitleLineView.Config(
            text: text, family: family, weight: .regular, fontSize: 42,
            isBold: false, isItalic: false, fill: .white, outline: nil, outlineWidth: 0,
            shadow: nil,
            background: background
                ? SubtitleBackgroundSpec(color: .black, cornerRadius: 6, horizontalPadding: 12, verticalPadding: 6)
                : nil,
            alignment: .left
        ))
        return view.measure(maxWidth: 2000).height
    }

    func testBackgroundHeightDoesNotChangeWhenTallOrDeepLettersArrive() {
        for family in [SubtitleFontFamily.system, .atkinson] {
            let plain = height("was so wide", family: family)
            XCTAssertEqual(height("was so wide open to begin", family: family), plain, "\(family)")
            XCTAssertEqual(height("hold by the minute, yes", family: family), plain, "\(family)")
            XCTAssertEqual(height("was so wide\nseason", family: family),
                           height("was so wide\nby the gypsy", family: family), "\(family)")
        }
    }

    func testTextWithoutABackgroundStillHugsItsInk() {
        XCTAssertLessThan(height("was so", background: false), height("hold gypsy", background: false))
    }
}
