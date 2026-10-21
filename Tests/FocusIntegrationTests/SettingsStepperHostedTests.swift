@testable import CoreUI
import Observation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SettingsStepperHostedTests: XCTestCase {
    func testDirectionalAdjustmentClampsAndKeepsNativeFocusAndWidth() async throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            try await withStepper(direction: direction) { model, input, window in
                let system = try XCTUnwrap(UIFocusSystem(for: window))
                let focused = try XCTUnwrap(system.focusedItem)
                let initialFrame = focused.frame
                XCTAssertGreaterThan(initialFrame.width, 800, "The native target must span the whole labeled row.")
                self.press(.right, input)
                try await self.waitUntil { model.selection == 120 }
                self.press(.right, input)
                XCTAssertEqual(model.selection, 120)
                self.press(.left, input)
                try await self.waitUntil { model.selection == 15 }
                self.press(.left, input)
                try await self.waitUntil { model.selection == 5 }
                self.press(.left, input)
                XCTAssertEqual(model.selection, 5)
                XCTAssertTrue(system.focusedItem === focused)
                XCTAssertEqual(system.focusedItem?.frame, initialFrame)
                XCTAssertTrue(model.focused)
                model.focusOther = true
                try await self.waitUntil { system.focusedItem !== focused && !model.focused }
                XCTAssertFalse(input.ownsHorizontalNavigationInput)
                self.press(.right, input)
                XCTAssertEqual(model.selection, 5, "An unfocused control cannot change settings.")
            }
        }
    }

    func testCyclicOptionsWrapWithoutChangingTheNativeFocusTarget() async throws {
        try await withStepper(wraps: true) { model, input, window in
            let focused = UIFocusSystem(for: window)?.focusedItem
            self.press(.right, input)
            try await self.waitUntil { model.selection == 120 }
            self.press(.right, input)
            try await self.waitUntil { model.selection == 5 }
            self.press(.left, input)
            try await self.waitUntil { model.selection == 120 }
            XCTAssertTrue(UIFocusSystem(for: window)?.focusedItem === focused)
        }
    }

    func testChangingTheOptionSetCancelsAnOwnedHeldPress() async throws {
        try await withStepper { model, input, _ in
            input.beginPress(.right)
            XCTAssertEqual(model.selection, 120)
            model.options = [120, 240]
            try await Task.sleep(for: .milliseconds(650))
            XCTAssertEqual(model.selection, 120, "A held press must not cross a changed option set.")
            self.press(.right, input)
            try await self.waitUntil { model.selection == 240 }
        }
    }

    private func press(_ direction: SettingsMoveCommandDirection, _ input: any SettingsAdjustmentRemoteInput) {
        input.beginPress(direction)
        input.stopRepeating()
    }

    private func withStepper(
        wraps: Bool = false,
        direction: LayoutDirection = .leftToRight,
        body: (Model, any SettingsAdjustmentRemoteInput, UIWindow) async throws -> Void
    ) async throws {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let model = Model()
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: Fixture(model: model, wraps: wraps)
            .environment(\.layoutDirection, direction))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await waitUntil { self.inputController(in: host) != nil }
        let input = try XCTUnwrap(inputController(in: host))
        let system = try XCTUnwrap(UIFocusSystem(for: window))
        system.requestFocusUpdate(to: input)
        system.updateFocusIfNeeded()
        try await waitUntil { input.ownsHorizontalNavigationInput && model.focused }
        defer { input.stopRepeating() }
        try await body(model, input, window)
    }

    private func inputController(in root: UIViewController) -> (any SettingsAdjustmentRemoteInput)? {
        if let input = root as? any SettingsAdjustmentRemoteInput { return input }
        return root.children.lazy.compactMap { self.inputController(in: $0) }.first
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition())
    }

    @Observable final class Model {
        var options = [5, 15, 120]
        var selection = 15
        var focused = false
        var focusOther = false
    }

    private struct Fixture: View {
        @Bindable var model: Model
        let wraps: Bool
        @FocusState private var otherFocused: Bool

        var body: some View {
            VStack(spacing: 50) {
                SettingsStepper(
                    options: model.options, selection: $model.selection, wraps: wraps,
                    onFocusChange: { model.focused = $0 }, label: "Seconds",
                    subtitle: "Adjustment helper",
                    verbatimTitle: { "\($0) sec" }
                )
                Button("Next setting") {}.focused($otherFocused)
            }
            .frame(width: 900)
            .onChange(of: model.focusOther) { _, value in otherFocused = value }
        }
    }
}
