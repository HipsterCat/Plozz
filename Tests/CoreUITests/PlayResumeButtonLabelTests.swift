#if canImport(UIKit)
import CoreUI
import SwiftUI
import UIKit
import XCTest

@MainActor
final class PlayResumeButtonLabelTests: XCTestCase {
    private func size(of view: some View) -> CGSize {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: 2_000, height: 200))
    }

    func testPlaceholderPlainAndResumeLabelsReserveTheSameSpace() {
        for fontSize in [CGFloat(17), 30] {
            for style in [
                PlayResumeButtonLabel.ResumeTrailingStyle.full,
                .seasonEpisodeOnly,
                .hidden
            ] {
                func label(pending: Bool, progress: Double?) -> some View {
                    PlayResumeButtonLabel(
                        title: "Play",
                        progress: progress,
                        remainingText: progress == nil ? nil : "35m",
                        seasonEpisodeText: pending ? nil : "S4, E1",
                        onLight: true,
                        spacing: fontSize == 17 ? 10 : 16,
                        capsuleWidth: fontSize == 17 ? 60 : 75,
                        resumeTrailingStyle: style,
                        isPlaceholder: pending,
                        reservesProgressSpace: true
                    )
                    .font(.system(size: fontSize))
                }
                let placeholder = size(of: label(pending: true, progress: nil))
                let plain = size(of: label(pending: false, progress: nil))
                let resume = size(of: label(pending: false, progress: 0.3))
                XCTAssertGreaterThan(placeholder.width, 0)
                XCTAssertGreaterThan(placeholder.height, 0)
                if style != .hidden {
                    XCTAssertEqual(placeholder.width, plain.width, accuracy: 0.5)
                }
                XCTAssertEqual(placeholder.width, resume.width, accuracy: 0.5)
                XCTAssertEqual(placeholder.height, plain.height, accuracy: 0.5)
                XCTAssertEqual(placeholder.height, resume.height, accuracy: 0.5)
            }
        }
    }

    func testExistingPlainButtonsKeepTheirCompactSizeByDefault() {
        let label = PlayResumeButtonLabel(
            title: "Play", progress: nil, remainingText: nil, onLight: true
        )
        let original = HStack(spacing: 16) {
            Image(systemName: "play.fill")
            Text("Play")
        }
        let actual = size(of: label.font(.system(size: 30)))
        let expected = size(of: original.font(.system(size: 30)))
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.5)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.5)
    }
}
#endif
