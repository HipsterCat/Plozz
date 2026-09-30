#if os(tvOS)
import CoreModels
import PlozzCoreUI
import SwiftUI
import UIKit
import XCTest

@MainActor
final class NightShiftOverlayHostedTests: XCTestCase {
    func testDefaultOffAndZeroStrengthLeaveNoWindowFilter() async throws {
        let model = try makeModel()
        XCTAssertFalse(model.settings.isEnabled)
        try await withWindow(model) { _, window in
            XCTAssertTrue(tints(in: window).isEmpty)
            model.settings.scheduleMode = .alwaysOn
            model.settings.warmth = .none
            model.settings.dimness = .none
            model.settings.isEnabled = true
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.channelScalars, .identity)
            XCTAssertTrue(tints(in: window).isEmpty)
        }
    }

    func testActiveTintStillWorksAndDisablingRemovesItsLayer() async throws {
        let model = try makeModel(enabled: true)
        let warmth = model.settings.warmth
        let dimness = model.settings.dimness
        try await withWindow(model) { _, window in
            try await waitFor { tints(in: window).count == 1 }
            let original = try XCTUnwrap(tints(in: window).first)
            try assertTint(original, matches: model, in: window)

            model.settings.isEnabled = false
            try await waitFor { tints(in: window).isEmpty }
            XCTAssertNil(original.superview)
            XCTAssertNil(original.layer.compositingFilter)
            XCTAssertNil(original.layer.animation(forKey: "tint"))
            XCTAssertEqual(model.settings.warmth, warmth)
            XCTAssertEqual(model.settings.dimness, dimness)

            model.settings.isEnabled = true
            try await waitFor { tints(in: window).count == 1 }
            try assertTint(try XCTUnwrap(tints(in: window).first), matches: model, in: window)
        }
    }

    func testScheduleRemovesDaytimeTintAndReinstallsItAtNight() async throws {
        let model = try makeModel(enabled: true)
        model.settings.scheduleMode = .manual
        model.previewDate = try date(hour: 12)
        try await withWindow(model) { _, window in
            XCTAssertEqual(model.channelScalars, .identity)
            XCTAssertTrue(tints(in: window).isEmpty)
            model.previewDate = try date(hour: 2)
            try await waitFor { tints(in: window).count == 1 }
            try assertTint(try XCTUnwrap(tints(in: window).first), matches: model, in: window)

            model.previewDate = try date(hour: 12)
            try await waitFor { tints(in: window).isEmpty }
            model.previewDate = try date(hour: 2)
            try await waitFor { tints(in: window).count == 1 }
            try assertTint(try XCTUnwrap(tints(in: window).first), matches: model, in: window)
        }
    }

    func testCalibrationCanTemporarilyShowAnOtherwiseInactiveTint() async throws {
        let model = try makeModel(enabled: true)
        model.settings.scheduleMode = .manual
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minutes = try XCTUnwrap(now.hour) * 60 + XCTUnwrap(now.minute)
        model.settings.manualOnMinutes = (minutes + 12 * 60) % (24 * 60)
        model.settings.manualOffMinutes = (minutes + 18 * 60) % (24 * 60)
        try await withWindow(model) { _, window in
            XCTAssertEqual(model.channelScalars, .identity)
            XCTAssertTrue(tints(in: window).isEmpty)
            model.isPreviewing = true
            try await waitFor { tints(in: window).count == 1 }
            try assertTint(try XCTUnwrap(tints(in: window).first), matches: model, in: window)
            model.isPreviewing = false
            try await waitFor { tints(in: window).isEmpty }
        }
    }

    func testReenablingDuringFadeOutCannotLoseTheNewTint() async throws {
        let model = try makeModel(enabled: true)
        try await withWindow(model) { _, window in
            try await waitFor { tints(in: window).count == 1 }
            model.settings.isEnabled = false
            try await waitFor {
                tints(in: window).first?.layer.animation(forKey: "tint") != nil
            }
            model.settings.isEnabled = true
            try await Task.sleep(for: .milliseconds(800))
            XCTAssertEqual(tints(in: window).count, 1)
            try assertTint(try XCTUnwrap(tints(in: window).first), matches: model, in: window)
        }
    }

    func testProfileSwitchDropsOldTintAndObservesTheReplacementModel() async throws {
        let original = try makeModel(enabled: true)
        let replacement = try makeModel()
        replacement.settings.warmth = .light
        replacement.settings.dimness = .none
        try await withWindow(original) { host, window in
            try await waitFor { tints(in: window).count == 1 }
            host.rootView = Fixture(model: replacement)
            try await waitFor { tints(in: window).isEmpty }

            original.settings.warmth = .onFire
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(tints(in: window).isEmpty, "The old profile no longer owns this window")

            replacement.settings.isEnabled = true
            try await waitFor { tints(in: window).count == 1 }
            try assertTint(try XCTUnwrap(tints(in: window).first), matches: replacement, in: window)
        }
    }

    func testDismantlingDuringFadeCannotReinstallTheFilter() async throws {
        let model = try makeModel(enabled: true)
        try await withWindow(model) { host, window in
            try await waitFor { tints(in: window).count == 1 }
            let original = try XCTUnwrap(tints(in: window).first)
            model.settings.isEnabled = false
            try await waitFor { original.layer.animation(forKey: "tint") != nil }
            host.rootView = Fixture(model: model, installsOverlay: false)
            try await waitFor { tints(in: window).isEmpty }
            model.settings.isEnabled = true
            try await Task.sleep(for: .milliseconds(800))
            XCTAssertTrue(tints(in: window).isEmpty)
            XCTAssertNil(original.superview)
            XCTAssertNil(original.layer.compositingFilter)
        }
    }

    private struct Fixture: View {
        var model: NightShiftSettingsModel
        var installsOverlay = true
        var appeared: () -> Void = {}

        var body: some View {
            Group {
                if installsOverlay {
                    Color.black.installNightShiftOverlay(model)
                } else {
                    Color.black
                }
            }
            .onAppear(perform: appeared)
        }
    }

    private func withWindow(
        _ model: NightShiftSettingsModel,
        body: (UIHostingController<Fixture>, UIWindow) async throws -> Void
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        var appeared = false
        let host = UIHostingController(rootView: Fixture(model: model, appeared: { appeared = true }))
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        try await waitFor { appeared }
        window.layoutIfNeeded()
        try await body(host, window)
    }

    private func makeModel(enabled: Bool = false) throws -> NightShiftSettingsModel {
        let suite = "NightShiftOverlayHostedTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let model = NightShiftSettingsModel(store: NightShiftSettingsStore(defaults: defaults))
        model.settings.scheduleMode = .alwaysOn
        model.settings.isEnabled = enabled
        return model
    }

    private func date(hour: Int) throws -> Date {
        try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026, month: 9, day: 30, hour: hour, minute: 0
        )))
    }

    private func tints(in window: UIWindow) -> [UIView] {
        window.subviews.filter { ($0.layer.compositingFilter as? String) == "multiplyBlendMode" }
    }

    private func assertTint(
        _ view: UIView, matches model: NightShiftSettingsModel, in window: UIWindow
    ) throws {
        let components = try XCTUnwrap(view.layer.backgroundColor?.components)
        XCTAssertEqual(components.count, 4)
        guard components.count == 4 else { return }
        let scalars = model.channelScalars
        XCTAssertNotEqual(scalars, .identity)
        XCTAssertEqual(Double(components[0]), scalars.red, accuracy: 0.000001)
        XCTAssertEqual(Double(components[1]), scalars.green, accuracy: 0.000001)
        XCTAssertEqual(Double(components[2]), scalars.blue, accuracy: 0.000001)
        XCTAssertEqual(components[3], 1)
        XCTAssertEqual(view.frame, window.bounds)
        XCTAssertGreaterThan(view.layer.zPosition, 0)
        XCTAssertLessThan(view.layer.zPosition, CGFloat(Float.greatestFiniteMagnitude))
        XCTAssertFalse(view.isHidden)
        XCTAssertFalse(view.isUserInteractionEnabled)
    }

    private func waitFor(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(predicate(), "The overlay did not reach the expected lifecycle state")
    }
}
#endif
