import Observation
import SwiftUI
import UIKit
import XCTest
@testable import PlozzCoreUI

@MainActor
final class StartupLogoHostedTests: XCTestCase {
    func testEveryExpressionCompletesAfterTheEarlyFaceAndOnlyOnce() async throws {
        for expression in PlozzStartupExpression.allCases {
            try await verifyIntro(expression: expression)
        }
    }

    private func verifyIntro(expression: PlozzStartupExpression) async throws {
        try await withFixture(expression: expression) { host, probe in
            try await Task.sleep(for: .milliseconds(450))
            XCTAssertTrue(probe.completions.isEmpty)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Startup \(expression.rawValue) before release"
            attachment.lifetime = .keepAlways
            add(attachment)
            try await waitUntil { probe.completions.count == 1 }
            XCTAssertGreaterThanOrEqual(
                probe.mountedAt.duration(to: try XCTUnwrap(probe.completions.first)),
                .milliseconds(650)
            )
            probe.phase = .inactive
            try await Task.sleep(for: .milliseconds(50))
            probe.phase = .active
            try await Task.sleep(for: .seconds(1))
            XCTAssertEqual(probe.completions.count, 1)
        }
    }

    func testInactiveTimeDoesNotConsumeTheIntro() async throws {
        try await withFixture(phase: .inactive) { _, probe in
            try await Task.sleep(for: .milliseconds(800))
            XCTAssertTrue(probe.completions.isEmpty)
            let resumedAt = ContinuousClock.now
            probe.phase = .active
            try await waitUntil { probe.completions.count == 1 }
            XCTAssertGreaterThanOrEqual(
                resumedAt.duration(to: try XCTUnwrap(probe.completions.first)),
                .milliseconds(650)
            )
        }
    }

    func testInterruptedIntroRestartsItsVisibleInterval() async throws {
        try await withFixture { _, probe in
            try await Task.sleep(for: .milliseconds(250))
            probe.phase = .background
            try await Task.sleep(for: .milliseconds(800))
            XCTAssertTrue(probe.completions.isEmpty)
            let resumedAt = ContinuousClock.now
            probe.phase = .active
            try await waitUntil { probe.completions.count == 1 }
            XCTAssertGreaterThanOrEqual(
                resumedAt.duration(to: try XCTUnwrap(probe.completions.first)),
                .milliseconds(650)
            )
        }
    }

    func testReduceMotionSkipsTheAnimationHold() async throws {
        try await withFixture(reduceMotion: true) { _, probe in
            try await waitUntil { probe.completions.count == 1 }
            XCTAssertLessThan(
                probe.mountedAt.duration(to: try XCTUnwrap(probe.completions.first)),
                .milliseconds(650)
            )
        }
    }

    func testRemovingTheLogoDoesNotCompleteTheIntro() async throws {
        try await withFixture { _, probe in
            try await Task.sleep(for: .milliseconds(150))
            probe.showsLogo = false
            try await Task.sleep(for: .milliseconds(800))
            XCTAssertTrue(probe.completions.isEmpty)
        }
    }

    private func withFixture(
        phase: ScenePhase = .active,
        reduceMotion: Bool = false,
        expression: PlozzStartupExpression = .wink,
        exercise: (UIHostingController<StartupLogoFixture>, StartupLogoProbe) async throws -> Void
    ) async throws {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let probe = StartupLogoProbe(phase: phase, reduceMotion: reduceMotion, expression: expression)
        let host = UIHostingController(rootView: StartupLogoFixture(probe: probe))
        window.rootViewController = host
        probe.mountedAt = .now
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await waitUntil { probe.appeared && host.view.window != nil }
        try await exercise(host, probe)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(predicate(), "Startup logo did not reach the expected presentation state.")
    }
}

@MainActor @Observable
private final class StartupLogoProbe {
    var phase: ScenePhase
    let reduceMotion: Bool
    let expression: PlozzStartupExpression
    var showsLogo = true
    var appeared = false
    var mountedAt = ContinuousClock.now
    var completions: [ContinuousClock.Instant] = []

    init(phase: ScenePhase, reduceMotion: Bool, expression: PlozzStartupExpression) {
        self.phase = phase
        self.reduceMotion = reduceMotion
        self.expression = expression
    }
}

private struct StartupLogoFixture: View {
    let probe: StartupLogoProbe

    var body: some View {
        Group {
            if probe.showsLogo {
                PlozzStartupLogoContent(
                    reduceMotion: probe.reduceMotion, scenePhase: probe.phase, expression: probe.expression
                ) {
                    probe.completions.append(.now)
                }
                    .onAppear { probe.appeared = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
