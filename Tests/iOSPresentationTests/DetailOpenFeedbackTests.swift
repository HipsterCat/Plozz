#if os(iOS)
@testable import CoreUI
import Observation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class DetailOpenFeedbackTests: XCTestCase {
    func testFeedbackFollowsNewPagesNotLoadingPlaybackOrBackNavigation() async throws {
        continueAfterFailure = false
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let model = DetailFeedbackFixtureModel()
        let events = DetailFeedbackEvents()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: DetailFeedbackFixture(model: model, events: events))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }

        try await waitFor { events.libraryAppearances == 1 }
        XCTAssertTrue(events.feedback.isEmpty, "Building destinations must not emit feedback.")
        model.path = [1]
        try await waitFor { events.appearances[1] == 1 }
        XCTAssertEqual(events.feedback, [1: 1])

        model.loaded = true
        try await settle(window)
        model.revision += 1
        try await settle(window)
        XCTAssertEqual(events.feedback, [1: 1], "Loading and redraws are not new detail opens.")

        model.showPlayer = true
        try await waitFor { events.playerAppearances == 1 }
        model.showPlayer = false
        try await waitFor { events.playerDismissals == 1 }
        try await settle(window)
        XCTAssertEqual(events.feedback, [1: 1], "Returning from playback must not vibrate.")

        model.path = [1, 2]
        try await waitFor { events.appearances[2] == 1 }
        XCTAssertEqual(events.feedback, [1: 1, 2: 1])
        let appearancesBeforePop = events.appearances[1] ?? 0
        model.path = [1]
        try await waitFor { (events.appearances[1] ?? 0) > appearancesBeforePop }
        XCTAssertEqual(events.feedback, [1: 1, 2: 1], "Popping a nested detail must not vibrate.")

        let libraryAppearancesBeforePop = events.libraryAppearances
        model.path = []
        try await waitFor { events.libraryAppearances > libraryAppearancesBeforePop }
        model.path = [1]
        try await waitFor { events.feedback[1] == 2 }
        XCTAssertEqual(events.feedback, [1: 2, 2: 1], "Reopening a title is a new presentation.")
    }

    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
    }

    private func waitFor(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("The expected detail presentation lifecycle did not occur.", file: file, line: line)
    }
}

@MainActor
@Observable
private final class DetailFeedbackFixtureModel {
    var path: [Int] = []
    var loaded = false
    var revision = 0
    var showPlayer = false
}

@MainActor
private final class DetailFeedbackEvents {
    var feedback: [Int: Int] = [:]
    var appearances: [Int: Int] = [:]
    var playerAppearances = 0
    var playerDismissals = 0
    var libraryAppearances = 0
}

private struct DetailFeedbackFixture: View {
    @Bindable var model: DetailFeedbackFixtureModel
    let events: DetailFeedbackEvents

    var body: some View {
        NavigationStack(path: $model.path) {
            Text("Library")
                .onAppear { events.libraryAppearances += 1 }
                .navigationDestination(for: Int.self) { item in
                    DetailFeedbackFixturePage(item: item, model: model, events: events)
                }
        }
        .transaction { $0.disablesAnimations = true }
    }
}

private struct DetailFeedbackFixturePage: View {
    let item: Int
    @Bindable var model: DetailFeedbackFixtureModel
    let events: DetailFeedbackEvents

    var body: some View {
        Group {
            if model.loaded {
                Text("Detail \(item), revision \(model.revision)")
            } else {
                ProgressView("Loading")
            }
        }
        .modifier(DetailOpenFeedbackModifier {
            events.feedback[item, default: 0] += 1
        })
        .onAppear { events.appearances[item, default: 0] += 1 }
        .fullScreenCover(isPresented: $model.showPlayer, onDismiss: {
            events.playerDismissals += 1
        }) {
            Color.black.onAppear { events.playerAppearances += 1 }
        }
    }
}
#endif
