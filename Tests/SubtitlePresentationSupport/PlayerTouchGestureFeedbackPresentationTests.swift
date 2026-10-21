#if os(iOS)
import CoreUI
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlayerTouchGestureFeedbackPresentationTests: XCTestCase {
    private var capturedImages: [(image: UIImage, name: String)] = []
    private var idleIndicator: RenderedFrame?
    private var typographyReferences: [TypographyReference: RenderedFrame] = [:]

    func testFirstForwardChevronTravelsHoldsFadesAndRetriggersWhileCountRemains() async throws {
        try await assertFlight(direction: .forward)
    }

    func testFirstBackwardChevronTravelsHoldsFadesAndRetriggersWhileCountRemains() async throws {
        try await assertFlight(direction: .backward)
    }

    func testRapidForwardTapsStackIndependentFlightsWithoutQueuedReplay() async throws {
        try await assertRapidTaps(direction: .forward)
    }

    func testRapidBackwardTapsStackIndependentFlightsWithoutQueuedReplay() async throws {
        try await assertRapidTaps(direction: .backward)
    }

    func testReduceMotionRendersOneSteadyCompactChevronAcrossAdditionalTaps() async throws {
        var outerClearances: [CGFloat] = []
        for direction in [PlayerTouchSkipDirection.forward, .backward] {
            try await withFeedback(direction: direction, reduceMotion: true) { fixture, window in
                let interval: TimeInterval = direction == .forward ? 25 : -25
                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(120))
                let first = try self.captureGlyphs(window, direction: direction, reduceMotion: true, label: "Reduce Motion insertion")
                XCTAssertEqual(self.componentCount(first), 1)
                try await Task.sleep(for: .milliseconds(160))
                let later = try self.captureGlyphs(window, direction: direction, reduceMotion: true, label: "Reduce Motion still held")
                XCTAssertTrue(first.pixels == later.pixels, "Reduce Motion must remain exactly static")

                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(180))
                let repeated = try self.captureGlyphs(window, direction: direction, reduceMotion: true, label: "Reduce Motion additional tap")
                XCTAssertTrue(later.pixels == repeated.pixels, "Updating the total must not move the glyphs")
                XCTAssertEqual(fixture.state.skip?.seconds, interval * 2)
                XCTAssertEqual(fixture.state.skip?.direction, direction)
                XCTAssertEqual(fixture.state.skip?.target, 300 + interval * 2)
                try await Task.sleep(for: .milliseconds(160))
                let held = try self.captureGlyphs(window, direction: direction, reduceMotion: true, label: "Reduce Motion repeated hold")
                XCTAssertTrue(repeated.pixels == held.pixels, "Additional taps must not start an animation")
                outerClearances.append(try self.assertCompactIndicator(
                    held, indicator: self.captureIndicator(window, direction: direction, label: "Complete compact indicator"),
                    direction: direction, seconds: interval * 2
                ))
            }
        }
        XCTAssertEqual(outerClearances[0], outerClearances[1], accuracy: 1.5, "Reduced-motion edge spacing must mirror in both directions")
    }

    func testEnablingReduceMotionReplacesOverlappingFlightsWithOneSteadyChevron() async throws {
        for direction in [PlayerTouchSkipDirection.forward, .backward] {
            try await withFeedback(direction: direction) { fixture, window in
                let interval: TimeInterval = direction == .forward ? 25 : -25
                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(140))
                let lastPulseAt = ContinuousClock.now
                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(60))
                let moving = try self.captureGlyphs(
                    window, direction: direction, label: "Before Reduce Motion", since: lastPulseAt
                )
                fixture.reduceMotion = true
                // Collect every timed sample before assertions can interrupt the gesture clock.
                try await Task.sleep(until: lastPulseAt + .milliseconds(240), clock: .continuous)
                let stopped = try self.captureGlyphs(
                    window, direction: direction, reduceMotion: true, label: "Reduce Motion activated", since: lastPulseAt
                )
                try await Task.sleep(until: lastPulseAt + .milliseconds(1120), clock: .continuous)
                let later = try self.captureGlyphs(
                    window, direction: direction, reduceMotion: true, label: "Past both flight completions", since: lastPulseAt
                )
                let indicator = try self.captureIndicator(window, direction: direction, label: "Final reduced-motion indicator")
                let observedSeconds = fixture.state.skip?.seconds
                let observedAt = ContinuousClock.now
                self.assertVisible(moving)
                XCTAssertEqual(self.componentCount(stopped), 1)
                try self.assertCompactIndicator(later, indicator: indicator, direction: direction, seconds: interval * 2)
                XCTAssertTrue(stopped.pixels == later.pixels, "Disposed flights must not disturb the steady chevron")
                XCTAssertLessThan(observedAt, lastPulseAt + .milliseconds(1200), "The final sample must precede feedback expiry")
                XCTAssertEqual(observedSeconds, interval * 2, "The count must still be present at the final timed sample")
            }
        }
    }

    func testNativeSkipCountAndChevronKeepLightInkInBothAppearances() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native Liquid Glass requires iOS 26.") }
        for scheme in [ColorScheme.light, .dark] {
            for direction in [PlayerTouchSkipDirection.forward, .backward] {
                try await withFeedback(reduceMotion: true, reducePanelGlass: false, colorScheme: scheme) { fixture, window in
                    fixture.seek(by: direction == .forward ? 25 : -25)
                    try await Task.sleep(for: .milliseconds(150))
                    let frame = try self.captureIndicator(window, direction: direction, label: "Native skip \(scheme)")
                    let middle = frame.width / 2
                    for region in [
                        CGRect(x: 0, y: 20, width: middle, height: 32),
                        CGRect(x: middle, y: 20, width: frame.width - middle, height: 32)
                    ] {
                        let ink = self.cropped(frame, to: region)
                        XCTAssertGreaterThan(ink.pixels.filter { $0 > 230 }.count, 20,
                                             "Both the signed count and chevron need light ink in \(scheme).")
                    }
                }
            }
        }
    }

    func testSkipCapsulesContainMovingAndParkedChevronsWithNativeAndReducedGlass() async throws {
        for reducePanelGlass in [false, true] {
            if !reducePanelGlass {
                guard #available(iOS 26.0, *) else { continue }
            }
            var parkedClearances: [CGFloat] = []
            for direction in [PlayerTouchSkipDirection.forward, .backward] {
                try await withFeedback(reducePanelGlass: reducePanelGlass) { fixture, window in
                    let interval: TimeInterval = direction == .forward ? 25 : -25
                    let startedAt = ContinuousClock.now
                    fixture.seek(by: interval)
                    var frames: [Int: RenderedFrame] = [:]
                    for milliseconds in [60, 300, 720, 1120] {
                        try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                        frames[milliseconds] = try self.captureIndicator(
                            window, direction: direction,
                            label: "\(reducePanelGlass ? "Reduced" : "Native") glass, \(milliseconds) ms"
                        )
                    }
                    let idle = try XCTUnwrap(frames[1120])
                    let capsule = try self.assertCapsule(idle, reducePanelGlass: reducePanelGlass)
                    XCTAssertEqual(capsule.height, 46, accuracy: 3)
                    XCTAssertGreaterThan(capsule.width, 85, "The capsule must include the count, native icon width, travel, and outer insets")
                    XCTAssertLessThan(capsule.width, 105, "The chevron must not retain the oversized blank slot")
                    let inset = capsule.insetBy(dx: 2, dy: 2)
                    let interior = UIBezierPath(roundedRect: inset, cornerRadius: inset.height / 2)
                    let indicatorRect = self.indicatorRect(direction: direction)
                    let glyphRect = self.glyphRect(direction: direction)
                        .offsetBy(dx: -indicatorRect.minX, dy: -indicatorRect.minY)
                    let idleGlyphs = self.cropped(idle, to: glyphRect)
                    let reference = try self.typographyReference(kind: .chevron)
                    for milliseconds in [60, 300, 720] {
                        let glyphs = self.cropped(try XCTUnwrap(frames[milliseconds]), to: glyphRect)
                        let foreground = self.removingBackground(glyphs, idleGlyphs)
                        self.assertVisible(foreground)
                        let glyphBounds = try self.inkBounds(foreground, threshold: 32)
                        if milliseconds == 300 || milliseconds == 720 {
                            try self.assertTypographyMatches(
                                foreground, reference: reference, antialiasWeighted: true,
                                message: "Opened skip chevrons must match PlayerTabButtonStyle's proportional label icons"
                            )
                            let clearance = direction == .forward
                                ? capsule.maxX - (glyphRect.minX + glyphBounds.maxX)
                                : glyphRect.minX + glyphBounds.minX - capsule.minX
                            XCTAssertGreaterThanOrEqual(clearance, 16, "A parked chevron must retain at least 16 points of outer padding")
                            try self.assertNumberChevronGap(
                                glyphBounds.offsetBy(dx: glyphRect.minX, dy: glyphRect.minY),
                                indicator: idle, direction: direction, seconds: interval, reduceMotion: false
                            )
                            if milliseconds == 720 { parkedClearances.append(clearance) }
                        }
                        for index in foreground.pixels.indices where foreground.pixels[index] > 32 {
                            let point = CGPoint(
                                x: glyphRect.minX + CGFloat(index % foreground.width) + 0.5,
                                y: glyphRect.minY + CGFloat(index / foreground.width) + 0.5
                            )
                            XCTAssertTrue(interior.contains(point), "The entire flight must stay inside the capsule at \(milliseconds) ms")
                        }
                    }
                    XCTAssertEqual(fixture.state.skip?.seconds, interval, "The idle capsule must retain its count")
                    try self.assertVisibleCompactCount(window, direction: direction, seconds: interval)
                }
            }
            XCTAssertEqual(parkedClearances[0], parkedClearances[1], accuracy: 1.5, "Parked edge spacing must mirror in both directions")
        }
    }

    func testSpeedCapsuleShowsRateAndFastForwardThenDisappearsWithNativeAndReducedGlass() async throws {
        for reducePanelGlass in [false, true] {
            if !reducePanelGlass {
                guard #available(iOS 26.0, *) else { continue }
            }
            try await withFeedback(
                reducePanelGlass: reducePanelGlass, colorScheme: reducePanelGlass ? .dark : .light
            ) { fixture, window in
                fixture.state.showBoost(rate: 2)
                try await Task.sleep(for: .milliseconds(150))
                let rect = CGRect(x: 110, y: 8, width: 180, height: 64)
                let speed = try self.capture(window, rect: rect, label: "\(reducePanelGlass ? "Reduced" : "Native") glass speed pill")
                let capsule = try self.assertCapsule(speed, reducePanelGlass: reducePanelGlass)
                XCTAssertEqual(capsule.minY + rect.minY, 16, accuracy: 2, "The speed pill must respect its top inset")
                XCTAssertGreaterThanOrEqual(capsule.height, 34)
                XCTAssertLessThanOrEqual(capsule.height, 40)
                let backing = self.cropped(speed, to: CGRect(
                    x: capsule.midX - 8, y: capsule.minY + 5, width: 16, height: 2
                ))
                XCTAssertLessThanOrEqual(
                    self.inkEnergy(backing) / Double(max(backing.pixels.count, 1)), 118,
                    "White speed feedback must retain a dark capsule even when its parent uses Light appearance"
                )
                let label = self.cropped(speed, to: CGRect(
                    x: capsule.minX + 14, y: capsule.minY + 6,
                    width: capsule.width / 2 - 14, height: capsule.height - 12
                ))
                let icon = self.cropped(speed, to: CGRect(
                    x: capsule.midX, y: capsule.minY + 6,
                    width: capsule.width / 2 - 14, height: capsule.height - 12
                ))
                XCTAssertEqual(self.componentCount(label, threshold: 160), 2, "The rate must render both 2 and ×")
                try self.assertTypographyMatches(
                    label, reference: self.typographyReference(kind: .rate),
                    message: "The speed label must match PlayerTabButtonStyle's callout semibold text"
                )
                try self.assertTypographyMatches(
                    icon, reference: self.typographyReference(kind: .fastForward),
                    message: "The speed symbol must match PlayerTabButtonStyle's proportional label icons"
                )
                let iconBounds = try self.inkBounds(icon, threshold: 160)
                XCTAssertGreaterThanOrEqual(iconBounds.width, 18)
                XCTAssertGreaterThanOrEqual(iconBounds.height, 10)
                // At this size the native first triangle's tip touches the second base.
                // Verify two filled right-pointing tapers instead of raster connectivity.
                let rows = Int(iconBounds.minY)..<Int(iconBounds.maxY)
                let columns = (Int(iconBounds.minX)..<Int(iconBounds.maxX)).map { x in
                    rows.filter { icon.pixels[$0 * icon.width + x] > 160 }.count
                }
                let midpoint = columns.count / 2
                for triangle in [Array(columns.prefix(midpoint)), Array(columns.dropFirst(midpoint))] {
                    let edgeWidth = max(2, triangle.count / 4)
                    let base = Double(triangle.prefix(edgeWidth).reduce(0, +)) / Double(edgeWidth)
                    let tip = Double(triangle.suffix(edgeWidth).reduce(0, +)) / Double(edgeWidth)
                    XCTAssertGreaterThanOrEqual(
                        base, Double(iconBounds.height) * 0.75,
                        "Each fast-forward triangle must have a tall filled base on its left"
                    )
                    XCTAssertLessThanOrEqual(
                        tip, Double(iconBounds.height) * 0.35,
                        "Each fast-forward triangle must taper to its own right-pointing tip"
                    )
                }
                let filledPixels = icon.pixels.filter { $0 > 160 }.count
                XCTAssertGreaterThan(
                    Double(filledPixels) / Double(iconBounds.width * iconBounds.height), 0.4,
                    "The speed symbol must be filled fast-forward triangles, not open skip chevrons"
                )
                XCTAssertEqual(fixture.state.boostRate, 2)
                fixture.state.showBoost(rate: nil)
                try await Task.sleep(for: .milliseconds(80))
                let removed = try self.capture(window, rect: rect, label: "Speed pill removed")
                self.assertAbsent(removed, message: "Ending boost must remove both the rate and its capsule")
            }
        }
    }

    func testVerticalLevelMetersMaskIconContrastAtZeroPartialAndFullWithoutVisibleNumbers() async throws {
        for reducePanelGlass in [false, true] {
            for kind in [PlayerTouchLevel.brightness, .volume] {
                try await withFeedback(reducePanelGlass: reducePanelGlass, colorScheme: .dark) { fixture, window in
                    let rect = CGRect(x: kind == .brightness ? 8 : 360, y: 22, width: 32, height: 156)
                    var frames: [Double: RenderedFrame] = [:]
                    for value in [0.0, 0.5, 1.0] {
                        fixture.state.showLevel(kind, value: value)
                        try await Task.sleep(for: .milliseconds(300))
                        let frame = try self.capture(
                            window, rect: rect,
                            label: "\(kind), \(value), \(reducePanelGlass ? "reduced" : "native") glass"
                        )
                        frames[value] = frame
                        let boundary = 156 * (1 - value)
                        for y in 30..<144 {
                            let pixel = frame.pixels[y * frame.width + 5]
                            if Double(y) > boundary + 2 {
                                if y < 110 {
                                    XCTAssertGreaterThan(pixel, 215, "The translucent fill must rise from the bottom: \(kind), \(value), row \(y)")
                                    XCTAssertLessThan(pixel, 250, "The fill must not become opaque.")
                                }
                            } else if Double(y) < boundary - 2 {
                                XCTAssertLessThan(pixel, 200, "The unfilled area must remain dark: \(kind), \(value), row \(y)")
                            }
                        }
                    }
                    let empty = try XCTUnwrap(frames[0])
                    var iconReference = empty
                    var coveredReference = try XCTUnwrap(frames[1])
                    if kind == .volume {
                        fixture.state.showLevel(kind, value: 0.001)
                        try await Task.sleep(for: .milliseconds(160))
                        iconReference = try self.capture(window, rect: rect, label: "Low-volume icon above the fill")
                        fixture.state.showLevel(kind, value: 0.30)
                        try await Task.sleep(for: .milliseconds(160))
                        coveredReference = try self.capture(window, rect: rect, label: "Low-volume icon covered by fill")
                    }
                    let upperInk = (12..<96).flatMap { y in
                        (4..<28).map { x in empty.pixels[y * empty.width + x] }
                    }.filter { $0 > 220 }
                    XCTAssertTrue(upperInk.isEmpty, "There must be no percentage or other visible label above the icon.")

                    let iconInk = (110..<144).flatMap { y in
                        (2..<30).compactMap { x -> Int? in
                            let index = y * empty.width + x
                            return iconReference.pixels[index] > 240 ? index : nil
                        }
                    }
                    let zeroIconInk = (110..<144).flatMap { y in
                        (2..<30).compactMap { x -> Int? in
                            let index = y * empty.width + x
                            return empty.pixels[index] > 240 ? index : nil
                        }
                    }
                    XCTAssertGreaterThan(
                        zeroIconInk.count, kind == .volume ? 20 : 40,
                        "The native brightness or mute strokes must remain visible at zero."
                    )
                    XCTAssertGreaterThan(iconInk.count, 40)
                    if kind == .volume {
                        XCTAssertNotEqual(zeroIconInk, iconInk, "Muted and low-volume glyphs must look different.")
                    }
                    for index in iconInk {
                        XCTAssertLessThan(coveredReference.pixels[index], 60, "The same icon must be dark over white fill.")
                    }
                    let iconRows = iconInk.map { $0 / empty.width }
                    let firstRow = try XCTUnwrap(iconRows.min())
                    let lastRow = try XCTUnwrap(iconRows.max())
                    let boundary = Double(firstRow + lastRow) / 2
                    fixture.state.showLevel(kind, value: 1 - boundary / 156)
                    try await Task.sleep(for: .milliseconds(160))
                    let partial = try self.capture(window, rect: rect, label: "\(kind) fill crossing the icon's center")
                    let lightPart = iconInk.filter { Double($0 / empty.width) < boundary - 2 }
                    let darkPart = iconInk.filter { Double($0 / empty.width) > boundary + 2 }
                    XCTAssertGreaterThan(lightPart.count, 5)
                    XCTAssertGreaterThan(darkPart.count, 5)
                    for index in lightPart {
                        XCTAssertGreaterThan(partial.pixels[index], 220, "Uncovered icon pixels must stay white.")
                    }
                    for index in darkPart {
                        XCTAssertLessThan(partial.pixels[index], 60, "Only covered icon pixels should turn dark.")
                    }

                    fixture.state.showLevel(kind, value: 0)
                    try await Task.sleep(for: .milliseconds(160))
                    let drained = try self.capture(window, rect: rect, label: "\(kind) drained back to zero")
                    for index in zeroIconInk {
                        XCTAssertGreaterThan(drained.pixels[index], 220, "Draining must restore the white brightness or mute icon.")
                    }
                    XCTAssertLessThan(drained.pixels[136 * drained.width + 2], 200, "Zero must not retain fill.")
                }
            }
        }
    }

    func testVolumeMeterRendersDistinctMutedAndProgressiveWaveIcons() async throws {
        try await withFeedback { fixture, window in
            let rect = CGRect(x: 360, y: 22, width: 32, height: 156)
            var previous: RenderedFrame?
            for value in [0.0, 0.1, 0.5, 1.0] {
                fixture.state.showLevel(.volume, value: value)
                try await Task.sleep(for: .milliseconds(350))
                let frame = try self.capture(
                    window, rect: rect, label: PlayerTouchLevel.volume.systemImage(at: value)
                )
                let icon = self.cropped(frame, to: CGRect(x: 4, y: 110, width: 24, height: 30))
                let normalized = value > 0.3
                    ? RenderedFrame(width: icon.width, height: icon.height, pixels: icon.pixels.map { 255 - $0 })
                    : icon
                self.assertVisible(normalized)
                if let previous {
                    XCTAssertGreaterThan(self.difference(previous, normalized), 0.01, "Each volume tier must render its own native glyph.")
                }
                previous = normalized
            }
        }
    }

    func testLevelMetersMatchSeekFillAndTrackAcrossAppearancesAndInteractionStates() async throws {
        for reduced in [false, true] {
            for scheme in [ColorScheme.dark, .light] {
                try await withFeedback(reducePanelGlass: reduced, colorScheme: scheme) { fixture, window in
                    fixture.showsSeekReference = true
                    for kind in [PlayerTouchLevel.brightness, .volume] {
                        var filledLevels: [Double] = []
                        for active in [false, true] {
                            fixture.state.showLevel(kind, value: 0.5)
                            if !active {
                                try await Task.sleep(for: .milliseconds(300))
                                fixture.state.finishLevel()
                            }
                            try await Task.sleep(for: .milliseconds(450))
                            let frame = try self.capture(window, rect: CGRect(x: 0, y: 0, width: 400, height: 200),
                                                         label: "\(kind), \(scheme), reduced \(reduced), active \(active)")
                            let x = kind == .brightness ? 24 : 376
                            @MainActor func level(_ rect: CGRect) -> Double {
                                let pixels = self.cropped(frame, to: rect).pixels
                                return pixels.reduce(0) { $0 + Double($1) } / Double(pixels.count)
                            }
                            let meterFill = level(CGRect(x: x - 2, y: 112, width: 4, height: 4))
                            let seekFill = level(CGRect(x: 178, y: 98, width: 4, height: 4))
                            XCTAssertEqual(meterFill, seekFill, accuracy: 12,
                                           "Vertical progress must use the seek bar's actual rendered fill.")
                            let meterTrack = level(CGRect(x: x - 2, y: 58, width: 4, height: 4))
                            let seekTrack = level(CGRect(x: 218, y: 98, width: 4, height: 4))
                            XCTAssertEqual(meterTrack, seekTrack, accuracy: 12,
                                           "Both unfilled tracks must use the same native/fallback surface.")
                            XCTAssertGreaterThan(meterFill - meterTrack, 70,
                                                 "Progress must stay lighter than the track, never black on a pale slab.")
                            filledLevels.append(meterFill)
                        }
                        XCTAssertGreaterThan(abs(filledLevels[1] - filledLevels[0]), 20,
                                             "Adjusting must brighten the fill like active seeking, without becoming opaque.")
                    }
                }
            }
        }
    }

    func testLevelMetersSlideAndScaleWithoutFadingAndRespectReduceMotion() async throws {
        for reduceMotion in [false, true] {
            for kind in [PlayerTouchLevel.brightness, .volume] {
                try await withFeedback(reduceMotion: reduceMotion) { fixture, window in
                    let rect = CGRect(x: 0, y: 0, width: 400, height: 200)
                    let started = ContinuousClock.now
                    fixture.state.showLevel(kind, value: 1)
                    try await Task.sleep(until: started + .milliseconds(160), clock: .continuous)
                    let entering = try self.capture(window, rect: rect, label: "\(kind) entering, reduced motion \(reduceMotion)")
                    try await Task.sleep(until: started + .milliseconds(300), clock: .continuous)
                    let settled = try self.capture(window, rect: rect, label: "\(kind) settled, reduced motion \(reduceMotion)")
                    let finished = ContinuousClock.now
                    fixture.state.finishLevel()
                    try await Task.sleep(until: finished + .milliseconds(400), clock: .continuous)
                    let released = try self.capture(window, rect: rect, label: "\(kind) released, reduced motion \(reduceMotion)")
                    try await Task.sleep(until: finished + .milliseconds(1360), clock: .continuous)
                    let exiting = try self.capture(window, rect: rect, label: "\(kind) exiting, reduced motion \(reduceMotion)")
                    try await Task.sleep(until: finished + .milliseconds(1500), clock: .continuous)
                    let gone = try self.capture(window, rect: rect, label: "\(kind) removed, reduced motion \(reduceMotion)")

                    let fullBounds = try self.inkBounds(settled, threshold: 128)
                    XCTAssertEqual(fullBounds.width, 32, accuracy: 1)
                    XCTAssertEqual(fullBounds.height, 156, accuracy: 1)
                    XCTAssertEqual(kind == .brightness ? fullBounds.minX : 400 - fullBounds.maxX, 8, accuracy: 1)
                    if reduceMotion {
                        XCTAssertEqual(try self.inkBounds(entering, threshold: 128), fullBounds)
                        self.assertAbsent(exiting, message: "Reduce Motion must remove the meter without movement or fading.")
                    } else {
                        for (frame, reference) in [(entering, settled), (exiting, released)] {
                            self.assertVisible(frame)
                            let movingFill = frame.pixels.filter { $0 > 128 }.sorted()
                            let restingFill = reference.pixels.filter { $0 > 128 }.sorted()
                            XCTAssertFalse(movingFill.isEmpty)
                            XCTAssertEqual(
                                Double(movingFill[movingFill.count / 2]),
                                Double(restingFill[restingFill.count / 2]), accuracy: 15,
                                "Motion must not add a fade to the seek-style translucent fill."
                            )
                            let bounds = try self.inkBounds(frame, threshold: 128)
                            let outward = kind == .brightness ? fullBounds.midX - bounds.midX : bounds.midX - fullBounds.midX
                            XCTAssertGreaterThan(outward, 2, "The capsule must travel through its nearest edge.")
                            XCTAssertEqual(bounds.midY, fullBounds.midY, accuracy: 1)
                            XCTAssertLessThan(bounds.height, fullBounds.height - 2, "Entry and exit must also scale the capsule.")
                        }
                    }
                    self.assertAbsent(gone, message: "The meter must disappear after its exit transition.")
                }
            }
        }
    }

    func testDirectTouchWidensMetersInwardWithoutMovingTheirHitRegions() async throws {
        for kind in [PlayerTouchLevel.brightness, .volume] {
            try await withFeedback { fixture, window in
                let rect = CGRect(x: 0, y: 0, width: 400, height: 200)
                fixture.state.showLevel(kind, value: 1)
                try await Task.sleep(for: .milliseconds(350))
                fixture.state.finishLevel()
                try await Task.sleep(for: .milliseconds(400))
                let resting = try self.inkBounds(self.capture(window, rect: rect, label: "\(kind) passive"), threshold: 128)
                let region = try XCTUnwrap(fixture.state.levelInteractionRegion)
                XCTAssertEqual(region.kind, kind)
                XCTAssertEqual(region.frame.width, 44)
                XCTAssertEqual(region.frame.height, 156)
                fixture.state.showLevel(kind, value: 1, isDirectInteraction: true)
                try await Task.sleep(for: .milliseconds(500))
                let touched = try self.inkBounds(self.capture(window, rect: rect, label: "\(kind) directly touched"), threshold: 128)
                XCTAssertEqual(resting.width, 32, accuracy: 1)
                XCTAssertEqual(touched.width, 44, accuracy: 1)
                XCTAssertEqual(touched.height, resting.height, accuracy: 1)
                XCTAssertEqual(kind == .brightness ? touched.minX : 400 - touched.maxX, 8, accuracy: 1)
                XCTAssertEqual(fixture.state.levelInteractionRegion?.frame, region.frame)
                fixture.state.finishLevel()
                try await Task.sleep(for: .milliseconds(500))
                let released = try self.inkBounds(self.capture(window, rect: rect, label: "\(kind) touch released"), threshold: 128)
                XCTAssertEqual(released, resting)
                XCTAssertEqual(fixture.state.levelInteractionRegion?.frame, region.frame)
            }
        }
    }

    func testLevelOverdragStretchesTowardTheLimitAndSpringsBackWithoutScalingIcons() async throws {
        for reducePanelGlass in [false, true] {
            for reduceMotion in [false, true] {
                for (kind, value, overshoot) in [(PlayerTouchLevel.brightness, 1.0, 160.0), (.volume, 0.0, -160.0)] {
                    try await withFeedback(
                        reduceMotion: reduceMotion, reducePanelGlass: reducePanelGlass,
                        feedbackSize: CGSize(width: 400, height: 300)
                    ) { fixture, window in
                        let rect = CGRect(x: kind == .brightness ? 0 : 320, y: 30, width: 80, height: 240)
                        let label = "\(kind), reduced motion \(reduceMotion), reduced glass \(reducePanelGlass)"
                        fixture.state.showLevel(kind, value: value)
                        try await Task.sleep(for: .milliseconds(350))
                        let resting = try self.capture(window, rect: rect, label: "Resting \(label)")
                        fixture.state.showLevel(kind, value: value, overshoot: overshoot)
                        try await Task.sleep(for: .milliseconds(100))
                        let pulled = try self.capture(window, rect: rect, label: "Overdrag \(label)")
                        fixture.state.showLevel(kind, value: value, overshoot: overshoot * 1000)
                        try await Task.sleep(for: .milliseconds(100))
                        let capped = try self.capture(window, rect: rect, label: "Extreme overdrag \(label)")
                        fixture.state.finishLevel()
                        try await Task.sleep(for: .milliseconds(80))
                        let returning = try self.capture(window, rect: rect, label: "Spring return \(label)")
                        try await Task.sleep(for: .milliseconds(520))
                        let released = try self.capture(window, rect: rect, label: "Released \(label)")

                        let restBounds = try self.inkBounds(resting, threshold: 10)
                        let pulledBounds = try self.inkBounds(pulled, threshold: 10)
                        let cappedBounds = try self.inkBounds(capped, threshold: 10)
                        let returnBounds = try self.inkBounds(returning, threshold: 10)
                        let releasedBounds = try self.inkBounds(released, threshold: 10)
                        XCTAssertEqual(restBounds.width, 32, accuracy: 1)
                        XCTAssertEqual(restBounds.height, 156, accuracy: 1)
                        if reduceMotion {
                            for bounds in [pulledBounds, cappedBounds, returnBounds] {
                                XCTAssertEqual(bounds, restBounds, "Reduce Motion must keep the capsule stationary.")
                            }
                        } else {
                            XCTAssertEqual(pulledBounds.height - restBounds.height, 20 * 160 / 240, accuracy: 2)
                            XCTAssertEqual(pulledBounds.width, 32 * 156 / (156 + 20 * 160 / 240), accuracy: 1.5)
                            XCTAssertLessThan(pulledBounds.width, restBounds.width)
                            XCTAssertLessThanOrEqual(cappedBounds.height, restBounds.height + 21)
                            XCTAssertGreaterThanOrEqual(cappedBounds.height, restBounds.height + 18)
                            XCTAssertGreaterThan(returnBounds.height, restBounds.height + 2, "Release must spring back, not snap.")
                            XCTAssertLessThan(returnBounds.height, cappedBounds.height - 2)
                            for bounds in [pulledBounds, cappedBounds, returnBounds] {
                                XCTAssertEqual(bounds.midX, restBounds.midX, accuracy: 1)
                                if overshoot > 0 {
                                    XCTAssertEqual(bounds.maxY, restBounds.maxY, accuracy: 1, "Upward stretching must anchor the bottom.")
                                } else {
                                    XCTAssertEqual(bounds.minY, restBounds.minY, accuracy: 1, "Downward stretching must anchor the top.")
                                }
                            }
                        }
                        XCTAssertEqual(releasedBounds.minX, restBounds.minX, accuracy: 1)
                        XCTAssertEqual(releasedBounds.minY, restBounds.minY, accuracy: 1)
                        XCTAssertEqual(releasedBounds.width, restBounds.width, accuracy: 1)
                        XCTAssertEqual(releasedBounds.height, restBounds.height, accuracy: 1)
                        XCTAssertEqual(fixture.state.level?.value, value)
                        XCTAssertEqual(fixture.state.level?.overshoot, 0)

                        @MainActor func iconFrame(_ frame: RenderedFrame, bounds: CGRect) -> RenderedFrame {
                            let icon = self.cropped(frame, to: CGRect(
                                x: bounds.midX - 12, y: bounds.maxY - 38, width: 24, height: 24
                            ))
                            return value == 1
                                ? RenderedFrame(width: icon.width, height: icon.height, pixels: icon.pixels.map { 255 - $0 })
                                : icon
                        }
                        let restIcon = try self.inkBounds(iconFrame(resting, bounds: restBounds))
                        let pulledIcon = try self.inkBounds(iconFrame(pulled, bounds: pulledBounds))
                        XCTAssertEqual(pulledIcon.width, restIcon.width, accuracy: 1)
                        XCTAssertEqual(pulledIcon.height, restIcon.height, accuracy: 1, "The symbol must not stretch with the capsule.")
                    }
                }
            }
        }
    }

    private func assertFlight(direction: PlayerTouchSkipDirection) async throws {
        try await withFeedback(direction: direction) { fixture, window in
            let interval: TimeInterval = direction == .forward ? 25 : -25
            XCTAssertNil(fixture.state.skip)
            var lastPulseAt = ContinuousClock.now
            for pulse in 1...2 {
                let startedAt = ContinuousClock.now
                lastPulseAt = startedAt
                fixture.seek(by: interval)
                var frames: [Int: RenderedFrame] = [:]
                for milliseconds in [40, 60, 170, 300, 500, 720, 880, 1000, 1120] {
                    try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                    frames[milliseconds] = try self.captureGlyphs(
                        window, direction: direction, label: "Pulse \(pulse), target \(milliseconds) ms", since: startedAt
                    )
                }
                let folded = try XCTUnwrap(frames[40])
                let early = try XCTUnwrap(frames[60])
                let traveling = try XCTUnwrap(frames[170])
                let parked = try XCTUnwrap(frames[300])
                let fading = try XCTUnwrap(frames[880])
                let late = try XCTUnwrap(frames[1000])
                self.assertVisible(folded)
                self.assertVisible(early)
                self.assertVisible(traveling)
                self.assertVisible(parked)
                self.assertVisible(fading)
                self.assertVisible(late)
                XCTAssertEqual(self.componentCount(early), 1, "Each isolated tap must launch one open chevron")
                XCTAssertGreaterThan(self.difference(early, traveling), 0.12, "Each accepted pulse must visibly animate")
                let travel = self.horizontalCentroid(traveling) - self.horizontalCentroid(early)
                XCTAssertGreaterThan(
                    travel * (direction == .forward ? 1 : -1), 3,
                    "The chevron must translate outward, not just fade or scale in place"
                )
                let earlyEnergy = self.inkEnergy(early)
                let parkedEnergy = self.inkEnergy(parked)
                let parkedCenter = self.horizontalCentroid(parked)
                let fadingEnergy = self.inkEnergy(fading)
                let lateEnergy = self.inkEnergy(late)
                let foldedSpread = self.horizontalSpread(folded)
                let parkedSpread = self.horizontalSpread(parked)
                XCTAssertGreaterThan(
                    foldedSpread, parkedSpread * 0.35,
                    "The first visible chevron must already be bent rather than starting as a flat stroke"
                )
                XCTAssertLessThan(
                    foldedSpread, parkedSpread * 0.8,
                    "A flight must start partially folded, not translate an already-open chevron"
                )
                XCTAssertGreaterThan(
                    self.horizontalSpread(traveling), foldedSpread * 1.25,
                    "The chevron must visibly unfold while traveling outward"
                )
                XCTAssertEqual(
                    try self.inkBounds(folded).height, try self.inkBounds(parked).height, accuracy: 1,
                    "Unfolding must change only horizontal shape, not the icon's proportional height"
                )
                try self.assertTypographyMatches(
                    parked, reference: self.typographyReference(kind: .chevron), antialiasWeighted: true,
                    message: "Travel must finish at the full native button-label chevron with full opacity"
                )
                // Horizontal scaling legitimately increases integrated ink. Divide by its
                // measured spread to distinguish unfolding from an early opacity fade.
                let earlyDensity = earlyEnergy / self.horizontalSpread(early)
                let parkedDensity = parkedEnergy / parkedSpread
                XCTAssertEqual(
                    earlyDensity, parkedDensity, accuracy: parkedDensity * 0.15,
                    "Unfolding must retain opacity instead of fading or brightening during travel"
                )
                for milliseconds in [500, 720] {
                    let held = try XCTUnwrap(frames[milliseconds])
                    XCTAssertEqual(
                        self.horizontalCentroid(held), parkedCenter, accuracy: 0.5,
                        "The chevron must stay parked throughout its half-second hold"
                    )
                    XCTAssertEqual(
                        self.inkEnergy(held), parkedEnergy, accuracy: parkedEnergy * 0.05,
                        "The chevron must stay fully opaque until its half-second hold finishes"
                    )
                }
                for frame in [fading, late] {
                    XCTAssertEqual(
                        self.horizontalCentroid(frame), parkedCenter, accuracy: 0.5,
                        "The fade must not restart or continue horizontal travel"
                    )
                }
                XCTAssertGreaterThan(
                    fadingEnergy, parkedEnergy * 0.25,
                    "The chevron must fade gradually after its parked hold"
                )
                XCTAssertLessThan(fadingEnergy, parkedEnergy * 0.97, "Fading must begin after the half-second hold")
                XCTAssertGreaterThan(lateEnergy, parkedEnergy * 0.05, "The flight must remain visible near its end")
                XCTAssertLessThan(
                    lateEnergy, fadingEnergy * 0.8,
                    "The chevron must progressively fade, not stay opaque until abrupt removal"
                )
                self.assertAbsent(try XCTUnwrap(frames[1120]))
                XCTAssertEqual(fixture.state.skip?.seconds, interval * Double(pulse), "The cumulative HUD must still be present")
                XCTAssertEqual(fixture.state.skip?.pulse, pulse)
                XCTAssertEqual(fixture.state.skip?.direction, direction)
                XCTAssertEqual(fixture.state.skip?.target, 300 + interval * Double(pulse))
                try self.assertVisibleCompactCount(window, direction: direction, seconds: interval * Double(pulse))
            }
            try await Task.sleep(until: lastPulseAt + .milliseconds(1300), clock: .continuous)
            XCTAssertNil(fixture.state.skip, "Flight completion must not change the existing feedback expiry")
            let expired = try self.captureIndicator(window, direction: direction, label: "Feedback expired")
            self.assertAbsent(expired)
        }
    }

    private func assertRapidTaps(direction: PlayerTouchSkipDirection) async throws {
        try await withFeedback(direction: direction) { fixture, window in
            let sign = direction == .forward ? 1.0 : -1.0
            let startedAt = ContinuousClock.now
            fixture.seek(by: sign * 25)
            // Two-digit totals keep text layout out of the flight geometry comparison.
            let burst = Task { @MainActor in
                var lastPulseAt = startedAt
                for milliseconds in [150, 300, 450] {
                    try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                    fixture.seek(by: sign * 5)
                    lastPulseAt = ContinuousClock.now
                }
                return lastPulseAt
            }
            defer { burst.cancel() }
            var frames: [Int: RenderedFrame] = [:]
            for milliseconds in [60, 220, 370, 520, 780] {
                try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                frames[milliseconds] = try self.captureGlyphs(
                    window, direction: direction, label: "Rapid taps, target \(milliseconds) ms", since: startedAt
                )
            }
            let lastPulseAt = try await burst.value
            XCTAssertLessThan(lastPulseAt, startedAt + .milliseconds(550), "The burst must occur during the first flight")
            let single = try XCTUnwrap(frames[60])
            self.assertVisible(single)
            let parked = try XCTUnwrap(frames[780])
            self.assertVisible(parked)
            let parkedBounds = try self.inkBounds(parked, threshold: 32)
            let referenceBounds = try self.inkBounds(self.typographyReference(kind: .chevron), threshold: 32)
            XCTAssertEqual(
                parkedBounds.width, referenceBounds.width, accuracy: 2,
                "Finished travel must bring the parked glyphs to the same position"
            )
            // At each new tap +70 ms, the new glyph is still about 10 points behind the older
            // parked glyphs. Combined extent proves coexistence even when their pixels intersect.
            for milliseconds in [220, 370, 520] {
                let overlap = try XCTUnwrap(frames[milliseconds])
                self.assertVisible(overlap)
                let bounds = try self.inkBounds(overlap, threshold: 32)
                XCTAssertGreaterThan(
                    bounds.width, parkedBounds.width + 5,
                    "Each new moving glyph must coexist with older parked glyphs at \(milliseconds) ms"
                )
                let outerEdge = direction == .forward ? bounds.maxX : bounds.minX
                let parkedEdge = direction == .forward ? parkedBounds.maxX : parkedBounds.minX
                XCTAssertEqual(
                    outerEdge, parkedEdge, accuracy: 3,
                    "A new tap must not pull the older glyph back from its parked position"
                )
            }
            var completionFrames: [Int: RenderedFrame] = [:]
            for milliseconds in [670, 830, 980] {
                try await Task.sleep(until: lastPulseAt + .milliseconds(milliseconds), clock: .continuous)
                let frame = try self.captureGlyphs(
                    window, direction: direction, label: "Independent completions, target \(milliseconds) ms", since: lastPulseAt
                )
                completionFrames[milliseconds] = frame
                self.assertVisible(frame, message: "Earlier completions must not remove the last flight")
                XCTAssertEqual(
                    self.horizontalCentroid(frame), self.horizontalCentroid(parked), accuracy: 0.5,
                    "Surviving glyphs must remain parked while older flights finish"
                )
            }
            let heldEnergy = self.inkEnergy(try XCTUnwrap(completionFrames[670]))
            let fadingEnergy = self.inkEnergy(try XCTUnwrap(completionFrames[830]))
            let lastEnergy = self.inkEnergy(try XCTUnwrap(completionFrames[980]))
            XCTAssertGreaterThan(
                heldEnergy, self.inkEnergy(parked) * 0.85,
                "The last glyph must retain its full hold after the first flight completes"
            )
            XCTAssertLessThan(
                lastEnergy, fadingEnergy * 0.8,
                "Older parked copies must fade independently instead of restarting their lifetime on every tap"
            )
            try await Task.sleep(until: lastPulseAt + .milliseconds(1120), clock: .continuous)
            let tail = try self.captureGlyphs(
                window, direction: direction, label: "Burst tail, target 1120 ms", since: lastPulseAt
            )
            self.assertAbsent(tail, message: "All flights must disappear without replay before the count expires")
            XCTAssertEqual(fixture.state.skip?.pulse, 4)
            XCTAssertEqual(fixture.state.skip?.seconds, sign * 40, "Every accepted tap must contribute to the held total")
            XCTAssertEqual(fixture.state.skip?.direction, direction)
            XCTAssertEqual(fixture.state.skip?.target, 300 + sign * 40)
            try self.assertVisibleCompactCount(window, direction: direction, seconds: sign * 40)
        }
    }

    @discardableResult
    private func assertCompactIndicator(
        _ glyphs: RenderedFrame, indicator: RenderedFrame, direction: PlayerTouchSkipDirection, seconds: TimeInterval
    ) throws -> CGFloat {
        XCTAssertEqual(componentCount(glyphs), 1, "Reduce Motion must retain exactly one open chevron")
        let glyphBounds = try inkBounds(glyphs)
        try assertTypographyMatches(
            glyphs, reference: typographyReference(kind: .chevron), antialiasWeighted: true,
            message: "Reduced Motion must retain the full proportional button-label chevron"
        )
        let capsule = try inkBounds(indicator, threshold: 12)
        let fullMotionCapsule = try inkBounds(XCTUnwrap(idleIndicator), threshold: 12)
        XCTAssertEqual(
            capsule.width, fullMotionCapsule.width - 20, accuracy: 1,
            "Reduce Motion must remove the entire unused 20-point travel reservation"
        )
        XCTAssertEqual(capsule.midX, fullMotionCapsule.midX, accuracy: 0.5, "Removing travel space must keep the pill centered")
        let origin = glyphRect(direction: direction, reduceMotion: true).minX - indicatorRect(direction: direction).minX
        let clearance = direction == .forward
            ? capsule.maxX - (origin + glyphBounds.maxX)
            : origin + glyphBounds.minX - capsule.minX
        XCTAssertGreaterThanOrEqual(clearance, 16, "The stationary chevron must retain its outer padding")
        try assertNumberChevronGap(
            glyphBounds.offsetBy(dx: origin, dy: 0),
            indicator: indicator, direction: direction, seconds: seconds, reduceMotion: true
        )
        let count = countRect(direction: direction, reduceMotion: true)
            .offsetBy(dx: -indicatorRect(direction: direction).minX, dy: -indicatorRect(direction: direction).minY)
        try assertCompactCount(cropped(indicator, to: count), seconds: seconds)
        return clearance
    }

    private func assertVisibleCompactCount(
        _ window: UIWindow, direction: PlayerTouchSkipDirection, seconds: TimeInterval
    ) throws {
        let count = try capture(
            window, rect: countRect(direction: direction), label: "\(direction) — compact skip count"
        )
        try assertCompactCount(count, seconds: seconds)
    }

    private func countRect(direction: PlayerTouchSkipDirection, reduceMotion: Bool = false) -> CGRect {
        let shift: CGFloat = reduceMotion ? (direction == .forward ? 10 : -10) : 0
        return CGRect(x: (direction == .forward ? 278 : 86) + shift, y: 82, width: 36, height: 36)
    }

    private func assertNumberChevronGap(
        _ glyphBounds: CGRect, indicator: RenderedFrame, direction: PlayerTouchSkipDirection,
        seconds: TimeInterval, reduceMotion: Bool
    ) throws {
        let region = countRect(direction: direction, reduceMotion: reduceMotion)
            .offsetBy(dx: -indicatorRect(direction: direction).minX, dy: -indicatorRect(direction: direction).minY)
        let count = try inkBounds(cropped(indicator, to: region))
            .offsetBy(dx: region.minX, dy: region.minY)
        let gap = direction == .forward ? glyphBounds.minX - count.maxX : count.minX - glyphBounds.maxX
        let travel: CGFloat = reduceMotion ? 0 : 20
        let reference = try typographyReference(kind: .spacing(seconds))
        let columns = (0..<reference.width).filter { x in
            (0..<reference.height).contains { reference.pixels[$0 * reference.width + x] > 128 }
        }
        let nativeGap = zip(columns, columns.dropFirst()).map { $1 - $0 - 1 }.max() ?? 0
        XCTAssertGreaterThanOrEqual(nativeGap, 4)
        XCTAssertEqual(
            gap, CGFloat(nativeGap) + travel, accuracy: 1.5,
            "The gap must match a native 4-point label/icon stack plus active travel, including glyph bearings"
        )
    }

    private func assertCompactCount(_ count: RenderedFrame, seconds: TimeInterval) throws {
        assertVisible(count, message: "The accumulated count must remain after the chevrons have disappeared")
        try assertTypographyMatches(
            count, reference: typographyReference(kind: .count(seconds)),
            message: "The skip count must match PlayerTabButtonStyle's callout semibold text"
        )
    }

    private func assertCapsule(_ frame: RenderedFrame, reducePanelGlass: Bool) throws -> CGRect {
        let bounds = try inkBounds(frame, threshold: 12)
        XCTAssertGreaterThan(bounds.width, 70, "Feedback must include the smaller player typography and 16-point side insets")
        XCTAssertLessThanOrEqual(bounds.width, 160)
        XCTAssertGreaterThanOrEqual(bounds.height, 32)
        XCTAssertLessThanOrEqual(bounds.height, 54)
        let corner = cropped(frame, to: CGRect(x: bounds.minX + 1, y: bounds.minY + 1, width: 2, height: 2))
        assertAbsent(corner, message: "The feedback surface must have capsule corners rather than a rectangular fill")
        let interior = cropped(frame, to: CGRect(x: bounds.midX - 8, y: bounds.minY + 5, width: 16, height: 2))
        XCTAssertGreaterThan(
            inkEnergy(interior) / Double(max(interior.pixels.count, 1)), 4,
            reducePanelGlass
                ? "Reduced glass must render the shared frosted surface behind the foreground"
                : "Native glass interior was not captured by drawHierarchy; a border alone is not native-glass evidence"
        )
        return bounds
    }

    private func withFeedback(
        direction: PlayerTouchSkipDirection? = nil, reduceMotion: Bool = false, reducePanelGlass: Bool = true,
        colorScheme: ColorScheme = .dark,
        feedbackSize: CGSize = CGSize(width: 400, height: 200),
        _ operation: (FeedbackFixture, UIWindow) async throws -> Void
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let fixture = FeedbackFixture(
            reduceMotion: direction == nil ? reduceMotion : false,
            reducePanelGlass: reducePanelGlass, colorScheme: colorScheme, feedbackSize: feedbackSize
        )
        let host = UIHostingController(rootView: FeedbackFixtureView(fixture: fixture))
        host.safeAreaRegions = []
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            fixture.state.cancel()
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
            for capture in capturedImages {
                let attachment = XCTAttachment(image: capture.image)
                attachment.name = capture.name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            capturedImages.removeAll()
            idleIndicator = nil
            typographyReferences.removeAll()
        }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        try await prepareTypographyReferences(fixture, window: window)
        if let direction {
            // Use the real idle pill as the contrast reference. The phase/overlap tests exercise
            // the supported deterministic frosted path; native glass gets separate rendered coverage.
            fixture.seek(by: direction == .forward ? 25 : -25)
            try await Task.sleep(for: .milliseconds(1120))
            let background = try captureIndicator(window, direction: direction, label: "Idle pill contrast reference")
            let region = glyphRect(direction: direction)
                .offsetBy(dx: -indicatorRect(direction: direction).minX, dy: -indicatorRect(direction: direction).minY)
            let backgroundGlyphs = cropped(background, to: region)
            XCTAssertLessThanOrEqual(
                backgroundGlyphs.pixels.max() ?? 0, 96,
                "The idle frosted reference must not contain a resting white chevron"
            )
            idleIndicator = background
            fixture.state.cancel()
            fixture.state = PlayerTouchGestureState()
            fixture.reduceMotion = reduceMotion
            try await Task.sleep(for: .milliseconds(60))
        }
        try await operation(fixture, window)
    }

    private struct RenderedFrame {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    private func captureGlyphs(
        _ window: UIWindow, direction: PlayerTouchSkipDirection, reduceMotion: Bool = false, label: String,
        since: ContinuousClock.Instant? = nil
    ) throws -> RenderedFrame {
        let rect = glyphRect(direction: direction, reduceMotion: reduceMotion)
        let frame = try capture(
            window, rect: rect, label: "\(direction) — \(label)", since: since
        )
        guard let idleIndicator else { return frame }
        // Removing the directional 20-point reservation moves the outer capsule edge inward
        // by 10 points. Sample the same real idle surface relative to that mirrored edge.
        let shift: CGFloat = reduceMotion ? (direction == .forward ? 10 : -10) : 0
        let referenceRect = rect.offsetBy(
            dx: shift - indicatorRect(direction: direction).minX,
            dy: -indicatorRect(direction: direction).minY
        )
        return removingBackground(frame, cropped(idleIndicator, to: referenceRect))
    }

    private func glyphRect(direction: PlayerTouchSkipDirection, reduceMotion: Bool = false) -> CGRect {
        let x: CGFloat = direction == .forward ? 312 : 36
        return CGRect(x: x + (reduceMotion ? 10 : 0), y: 76, width: reduceMotion ? 32 : 52, height: 48)
    }

    private func indicatorRect(direction: PlayerTouchSkipDirection) -> CGRect {
        let center: CGFloat = direction == .forward ? 312 : 88
        return CGRect(x: center - 85, y: 64, width: 170, height: 72)
    }

    private func captureIndicator(
        _ window: UIWindow, direction: PlayerTouchSkipDirection, label: String
    ) throws -> RenderedFrame {
        return try capture(
            window, rect: indicatorRect(direction: direction),
            label: "\(direction) — \(label)"
        )
    }

    private enum TypographyReference: Hashable {
        case count(TimeInterval), spacing(TimeInterval), rate, chevron, fastForward
    }

    private func prepareTypographyReferences(_ fixture: FeedbackFixture, window: UIWindow) async throws {
        let totals: [TimeInterval] = [25, 40, 50, -25, -40, -50]
        for seconds in totals {
            fixture.referenceCount = seconds
            try await Task.sleep(for: .milliseconds(40))
            typographyReferences[.count(seconds)] = try captureTypographyReference(window, kind: .count(seconds))
            typographyReferences[.spacing(seconds)] = try captureTypographyReference(window, kind: .spacing(seconds))
        }
        for kind in [TypographyReference.rate, .chevron, .fastForward] {
            typographyReferences[kind] = try captureTypographyReference(window, kind: kind)
        }
        fixture.referenceIconsVisible = false
        try await Task.sleep(for: .milliseconds(40))
        for kind in [TypographyReference.chevron, .fastForward] {
            let background = try captureTypographyReference(window, kind: kind, background: true)
            typographyReferences[kind] = removingBackground(try typographyReference(kind: kind), background)
        }
        fixture.showsTypographyReferences = false
        try await Task.sleep(for: .milliseconds(60))
    }

    private func typographyReference(kind: TypographyReference) throws -> RenderedFrame {
        try XCTUnwrap(typographyReferences[kind], "Typography references must be captured before the gesture clock starts")
    }

    private func captureTypographyReference(
        _ window: UIWindow, kind: TypographyReference, background: Bool = false
    ) throws -> RenderedFrame {
        let rect: CGRect
        switch kind {
        case .count: rect = CGRect(x: 30, y: 230, width: 60, height: 40)
        case .spacing: rect = CGRect(x: 0, y: 280, width: 120, height: 60)
        case .rate: rect = CGRect(x: 150, y: 230, width: 60, height: 40)
        case .chevron: rect = CGRect(x: 240, y: 226, width: 60, height: 48)
        case .fastForward: rect = CGRect(x: 300, y: 226, width: 60, height: 48)
        }
        return try capture(window, rect: rect, label: "Player typography reference — \(kind)\(background ? " background" : "")")
    }

    private func assertTypographyMatches(
        _ actual: RenderedFrame, reference: RenderedFrame, antialiasWeighted: Bool = false, message: String
    ) throws {
        let actualBounds = try inkBounds(actual)
        let referenceBounds = try inkBounds(reference)
        XCTAssertEqual(actualBounds.width, referenceBounds.width, accuracy: 1, message)
        XCTAssertEqual(actualBounds.height, referenceBounds.height, accuracy: 1, message)
        if antialiasWeighted {
            // Summed antialias coverage preserves thin strokes across fractional origins and
            // mirroring; a hard threshold can count the same native chevron as 32 or 49 pixels.
            let actualInk = inkEnergy(actual) / 255
            let referenceInk = inkEnergy(reference) / 255
            XCTAssertEqual(
                actualInk, referenceInk, accuracy: max(1, referenceInk * 0.05),
                "\(message); antialias-weighted stroke coverage must match"
            )
        } else {
            let actualInk = Double(actual.pixels.filter { $0 > 128 }.count)
            let referenceInk = Double(reference.pixels.filter { $0 > 128 }.count)
            XCTAssertEqual(
                actualInk, referenceInk, accuracy: max(3, referenceInk * 0.15),
                "\(message); stroke coverage must match as well as bounding size"
            )
        }
    }

    private func capture(
        _ window: UIWindow, rect: CGRect, label: String, since: ContinuousClock.Instant? = nil
    ) throws -> RenderedFrame {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let capturedAt = ContinuousClock.now
        let image = renderer.image { context in
            context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: false))
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let duration = milliseconds(from: capturedAt, to: ContinuousClock.now)
        let elapsed = since.map { "actual \(milliseconds(from: $0, to: capturedAt)) ms, " } ?? ""
        capturedImages.append((image, "\(label) — \(elapsed)capture \(duration) ms"))
        return RenderedFrame(width: width, height: height, pixels: pixels)
    }

    private func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Int {
        let duration = start.duration(to: end).components
        return Int(duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000)
    }

    private func removingBackground(_ frame: RenderedFrame, _ background: RenderedFrame) -> RenderedFrame {
        XCTAssertEqual(frame.width, background.width)
        XCTAssertEqual(frame.height, background.height)
        let pixels = zip(frame.pixels, background.pixels).map { pixel, base -> UInt8 in
            let contrast = Int(pixel) - Int(base)
            guard contrast > 2, base < 255 else { return 0 }
            return UInt8(min(255, contrast * 255 / (255 - Int(base))))
        }
        return RenderedFrame(width: frame.width, height: frame.height, pixels: pixels)
    }

    private func cropped(_ frame: RenderedFrame, to rect: CGRect) -> RenderedFrame {
        let minX = max(0, min(frame.width, Int(rect.minX.rounded(.down))))
        let minY = max(0, min(frame.height, Int(rect.minY.rounded(.down))))
        let maxX = max(minX, min(frame.width, Int(rect.maxX.rounded(.up))))
        let maxY = max(minY, min(frame.height, Int(rect.maxY.rounded(.up))))
        var pixels: [UInt8] = []
        for y in minY..<maxY {
            pixels.append(contentsOf: frame.pixels[(y * frame.width + minX)..<(y * frame.width + maxX)])
        }
        return RenderedFrame(width: maxX - minX, height: maxY - minY, pixels: pixels)
    }

    private func difference(_ lhs: RenderedFrame, _ rhs: RenderedFrame) -> Double {
        let difference = zip(lhs.pixels, rhs.pixels).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(difference) / max(max(inkEnergy(lhs), inkEnergy(rhs)), 1)
    }

    private func inkEnergy(_ frame: RenderedFrame) -> Double {
        Double(frame.pixels.reduce(0) { $0 + Int($1) })
    }

    private func horizontalCentroid(_ frame: RenderedFrame) -> Double {
        let energy = inkEnergy(frame)
        XCTAssertGreaterThan(energy, 0)
        let moment = frame.pixels.enumerated().reduce(0) { $0 + ($1.offset % frame.width) * Int($1.element) }
        return Double(moment) / max(energy, 1)
    }

    private func horizontalSpread(_ frame: RenderedFrame) -> Double {
        let center = horizontalCentroid(frame)
        let variance = frame.pixels.enumerated().reduce(0.0) { sum, pixel in
            let distance = Double(pixel.offset % frame.width) - center
            return sum + distance * distance * Double(pixel.element)
        }
        return (variance / max(inkEnergy(frame), 1)).squareRoot()
    }

    private func assertVisible(
        _ frame: RenderedFrame, message: String = "The traveling chevron must be visible",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThan(frame.pixels.filter { $0 > 8 }.count, 20, message, file: file, line: line)
    }

    private func assertAbsent(
        _ frame: RenderedFrame, message: String = "A completed flight must leave no resting or replaying chevron",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(frame.pixels.max() ?? 0, 3, message, file: file, line: line)
    }

    private func inkBounds(_ frame: RenderedFrame, threshold: UInt8 = 128) throws -> CGRect {
        let ink = frame.pixels.indices.filter { frame.pixels[$0] > threshold }
        let xs = ink.map { $0 % frame.width }
        let ys = ink.map { $0 / frame.width }
        let minX = try XCTUnwrap(xs.min())
        let minY = try XCTUnwrap(ys.min())
        let maxX = try XCTUnwrap(xs.max())
        let maxY = try XCTUnwrap(ys.max())
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func componentCount(_ frame: RenderedFrame, threshold: UInt8 = 128) -> Int {
        var remaining = Set(frame.pixels.indices.filter { frame.pixels[$0] > threshold })
        var count = 0
        while let seed = remaining.first {
            remaining.remove(seed)
            var queue = [seed]
            var size = 0
            while let index = queue.popLast() {
                size += 1
                for dy in -1...1 {
                    for dx in -1...1 {
                        let x = index % frame.width + dx
                        let y = index / frame.width + dy
                        guard (0..<frame.width).contains(x), (0..<frame.height).contains(y) else { continue }
                        let neighbor = y * frame.width + x
                        if remaining.remove(neighbor) != nil { queue.append(neighbor) }
                    }
                }
            }
            if size > 10 { count += 1 }
        }
        return count
    }
}

