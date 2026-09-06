#if canImport(UIKit)
import CoreModels
import CoreUI
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SeasonRequestControlsTests: XCTestCase {
    func testSectionRendersLoadingFailureEmptyAndMixedSeasonStates() throws {
        let mixed = MediaRequestAvailability(
            status: .partiallyAvailable,
            seasons: [
                .init(number: 1, title: "Season 1", status: .available),
                .init(number: 2, title: "Season 2", status: .pending),
                .init(number: 3, title: "Season 3", status: .processing),
                .init(number: 4, title: "Season 4", status: .unknown),
                .init(number: 5, title: "Season 5", status: .unknown)
            ]
        )
        let cases: [(String, MediaRequestAvailability?, Bool, Bool)] = [
            ("loading", nil, false, false),
            ("retry", nil, false, true),
            ("empty", .init(status: .unknown, seasons: []), false, false),
            ("mixed", mixed, false, false),
            ("submitting", mixed, true, false),
            ("stale", mixed, false, true)
        ]
        for (name, availability, submitting, failed) in cases {
            for width in [CGFloat(320), 640] {
                let content = VStack(alignment: .leading, spacing: 12) {
                    SeasonRequestControls(
                        availability: availability,
                        isSubmitting: submitting,
                        refreshFailed: failed,
                        actingName: "Viewer",
                        onRefresh: {},
                        onRequest: { _ in }
                    )
                }
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .frame(width: width, alignment: .leading)
                .padding(16)
                .background(.black)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertGreaterThan(image.size.height, 0)
                XCTAssertEqual(image.size.width, width + 32, accuracy: 0.5)
                let attachment = XCTAttachment(image: image)
                attachment.name = "season-requests-\(name)-\(Int(width))pt"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
#endif
