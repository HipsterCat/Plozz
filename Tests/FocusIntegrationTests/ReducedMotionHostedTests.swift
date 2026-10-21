import CoreUI
import Observation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class ReducedMotionHostedTests: XCTestCase {
    func testMotionPolicyPreservesLayoutAndIdentityAcrossExplicitAndImplicitAnimations() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let model = MotionTransactionFixture()
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: MotionTransactionView(model: model))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await waitUntil { model.marker != nil }
        let original = try XCTUnwrap(model.marker)
        let start = original.convert(original.bounds, to: window)
        for explicit in [false, true] {
            model.lastTransaction = nil
            let next = model.step + 1
            if explicit {
                withAnimation(.linear(duration: 1)) { model.step = next }
            } else {
                model.step = next
            }
            try await waitUntil { model.observedStep == next && model.lastTransaction != nil }
            let transaction = try XCTUnwrap(model.lastTransaction)
            XCTAssertTrue(model.marker === original, "Accessibility must not replace the content hierarchy.")
            if UIAccessibility.isReduceMotionEnabled {
                XCTAssertNil(transaction.animation)
                XCTAssertTrue(transaction.disablesAnimations)
            } else {
                XCTAssertNotNil(transaction.animation, "Normal-motion animations must remain enabled.")
            }
            try await Task.sleep(for: .milliseconds(1100))
            let frame = original.convert(original.bounds, to: window)
            XCTAssertEqual(frame.minY - start.minY, CGFloat(next) * 120, accuracy: 1,
                           "Suppress animation, never the final layout offset.")
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }
}

@MainActor @Observable
private final class MotionTransactionFixture {
    var step = 0
    @ObservationIgnored weak var marker: UIView?
    @ObservationIgnored var observedStep = -1
    @ObservationIgnored var lastTransaction: Transaction?
}

private struct MotionTransactionView: View {
    let model: MotionTransactionFixture

    var body: some View {
        MotionTransactionMarker(model: model, step: model.step)
            .frame(width: 200, height: 100)
            .offset(y: CGFloat(model.step) * 120)
            .animation(.linear(duration: 1), value: model.step)
            .modifier(ReducedMotion())
    }
}

private struct MotionTransactionMarker: UIViewRepresentable {
    let model: MotionTransactionFixture
    let step: Int

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .red
        model.marker = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        model.observedStep = step
        model.lastTransaction = context.transaction
    }
}
