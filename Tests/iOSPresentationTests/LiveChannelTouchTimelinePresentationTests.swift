#if os(iOS)
import CoreModels
import CoreUI
@testable import FeaturePlayback
import SwiftUI
import UIKit
import XCTest

@MainActor
final class LiveChannelTouchTimelinePresentationTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 36_000)

    func testReducedEffectsLiveProgressNeverInvertsInLightAppearance() throws {
        for (height, focused, scrubbing) in [(CGFloat(8), false, false), (20, true, false), (20, false, true)] {
            let track = LiveChannelTouchTrack(
                layout: timeline(progress: 0.5), width: 240, height: height, focused: focused, scrubbing: scrubbing
            )
            let light = try pixels(track, width: 240, scheme: .light)
            let dark = try pixels(track, width: 240, scheme: .dark)
            XCTAssertEqual(light.bytes, dark.bytes, "The video timeline must never become black progress on a pale track.")
            XCTAssertGreaterThan(Int(light.color(30, 22)[0]) - Int(light.color(210, 22)[0]), 20,
                                 "Played progress must remain lighter than the remaining track.")
        }
    }

    func testLiveFillOnlyAtZeroMiddleAndLiveEdgeInRestFocusedAndDraggingStates() throws {
        for width in [CGFloat(240), 960] {
            for progress in [0.0, 0.5, 1.0] {
                let layout = timeline(progress: progress)
                XCTAssertEqual(layout.playing, progress, accuracy: 0.000001)
                for (height, focused, scrubbing) in [(CGFloat(8), false, false), (20, true, false), (20, false, true)] {
                    let actual = try pixels(
                        LiveChannelTouchTrack(layout: layout, width: width, height: height, focused: focused, scrubbing: scrubbing),
                        width: width
                    )
                    let expected = try pixels(
                        reference(layout, width: width, height: height, opacity: scrubbing ? 0.9 : focused ? 0.62 : 0.32),
                        width: width
                    )
                    XCTAssertEqual(actual.bytes, expected.bytes,
                                   "Live progress must consist only of its masked fills, with no mobile playhead.")
                }
            }
        }
    }

    func testMobileProgrammeCutsSuppressTinyNeighborsAndReturnWhenWide() throws {
        for width in [CGFloat(240), 960] {
            let layout = timeline(progress: 0.5)
            let unbroken = LiveChannelTimelineLayout(
                now: origin.addingTimeInterval(100), program: program(0, 100),
                seekWindowSeconds: 100, behindLiveSeconds: 50
            )
            XCTAssertEqual(layout.start, unbroken.start)
            XCTAssertEqual(layout.end, unbroken.end)
            XCTAssertEqual(layout.playing, unbroken.playing)
            XCTAssertEqual(layout.seekableStart, unbroken.seekableStart)
            for height in [CGFloat(8), 20] {
                let actual = try pixels(
                    LiveChannelTouchTrack(layout: layout, width: width, height: height, focused: false, scrubbing: height == 20),
                    width: width
                )
                let plain = try pixels(
                    LiveChannelTouchTrack(layout: unbroken, width: width, height: height, focused: false, scrubbing: height == 20),
                    width: width
                )
                let retained = width == 240 ? [0.4, 0.75] : [0.25, 0.28125, 0.4, 0.55, 0.58125, 0.75]
                for boundary in retained {
                    let x = Int(width * boundary)
                    for y in (22 - Int(height / 2))..<(22 + Int(height / 2)) {
                        XCTAssertEqual(actual.color(x, y), [0, 255, 255],
                                       "A retained programme cut must stay at its exact time coordinate.")
                    }
                }
                if width == 240 {
                    for boundary in [0.25, 0.28125, 0.55, 0.58125] {
                        let x = Int(width * boundary)
                        XCTAssertEqual(actual.color(x, 22), plain.color(x, 22),
                                       "Tiny programmes and their neighbors must not strand isolated slivers.")
                    }
                }
                let attachment = XCTAttachment(image: UIImage(cgImage: actual.image))
                attachment.name = "Live fill-only \(Int(width))pt - \(Int(height))pt track"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testUnavailableRewindShowsOnlyAiredFillEvenWhenThePictureIsPausedBehindLive() throws {
        for height in [CGFloat(8), 20] {
            var baseline: [UInt8]?
            for behind in [0.0, 20, 50] {
                let layout = LiveChannelTimelineLayout(
                    now: origin.addingTimeInterval(50), program: program(0, 100),
                    seekWindowSeconds: nil, behindLiveSeconds: behind
                )
                XCTAssertNil(layout.seekableStart)
                let actual = try pixels(
                    LiveChannelTouchTrack(layout: layout, width: 240, height: height, focused: false, scrubbing: height == 20),
                    width: 240
                )
                XCTAssertEqual(actual.bytes, try pixels(reference(layout, width: 240, height: height, opacity: 0.9), width: 240).bytes)
                if let baseline {
                    XCTAssertEqual(actual.bytes, baseline, "No bright seekable fill or vertical head may imply unavailable rewind.")
                } else {
                    baseline = actual.bytes
                }
            }
        }
    }

    func testUnreachableHistoryRemainsUnfilledBeforeTheRewindWindow() throws {
        let layout = timeline(progress: 0.5, window: 90)
        XCTAssertEqual(try XCTUnwrap(layout.seekableStart), 0.1, accuracy: 0.000001)
        let actual = try pixels(
            LiveChannelTouchTrack(layout: layout, width: 240, height: 8, focused: false, scrubbing: false), width: 240
        )
        let surface = try pixels(PlayerScrubTrackSurface(height: 8), width: 240)
        XCTAssertEqual(actual.color(12, 22), surface.color(12, 22))
        XCTAssertNotEqual(actual.color(36, 22), surface.color(36, 22))
    }

    private func timeline(progress: Double, window: TimeInterval = 100) -> LiveChannelTimelineLayout {
        LiveChannelTimelineLayout(
            now: origin.addingTimeInterval(100), program: program(75, 100),
            earlierPrograms: [program(0, 25), program(25, 28.125), program(28.125, 40),
                              program(40, 55), program(55, 58.125), program(58.125, 75)],
            seekWindowSeconds: window, behindLiveSeconds: (1 - progress) * 100
        )
    }

    private func program(_ start: TimeInterval, _ end: TimeInterval) -> LiveChannelProgramInfo {
        .init(title: "Programme", start: origin.addingTimeInterval(start), end: origin.addingTimeInterval(end))
    }

    private func reference(_ layout: LiveChannelTimelineLayout, width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        let start = width * CGFloat(layout.seekableStart ?? 0)
        return ZStack(alignment: .leading) {
            PlayerScrubTrackSurface(height: height)
            Rectangle().fill(Color.primary.opacity(layout.seekableStart == nil ? 0.14 : 0.24))
                .frame(width: max(0, width * CGFloat(layout.aired) - start), height: height)
                .offset(x: start)
            if layout.seekableStart != nil {
                Rectangle().fill(Color.primary.opacity(opacity))
                    .frame(width: max(0, width * CGFloat(layout.playing) - start), height: height)
                    .offset(x: start)
            }
        }
        .mask {
            PlayerSkipMarkerTrack(
                segments: layout.maskRanges.map { .init(kind: .intro, start: $0.lowerBound * 100, end: $0.upperBound * 100) },
                duration: 100, height: height, minimumSectionWidth: 20
            )
        }
    }

    private func pixels(_ view: some View, width: CGFloat, scheme: ColorScheme = .dark) throws -> Pixels {
        let renderer = ImageRenderer(content: view
            .frame(width: width, height: 44)
            .environment(\.plozzReducePanelGlass, true)
            .environment(\.colorScheme, scheme)
            .background(Color(red: 0, green: 1, blue: 1))
        )
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Pixels(image: image, bytes: bytes)
    }

    private struct Pixels {
        let image: CGImage
        let bytes: [UInt8]
        func color(_ x: Int, _ y: Int) -> [UInt8] {
            let index = (y * image.width + x) * 4
            return Array(bytes[index..<(index + 3)])
        }
    }
}
#endif
