import CoreModels
import MediaPlayer
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlayerTouchLevelTests: XCTestCase {
    func testSettingsDefaultUpgradeRoundTripAndProfileIsolation() throws {
        XCTAssertTrue(PlaybackSettings.default.volumeBrightnessGestures)
        let legacy = try JSONDecoder().decode(PlaybackSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.volumeBrightnessGestures)
        let suite = "PlayerTouchLevelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let primary = PlaybackSettingsStore(defaults: defaults)
        let guest = PlaybackSettingsStore(defaults: defaults, namespace: "guest")
        let model = PlaybackSettingsModel(store: guest)
        model.settings.volumeBrightnessGestures = false
        XCTAssertFalse(guest.load().volumeBrightnessGestures)
        XCTAssertTrue(primary.load().volumeBrightnessGestures)
        XCTAssertEqual(guest.load(), model.settings)
    }

    func testSwipeZonesKeepCenterNeutralAndValuesAreRelativeAndBounded() {
        XCTAssertEqual(PlayerTouchLevelDrag.kind(at: 180, width: 1000), .brightness)
        XCTAssertNil(PlayerTouchLevelDrag.kind(at: 500, width: 1000))
        XCTAssertEqual(PlayerTouchLevelDrag.kind(at: 820, width: 1000), .volume)
        XCTAssertNil(PlayerTouchLevelDrag.kind(at: -1, width: 1000))
        XCTAssertNil(PlayerTouchLevelDrag.kind(at: 0, width: 0))
        let drag = PlayerTouchLevelDrag(kind: .volume, startValue: 0.5, height: 800)
        XCTAssertEqual(drag.adjustment(translationY: -160)?.value, 0.7)
        XCTAssertEqual(drag.adjustment(translationY: 240)?.value, 0.2)
        XCTAssertEqual(drag.adjustment(translationY: -1000)?.value, 1)
        XCTAssertEqual(drag.adjustment(translationY: 1000)?.value, 0)
        XCTAssertNil(drag.adjustment(translationY: .nan))
    }

    func testLevelFeedbackReplacesSkippingAndCancellationClearsIt() async throws {
        let state = PlayerTouchGestureState()
        defer { state.cancel() }
        _ = state.seek(by: 10, from: 20, within: 0...100)
        state.showLevel(.brightness, value: 0.4)
        XCTAssertNil(state.skip)
        XCTAssertEqual(state.level?.value, 0.4)
        XCTAssertTrue(state.isActive)
        state.finishLevel()
        try await Task.sleep(for: .milliseconds(1400))
        XCTAssertNil(state.level)
        state.showLevel(.volume, value: nil)
        XCTAssertNil(state.level?.value)
        XCTAssertTrue(state.isActive, "Unavailable output still needs visible feedback.")
        state.cancel()
        XCTAssertFalse(state.isActive)
    }

    func testDirectPositionUsesTheBarHeightAndHapticsStartFromTheActualOutput() throws {
        for kind in [PlayerTouchLevel.brightness, .volume] {
            var drag = PlayerTouchLevelDrag(kind: kind, startValue: 1, height: 156, initialFeedbackValue: 0.4)
            for (y, expected, overshoot) in [
                (0.0, 1.0, 0.0), (39, 0.75, 0), (78, 0.5, 0), (156, 0, 0), (-28, 1, 28), (184, 0, -28)
            ] {
                let adjustment = try XCTUnwrap(drag.adjustment(translationY: y))
                XCTAssertEqual(adjustment.value, expected, accuracy: 0.001)
                XCTAssertEqual(adjustment.overshoot, overshoot, accuracy: 0.001)
            }
            XCTAssertEqual(drag.feedback(afterApplying: 1), .limit, "Tapping full from 40% must emit endpoint feedback.")
            XCTAssertNil(drag.feedback(afterApplying: 1))
            drag = PlayerTouchLevelDrag(kind: kind, startValue: 1, height: 156, initialFeedbackValue: 0)
            XCTAssertNil(drag.feedback(afterApplying: 0), "Touching the already-selected minimum must not buzz.")
            XCTAssertEqual(drag.feedback(afterApplying: 0.5), .step)
            XCTAssertEqual(drag.feedback(afterApplying: 0), .limit)
        }
    }

    func testDirectContactCancelsExpiryUntilReleaseAndDoesNotWidenScreenSwipes() async throws {
        let state = PlayerTouchGestureState()
        defer { state.cancel() }
        state.showLevel(.brightness, value: 0.5)
        XCTAssertEqual(state.level?.isDirectInteraction, false)
        state.finishLevel()
        state.showLevel(.brightness, value: 0.75, isDirectInteraction: true)
        try await Task.sleep(for: .milliseconds(1400))
        XCTAssertEqual(state.level?.value, 0.75)
        XCTAssertEqual(state.level?.isDirectInteraction, true)
        state.finishLevel()
        XCTAssertEqual(state.level?.isDirectInteraction, false)
        XCTAssertEqual(state.level?.isDragging, false)
        try await Task.sleep(for: .milliseconds(1400))
        XCTAssertNil(state.level)
    }

    func testLimitFeedbackFiresOnlyOnArrivalAndRearmsAfterLeaving() throws {
        for kind in [PlayerTouchLevel.brightness, .volume] {
            var drag = PlayerTouchLevelDrag(kind: kind, startValue: 0.5, height: 800)
            let movements: [(Double, Bool)] = [
                (-160, false), (-400, true), (-500, false), (-800, false),
                (-320, false), (-400, true), (0, false), (400, true),
                (500, false), (800, false), (320, false), (400, true)
            ]
            for (translation, expected) in movements {
                let value = try XCTUnwrap(drag.adjustment(translationY: translation)?.value)
                XCTAssertEqual(drag.feedback(afterApplying: value) == .limit, expected, "\(kind), \(translation)")
            }
        }
    }

    func testStartingAtALimitDoesNotEmitUntilLeavingAndReturning() {
        for start in [0.0, 1.0] {
            var drag = PlayerTouchLevelDrag(kind: .brightness, startValue: start, height: 800)
            XCTAssertNil(drag.feedback(afterApplying: start))
            XCTAssertNil(drag.feedback(afterApplying: start))
            XCTAssertEqual(drag.feedback(afterApplying: 0.5), .step)
            XCTAssertEqual(drag.feedback(afterApplying: start), .limit)
            XCTAssertNil(drag.feedback(afterApplying: start))
            drag = PlayerTouchLevelDrag(kind: .brightness, startValue: start, height: 800)
            XCTAssertNil(drag.feedback(afterApplying: start), "A new swipe must not inherit old endpoint feedback.")
        }
    }

    func testDragTicksTrackMeaningfulMovementInBothDirectionsWithoutRepeatedBuzzing() {
        for kind in [PlayerTouchLevel.brightness, .volume] {
            var drag = PlayerTouchLevelDrag(kind: kind, startValue: 0.5, height: 800)
            let updates: [(Double, PlayerTouchLevelDrag.Feedback?)] = [
                (0.5, nil), (0.52, nil), (0.56, .step), (0.56, nil), (0.58, nil),
                (0.50, .step), (0.48, nil), (0.44, .step), (0.01, .step),
                (0, .limit), (0, nil), (0.02, nil), (0.06, .step),
                (0.94, .step), (1, .limit), (1, nil), (0.98, nil), (0.94, .step)
            ]
            for (value, expected) in updates {
                XCTAssertEqual(drag.feedback(afterApplying: value), expected, "\(kind), \(value)")
            }
        }
    }

    func testVolumeSymbolsProgressFromMutedThroughThreeWaves() {
        for (value, symbol) in [
            (0.0, "speaker.slash.fill"), (0.001, "speaker.wave.1.fill"),
            (0.32, "speaker.wave.1.fill"), (1.0 / 3, "speaker.wave.2.fill"),
            (0.65, "speaker.wave.2.fill"), (2.0 / 3, "speaker.wave.3.fill"),
            (1.0, "speaker.wave.3.fill")
        ] {
            XCTAssertEqual(PlayerTouchLevel.volume.systemImage(at: value), symbol)
            XCTAssertNotNil(UIImage(systemName: symbol))
            XCTAssertEqual(PlayerTouchLevel.brightness.systemImage(at: value), "sun.max.fill")
        }
    }

    func testOverdragKeepsOutputsClampedAndMeasuresOnlyDistancePastTheLimit() throws {
        let drag = PlayerTouchLevelDrag(kind: .volume, startValue: 0.5, height: 800)
        for translation in [-400.0, -160, 0, 240, 400] {
            XCTAssertEqual(try XCTUnwrap(drag.adjustment(translationY: translation)).overshoot, 0, accuracy: 0.001)
        }
        let above = try XCTUnwrap(drag.adjustment(translationY: -560))
        XCTAssertEqual(above.value, 1)
        XCTAssertEqual(above.overshoot, 160, accuracy: 0.001)
        let below = try XCTUnwrap(drag.adjustment(translationY: 560))
        XCTAssertEqual(below.value, 0)
        XCTAssertEqual(below.overshoot, -160, accuracy: 0.001)
        XCTAssertNil(drag.adjustment(translationY: .infinity))
        XCTAssertNil(PlayerTouchLevelDrag(kind: .brightness, startValue: 0.5, height: 0).adjustment(translationY: 1))
    }

    func testFinishingOverdragReleasesTheStretchWithoutChangingTheOutput() {
        let state = PlayerTouchGestureState()
        defer { state.cancel() }
        for (value, overshoot) in [(1.0, 160.0), (0.0, -160.0)] {
            state.showLevel(.brightness, value: value, overshoot: overshoot)
            XCTAssertEqual(state.level?.overshoot, overshoot)
            XCTAssertEqual(state.level?.isDragging, true)
            state.finishLevel()
            XCTAssertEqual(state.level?.value, value)
            XCTAssertEqual(state.level?.overshoot, 0)
            XCTAssertEqual(state.level?.isDragging, false)
        }
    }

    func testBrightnessRestoresOnTeardownButDoesNotOverwriteAnExternalChange() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        // Simulator brightness is fixed at 0.5. Exercise ownership at the native
        // read/write boundary instead of claiming a simulated backlight changed.
        var brightness: CGFloat = 0.6
        var writes: [CGFloat] = []
        let control = PlayerTouchLevelControl(
            readBrightness: { _ in brightness },
            writeBrightness: { _, value in brightness = value; writes.append(value) }
        )
        let original = brightness
        defer {
            control.deactivate()
            window.isHidden = true
        }
        XCTAssertEqual(try control.begin(.brightness, in: host.view), Double(original))
        try control.set(.brightness, value: 0.27, in: host.view)
        XCTAssertEqual(brightness, 0.27, accuracy: 0.01)
        control.deactivate()
        XCTAssertEqual(brightness, original, accuracy: 0.01)
        _ = try control.begin(.brightness, in: host.view)
        try control.set(.brightness, value: 0.4, in: host.view)
        brightness = 0.8
        control.deactivate()
        XCTAssertEqual(brightness, 0.8, accuracy: 0.01)
        XCTAssertEqual(writes, [0.27, original, 0.4])
    }

    func testVolumeBridgeIsRemovedOnTeardownAndMissingWindowIsExplicitlyUnavailable() throws {
        let control = PlayerTouchLevelControl()
        XCTAssertThrowsError(try control.begin(.volume, in: UIView()))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer {
            control.deactivate()
            window.isHidden = true
        }
        do {
            _ = try control.begin(.volume, in: host.view)
            XCTAssertEqual(host.view.subviews.filter { $0 is MPVolumeView }.count, 1)
        } catch PlayerTouchLevelControl.Failure.unavailable {
            XCTAssertFalse(host.view.subviews.contains { $0 is MPVolumeView })
        }
        control.deactivate()
        XCTAssertFalse(host.view.subviews.contains { $0 is MPVolumeView })
    }

    func testReplacingTheGestureSurfacePreservesBrightnessUntilPlaybackDeactivates() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        var brightness: CGFloat = 0.6
        let control = PlayerTouchLevelControl(
            readBrightness: { _ in brightness },
            writeBrightness: { _, value in brightness = value }
        )
        defer {
            control.deactivate()
            window.isHidden = true
        }
        let outgoing = PlayerTouchGestureSurface.Coordinator(surface(isActive: true), sharedLevelControl: control)
        outgoing.install(in: host.view)
        _ = try control.begin(.brightness, in: host.view)
        try control.set(.brightness, value: 0.25, in: host.view)
        PlayerTouchGestureSurface.dismantleUIView(host.view, coordinator: outgoing)
        XCTAssertEqual(brightness, 0.25, "An episode/engine handoff must not restore the old brightness.")

        let incoming = PlayerTouchGestureSurface.Coordinator(surface(isActive: true), sharedLevelControl: control)
        XCTAssertEqual(try control.begin(.brightness, in: host.view), 0.25)
        try control.set(.brightness, value: 0.35, in: host.view)
        incoming.update(surface(isActive: false))
        XCTAssertEqual(brightness, 0.6, "Leaving local foreground playback restores the session's original level.")
    }

    private func surface(isActive: Bool) -> PlayerTouchGestureSurface {
        PlayerTouchGestureSurface(
            state: PlayerTouchGestureState(), shortcutsEnabled: true,
            levelsEnabled: true, isActive: isActive,
            canSeek: true, canBoost: true, canZoom: true,
            onTap: { XCTFail("A lifecycle change must not tap the player.") },
            onSkip: { _ in XCTFail("A lifecycle change must not seek.") },
            onBoostChanged: { _ in XCTFail("No hold gesture is active.") },
            onZoom: { _ in XCTFail("A lifecycle change must not zoom.") },
            onGestureStarted: { XCTFail("A lifecycle change must not begin a gesture.") }
        )
    }
}
