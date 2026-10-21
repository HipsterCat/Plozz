import SwiftUI
import Observation
import AppRuntime
import CoreModels
import FeatureHomeCore
import FeaturePlayback
@testable import AppShelliOS
@testable import CoreUI

struct TouchFeedbackFixture: View {
    @State private var position: TimeInterval = 30
    @State private var duration: TimeInterval = 300
    @State private var events = 0
    @State private var previews = 0
    @State private var commits = 0
    @State private var committedPosition: TimeInterval = -1
    @State private var gestureMinimum: TimeInterval = 0
    @State private var gestureMaximum: TimeInterval = 0
    @State private var isScrubbing = false

    private let segmented = ProcessInfo.processInfo.arguments.contains("--segmented-touch-feedback")
    private let segments: [MediaSegment] = [
        .init(kind: .intro, start: 75, end: 84.375),
        .init(kind: .recap, start: 120, end: 165),
        .init(kind: .commercial, start: 174.375, end: 225)
    ]

    var body: some View {
        VStack(spacing: 30) {
            PlayerTouchScrubBar(
                currentSeconds: position, duration: duration, bufferedFraction: 1,
                segments: segmented ? segments : [],
                onScrub: {
                    position = $0
                    previews += 1
                    gestureMinimum = min(gestureMinimum, $0)
                    gestureMaximum = max(gestureMaximum, $0)
                },
                onScrubbingChanged: {
                    isScrubbing = $0
                    if $0 {
                        gestureMinimum = .infinity
                        gestureMaximum = -.infinity
                    } else {
                        commits += 1
                        committedPosition = position
                    }
                },
                feedback: TouchFeedback(
                    output: { _ in events += 1 },
                    isActive: { true }
                )
            )
            .frame(maxWidth: segmented ? 240 : .infinity)
            .accessibilityLabel("Playback position")
            .accessibilityIdentifier("touch-scrubber")
            Text("Feedback \(events)").accessibilityIdentifier("feedback-count")
            Text("Previews \(previews)").accessibilityIdentifier("preview-count")
            Text("Commits \(commits)").accessibilityIdentifier("commit-count")
            if segmented {
                Text(verbatim: String(format: "%.3f", committedPosition)).accessibilityIdentifier("committed-position")
                Text(verbatim: String(format: "%.3f", gestureMinimum)).accessibilityIdentifier("gesture-minimum")
                Text(verbatim: String(format: "%.3f", gestureMaximum)).accessibilityIdentifier("gesture-maximum")
                Text(verbatim: isScrubbing ? "yes" : "no").accessibilityIdentifier("scrubbing-active")
            }
            Button("Playback tick") { position += 1 }
            Button("Unknown duration") { duration = 0 }
        }
        .padding(40)
        .background(segmented ? Color(red: 0.15, green: 0.35, blue: 0.6) : .clear)
        .preferredColorScheme(.dark)
    }
}

struct WatchlistFeedbackFixture: View {
    @State private var appModel: PlozziOSAppModel
    @State private var probe = WatchlistFeedbackProbe()
    @State private var revision = 0
    private let item = MediaItem(id: "haptic-fixture", title: "Watchlist feedback", kind: .movie)

    init() {
        SyncSetupFeatureFlag().isEnabled = false
        _appModel = State(initialValue: PlozziOSAppModel())
    }

    var body: some View {
        VStack(spacing: 24) {
            PlozziOSHomeHeroForeground(
                item: item, detailItem: item, watchlistItem: item,
                presentation: .init(item: item, artworkStyle: .compactPortrait, surface: .home),
                style: .compactPortrait, onPlay: { _ in }
            )
            .id(revision)
            Text("Taps \(probe.taps)").accessibilityIdentifier("watchlist-taps")
            Text("Confirmations \(probe.confirmations)").accessibilityIdentifier("watchlist-confirmations")
            Text("Errors \(probe.errors)").accessibilityIdentifier("watchlist-errors")
            Text("Saved \(probe.saved ? "yes" : "no")").accessibilityIdentifier("watchlist-saved")
            if probe.canFinish {
                Button("Complete save") { probe.complete(success: true) }
                Button("Fail save") { probe.complete(success: false) }
            }
        }
        .padding(40)
        .environment(appModel)
        .mediaItemActionHandler(probe.handler)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.plozzMetrics, .touch(density: .standard))
        .onReceive(NotificationCenter.default.publisher(for: .watchlistIntentDidChange)) { _ in revision += 1 }
    }
}

@MainActor
@Observable
private final class WatchlistFeedbackProbe {
    var taps = 0
    var confirmations = 0
    var errors = 0
    var canFinish = false
    var saved = false
    @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var pendingDelay: Task<Void, Error>?
    @ObservationIgnored private lazy var feedback = TouchFeedback(
        output: { [unowned self] event in
            if event == .impact { taps += 1 }
            if event == .confirmation { confirmations += 1 }
            if event == .error { errors += 1 }
        }, isActive: { true }
    )
    @ObservationIgnored lazy var handler = MediaItemActionCoordinator(
        providerResolver: { _ in nil },
        providerCapabilityResolver: { _ in nil },
        additionalSources: { _ in [] },
        primaryAccountID: { nil },
        crossServerWatchSyncEnabled: { false }, enqueueWatchMutation: { _ in },
        universalWatchlistEnabled: { true },
        watchlistMembership: { [unowned self] _ in saved },
        watchlistMembershipRevision: { 0 },
        performUniversalWatchlist: { [unowned self] adding, _ in
            await save(adding: adding)
        },
        presentUniversalWatchlistFeedback: { _, _ in },
        beginUniversalWatchlistFanOut: { _, _ in },
        resolveDurableWatchlist: { $0 },
        durableWatchlistPresentationReady: { true },
        durableWatchlistLoadingTarget: { nil },
        rehydratePersistedArtworkItems: { $0 },
        seedLegacyUniversalWatchlist: { _ in },
        downloadState: { _ in nil },
        performDownloadAction: { _, _ in },
        makeActionConfirmation: { [unowned self] in feedback.acknowledgeAction() },
        makeWatchlistFailureFeedback: { [unowned self] in feedback.acknowledgeAction(onCompletion: .error) }
    )

    private func save(adding: Bool) async -> Bool {
        pendingDelay = Task { @MainActor [weak self] in
            try await Task.sleep(for: .seconds(3.2))
            self?.canFinish = true
        }
        let succeeded = await withCheckedContinuation { continuation = $0 }
        if succeeded { saved = adding }
        return succeeded
    }

    func complete(success: Bool) {
        pendingDelay?.cancel()
        pendingDelay = nil
        canFinish = false
        continuation?.resume(returning: success)
        continuation = nil
    }
}
