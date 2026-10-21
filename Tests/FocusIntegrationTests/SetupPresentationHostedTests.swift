import CoreUI
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import AppShell

@MainActor
final class SetupPresentationHostedTests: XCTestCase {
    func testSetupStaysMountedUntilUserDismissesAndQueuedStartupThenOpens() async throws {
        try await withFixture { host, probe in
            probe.requests = [.sendSetup]
            try await waitUntil { probe.appearances[.sendSetup] == 1 }
            let setup = try XCTUnwrap(host.presentedViewController)
            try await waitUntil { !setup.isBeingPresented && setup.transitionCoordinator == nil }
            let others: [RootPresentationCoordinator.Destination] = [
                .releaseNotes, .introduction, .accessGate, .newServer, .profileAppearance
            ]
            for other in others {
                probe.requests = [other, .sendSetup]
                try await Task.sleep(for: .milliseconds(100))
                XCTAssertTrue(host.presentedViewController === setup)
                XCTAssertEqual(probe.appearances[.sendSetup], 1)
                XCTAssertNil(probe.appearances[other])
                XCTAssertEqual(probe.dismissals, 0)
            }
            probe.requests = [.releaseNotes, .sendSetup]
            probe.coordinator.dismiss()
            try await waitUntil { probe.dismissals == 1 && probe.appearances[.releaseNotes] == 1 }
            XCTAssertFalse(host.presentedViewController === setup)
        }
    }

    func testSetupRequestedDuringStartupOpensAfterItsNativeDismissal() async throws {
        try await withFixture { host, probe in
            probe.requests = [.releaseNotes]
            try await waitUntil { probe.appearances[.releaseNotes] == 1 }
            let startup = try XCTUnwrap(host.presentedViewController)
            try await waitUntil { !startup.isBeingPresented && startup.transitionCoordinator == nil }
            probe.requests = [.releaseNotes, .sendSetup]
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertNil(probe.appearances[.sendSetup])
            probe.coordinator.dismiss()
            try await waitUntil { probe.dismissals == 1 && probe.appearances[.sendSetup] == 1 }
            XCTAssertEqual(probe.coordinator.active, .sendSetup)
            XCTAssertTrue(probe.coordinator.isPresented)
        }
    }

    private func withFixture(
        exercise: (UIHostingController<SetupPresentationFixture>, SetupPresentationProbe) async throws -> Void
    ) async throws {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let probe = SetupPresentationProbe()
        let host = UIHostingController(rootView: SetupPresentationFixture(probe: probe))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await waitUntil { host.view.window != nil }
        try await exercise(host, probe)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(predicate(), "Native presentation did not complete.")
    }
}

@MainActor @Observable
private final class SetupPresentationProbe {
    let coordinator = RootPresentationCoordinator()
    var requests: [RootPresentationCoordinator.Destination] = []
    var appearances: [RootPresentationCoordinator.Destination: Int] = [:]
    var dismissals = 0
}

private struct SetupPresentationFixture: View {
    let probe: SetupPresentationProbe

    var body: some View {
        ZStack { Text("App") }
            .onChange(of: probe.requests, initial: true) { _, requests in
                probe.coordinator.update(requests)
            }
            .plozzFullScreenCover(
                isPresented: Binding(
                    get: { probe.coordinator.isPresented },
                    set: { if !$0 { probe.coordinator.dismiss() } }
                ),
                onDismiss: {
                    if let active = probe.coordinator.active {
                        probe.requests.removeAll { $0 == active }
                    }
                    probe.dismissals += 1
                    probe.coordinator.didDismiss()
                    probe.coordinator.update(probe.requests)
                }
            ) {
                if let active = probe.coordinator.active {
                    Button("Done") { probe.coordinator.dismiss() }
                        .onAppear { probe.appearances[active, default: 0] += 1 }
                }
            }
    }
}
