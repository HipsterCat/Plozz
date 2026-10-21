#if os(iOS)
@testable import AppShelliOS
import CoreUI
import FeaturePlayback
import SwiftUI
import UIKit
import XCTest

@MainActor
final class PlayerTimelineClockPresentationTests: XCTestCase {
    func testElapsedModeDoesNotReserveUnusedHourColumns() throws {
        for duration in [TimeInterval(1_200), 3_599] {
            let model = PlayerControlsModel()
            model.duration = duration
            model.currentSeconds = 600
            let image = try render(model, width: 398, scrubbing: false, locale: "en_US")
            XCTAssertEqual(try trackRange(image).count, 302, accuracy: 1)
        }
    }

    func testTimestampFieldsStayFixedForTheVideoDuration() {
        let model = PlayerControlsModel()
        let timeline = PlozziOSPlayerTimeline(
            model: model, displayedSeconds: 0, isScrubbing: false,
            onScrubChanged: { _ in }, onScrubEditingChanged: { _ in }, onInteraction: {}
        )
        model.duration = 1_200
        for (seconds, expected) in [(0.0, "00:00"), (9, "00:09"), (60, "01:00"), (600, "10:00"), (1_200, "20:00")] {
            XCTAssertEqual(timeline.playbackTime(seconds), expected)
        }
        model.duration = 5_600
        for (seconds, expected) in [(0.0, "0:00:00"), (59, "0:00:59"), (600, "0:10:00"), (3_600, "1:00:00")] {
            XCTAssertEqual(timeline.playbackTime(seconds), expected)
        }
        model.duration = 43_200
        XCTAssertEqual(timeline.playbackTime(600), "00:10:00")
        XCTAssertEqual(timeline.playbackTime(36_000), "10:00:00")
        for invalid in [TimeInterval.nan, .infinity, -1, Double(Int.max)] {
            XCTAssertEqual(timeline.playbackTime(invalid), "--:--")
        }
    }

    func testScrubTargetCrossingTimeFormatsDoesNotChangeDragGeometry() throws {
        for clockEnabled in [false, true] {
            for locale in ["en_US", "en_GB", "de_DE", "ar"] {
                let model = PlayerControlsModel()
                model.duration = 43_200
                model.currentSeconds = 600
                model.timelineClock.isEnabled = clockEnabled
                let normal = try render(model, width: 398, scrubbing: false, locale: locale)
                for target in [TimeInterval(30), 3_600, 40_000] {
                    let scrub = try render(
                        model, width: 398, scrubbing: true, locale: locale, displayedSeconds: target
                    )
                    XCTAssertEqual(try trackRange(normal), try trackRange(scrub),
                                   "A longer seek label must not move the track under the finger.")
                }
            }
        }
    }

    func testClockLabelsDoNotMoveTheScrubberWhenScrubbingStartsOrEnds() throws {
        for width in [320, 393, 852, 1024] {
            for locale in ["en_US", "en_GB", "de_DE", "ar"] {
                let model = PlayerControlsModel()
                model.duration = 7_200
                model.currentSeconds = 600
                model.bufferedSeconds = 900
                let normal = try render(model, width: width, scrubbing: false, locale: locale)
                model.timelineClock.isEnabled = true
                let clock = try render(model, width: width, scrubbing: false, locale: locale)
                let scrub = try render(model, width: width, scrubbing: true, locale: locale)
                XCTAssertEqual(try trackRange(clock), try trackRange(scrub),
                               "Showing the seek target must not change drag geometry: \(width) \(locale)")
                XCTAssertGreaterThan(try trackRange(clock).count, 40,
                                     "Clock labels must leave a usable scrubber on narrow phones.")
                model.controlsVisible = false
                let reset = try render(model, width: width, scrubbing: false, locale: locale)
                XCTAssertEqual(try trackRange(normal), try trackRange(reset))
                if locale == "en_US" {
                    let attachment = XCTAttachment(image: UIImage(cgImage: clock))
                    attachment.name = "Player clock timeline \(width)pt"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    private func render(
        _ model: PlayerControlsModel, width: Int, scrubbing: Bool, locale: String,
        displayedSeconds: TimeInterval? = nil
    ) throws -> CGImage {
        let renderer = ImageRenderer(content:
            PlozziOSPlayerTimeline(
                model: model, displayedSeconds: displayedSeconds ?? (scrubbing ? 1_200 : 600), isScrubbing: scrubbing,
                onScrubChanged: { _ in XCTFail("Rendering must not seek.") },
                onScrubEditingChanged: { _ in XCTFail("Rendering must not change scrub state.") },
                onInteraction: { XCTFail("Rendering must not toggle clock mode.") }
            )
            .frame(width: CGFloat(width), height: 44)
            .environment(\.locale, Locale(identifier: locale))
            .environment(\.timeZone, .gmt)
            .environment(\.plozzReducePanelGlass, true)
            .background(Color(red: 0, green: 1, blue: 1))
        )
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    private func trackRange(_ image: CGImage) throws -> Range<Int> {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        func background(_ x: Int) -> Bool {
            let offset = (22 * image.width + x) * 4
            return pixels[offset] == 0 && pixels[offset + 1] == 255 && pixels[offset + 2] == 255
        }
        let center = image.width / 2
        XCTAssertFalse(background(center), "The center must remain inside the scrubber.")
        var lower = center
        var upper = center
        while lower > 0, !background(lower - 1) { lower -= 1 }
        while upper < image.width, !background(upper) { upper += 1 }
        return lower..<upper
    }
}
#endif