@MainActor
@Observable
private final class FeedbackFixture {
    var state = PlayerTouchGestureState()
    var reduceMotion: Bool
    var referenceCount: TimeInterval = 25
    var referenceIconsVisible = true
    var showsTypographyReferences = true
    var showsSeekReference = false
    let reducePanelGlass: Bool
    let colorScheme: ColorScheme
    let feedbackSize: CGSize

    init(reduceMotion: Bool, reducePanelGlass: Bool, colorScheme: ColorScheme, feedbackSize: CGSize) {
        self.reduceMotion = reduceMotion
        self.reducePanelGlass = reducePanelGlass
        self.colorScheme = colorScheme
        self.feedbackSize = feedbackSize
    }

    func seek(by interval: TimeInterval) {
        _ = state.seek(by: interval, from: 300, within: 0...600)
    }
}

private struct FeedbackFixtureView: View {
    let fixture: FeedbackFixture

    var body: some View {
        PlayerTouchGestureFeedbackContent(state: fixture.state, reduceMotion: fixture.reduceMotion)
            .frame(width: fixture.feedbackSize.width, height: fixture.feedbackSize.height)
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.black)
            .overlay(alignment: .topLeading) {
                if fixture.showsSeekReference, let level = fixture.state.level, let value = level.value {
                    PlayerTouchScrubTrack(
                        width: 80, progressFraction: value, bufferedFraction: 0,
                        segments: [], duration: 600, isTouching: level.isDragging
                    )
                    .frame(width: 80, height: 20)
                    .offset(x: 160, y: 90)
                }
            }
            .overlay(alignment: .topLeading) {
                if fixture.showsTypographyReferences {
                    FeedbackTypographyReferenceView(fixture: fixture)
                        .offset(y: 220)
                }
            }
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.colorScheme, fixture.colorScheme)
            .environment(\.plozzReducePanelGlass, fixture.reducePanelGlass)
            .ignoresSafeArea()
    }
}

private struct FeedbackTypographyReferenceView: View {
    let fixture: FeedbackFixture

    var body: some View {
        HStack(spacing: 0) {
            Button {} label: {
                Text(fixture.referenceCount, format: .number.sign(strategy: .always()).precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .buttonStyle(PlayerTabButtonStyle(focused: false, selected: true))
            .frame(width: 120, height: 60)
            Button {} label: {
                Text(verbatim: "2×").monospacedDigit()
            }
            .buttonStyle(PlayerTabButtonStyle(focused: false, selected: true))
            .frame(width: 120, height: 60)
            Button {} label: {
                Image(systemName: "chevron.right")
                    .opacity(fixture.referenceIconsVisible ? 1 : 0)
            }
            .buttonStyle(PlayerTabButtonStyle(focused: false, selected: true))
            .frame(width: 60, height: 60)
            Button {} label: {
                Image(systemName: "forward.fill")
                    .opacity(fixture.referenceIconsVisible ? 1 : 0)
            }
            .buttonStyle(PlayerTabButtonStyle(focused: false, selected: true))
            .frame(width: 60, height: 60)
        }
        .foregroundStyle(.white)
        .environment(\.plozzReducePanelGlass, true)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                if fixture.referenceCount < 0 { Image(systemName: "chevron.left").frame(height: 30) }
                Text(fixture.referenceCount, format: .number.sign(strategy: .always()).precision(.fractionLength(0)))
                    .monospacedDigit()
                if fixture.referenceCount > 0 { Image(systemName: "chevron.right").frame(height: 30) }
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 120, height: 60)
            .offset(y: 60)
        }
    }
}
#endif
