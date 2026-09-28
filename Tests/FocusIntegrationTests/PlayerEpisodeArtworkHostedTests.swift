import CoreModels
import Observation
@testable import CoreUI
@testable import FeaturePlayback
import SwiftUI
import TVUIKit
import UIKit
import XCTest

@MainActor
final class PlayerEpisodeArtworkHostedTests: XCTestCase {
    func testPrependingEpisodesPreservesNativeFocusAndExactViewport() async throws {
        try await assertStablePrepend(direction: .leftToRight)
        try await assertStablePrepend(direction: .rightToLeft)
    }

    private func assertStablePrepend(direction: LayoutDirection) async throws {
        let provider = EpisodeRowProvider()
        await provider.hold("season-1")
        defer { Task { await provider.release("season-1") } }
        let playing = EpisodeRowProvider.episode(season: 2, number: 2)
        let player = PlayerViewModel(provider: provider, itemID: playing.id, episodeItem: playing)
        let browser = try XCTUnwrap(player.episodeBrowser)
        await browser.loadIfNeeded()
        let requests = await provider.requests
        XCTAssertEqual(requests, ["series", "season-2"])
        XCTAssertNil(browser.loadError)
        XCTAssertEqual(browser.episodes.map(\.item.id), (1...8).map { "2-\($0)" })
        try await withProductionPanel(player, direction: direction) { model, window in
            try await self.waitUntil {
                !self.nativePosters(in: window).isEmpty && model.observedFocus == .button(.episodes)
            }
            let entry = try XCTUnwrap(browser.initialEntryID)
            model.target = entry
            try await self.waitUntil {
                (UIFocusSystem.focusSystem(for: window)?.focusedItem as? TVPosterView)?
                    .accessibilityLabel == playing.title
            }
            try await self.waitUntil { await provider.isHolding("season-1") }
            for number in [3, 2] {
                let target = try XCTUnwrap(browser.episodes.first { $0.item.id == "2-\(number)" })
                model.target = target.id
                try await self.waitUntil {
                    (UIFocusSystem.focusSystem(for: window)?.focusedItem as? TVPosterView)?
                        .accessibilityLabel == target.item.title
                }
            }
            try await Task.sleep(for: .milliseconds(300))
            let poster = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem as? TVPosterView)
            let scroll = try XCTUnwrap(self.scrollView(in: window))
            try await self.waitUntil { !scroll.isDecelerating && !scroll.isDragging }
            // Preserve even a viewport parked between card slots.
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x + 47, y: 0), animated: false)
            try await Task.sleep(for: .milliseconds(100))
            let frame = poster.convert(poster.bounds, to: window)
            let width = scroll.contentSize.width
            await provider.release("season-1")
            try await self.waitUntil { browser.episodes.count == 16 && scroll.contentSize.width > width + 1000 }
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(20))
                XCTAssertTrue(UIFocusSystem.focusSystem(for: window)?.focusedItem === poster)
                XCTAssertEqual(model.observedFocus, .episodeItem(entry))
                XCTAssertEqual(poster.convert(poster.bounds, to: window).minX, frame.minX, accuracy: 1,
                               "Prepending must preserve the offset within the card, not realign it.")
            }
        }
    }

    func testPrependFinishingDuringNativeScrollNeverMovesFocusToAnotherEpisode() async throws {
        let provider = EpisodeRowProvider()
        await provider.hold("season-1")
        defer { Task { await provider.release("season-1") } }
        let playing = EpisodeRowProvider.episode(season: 2, number: 2)
        let player = PlayerViewModel(provider: provider, itemID: playing.id, episodeItem: playing)
        let browser = try XCTUnwrap(player.episodeBrowser)
        await browser.loadIfNeeded()
        try await withProductionPanel(player) { model, window in
            try await self.waitUntil {
                !self.nativePosters(in: window).isEmpty && model.observedFocus == .button(.episodes)
            }
            for number in [2, 3, 2] {
                let entry = try XCTUnwrap(browser.episodes.first { $0.item.id == "2-\(number)" })
                model.target = entry.id
                try await self.waitUntil {
                    (UIFocusSystem.focusSystem(for: window)?.focusedItem as? TVPosterView)?
                        .accessibilityLabel == entry.item.title
                }
            }
            try await self.waitUntil { await provider.isHolding("season-1") }
            let poster = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem as? TVPosterView)
            let scroll = try XCTUnwrap(self.scrollView(in: window))
            let width = scroll.contentSize.width
            XCTAssertTrue(scroll.isDecelerating, "Complete the request during native directional scrolling.")
            await provider.release("season-1")
            var priorX = poster.convert(poster.bounds, to: window).minX
            for _ in 0..<75 {
                try await Task.sleep(for: .milliseconds(20))
                XCTAssertTrue(UIFocusSystem.focusSystem(for: window)?.focusedItem === poster)
                let x = poster.convert(poster.bounds, to: window).minX
                XCTAssertLessThan(abs(x - priorX), 80, "Loading must not snap the viewport.")
                priorX = x
            }
            XCTAssertEqual(browser.episodes.count, 16)
            XCTAssertGreaterThan(scroll.contentSize.width, width + 1000, "Apply the loaded season after scrolling settles.")
        }
    }

    func testAppendingEpisodesPreservesFocusAfterMovingLeftDuringLoading() async throws {
        let provider = EpisodeRowProvider()
        await provider.hold("season-3")
        defer { Task { await provider.release("season-3") } }
        let playing = EpisodeRowProvider.episode(season: 2, number: 7)
        let player = PlayerViewModel(provider: provider, itemID: playing.id, episodeItem: playing)
        let browser = try XCTUnwrap(player.episodeBrowser)
        await browser.loadIfNeeded()
        try await withProductionPanel(player) { model, window in
            try await self.waitUntil {
                !self.nativePosters(in: window).isEmpty && model.observedFocus == .button(.episodes)
            }
            for number in [8, 7] {
                let target = try XCTUnwrap(browser.episodes.first { $0.item.id == "2-\(number)" })
                model.target = target.id
                try await self.waitUntil {
                    (UIFocusSystem.focusSystem(for: window)?.focusedItem as? TVPosterView)?
                        .accessibilityLabel == target.item.title
                }
            }
            try await self.waitUntil { await provider.isHolding("season-3") }
            let scroll = try XCTUnwrap(self.scrollView(in: window))
            try await self.waitUntil { !scroll.isDecelerating && !scroll.isDragging }
            try await Task.sleep(for: .milliseconds(100))
            let poster = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem as? TVPosterView)
            let frame = poster.convert(poster.bounds, to: window)
            let count = browser.episodes.count
            await provider.release("season-3")
            try await self.waitUntil { browser.episodes.count == count + 8 }
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(20))
                XCTAssertTrue(UIFocusSystem.focusSystem(for: window)?.focusedItem === poster)
                XCTAssertEqual(poster.convert(poster.bounds, to: window).minX, frame.minX, accuracy: 1)
            }
        }
    }

    func testInitialLoadingUsesNonfocusableSkeletonsAndDoesNotStealBrowseFocus() async throws {
        let provider = EpisodeRowProvider()
        await provider.hold("series")
        defer { Task { await provider.release("series") } }
        let playing = EpisodeRowProvider.episode(season: 2, number: 2)
        let player = PlayerViewModel(provider: provider, itemID: playing.id, episodeItem: playing)
        let browser = try XCTUnwrap(player.episodeBrowser)
        try await withProductionPanel(player) { model, window in
            try await self.waitUntil { await provider.isHolding("series") }
            try await self.waitUntil { model.observedFocus == .button(.episodes) }
            XCTAssertFalse(browser.hasLoaded)
            XCTAssertTrue(self.nativePosters(in: window).isEmpty)
            XCTAssertTrue(self.views(in: window, of: UIActivityIndicatorView.self).isEmpty)
            let before = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem)
            let loadingScroll = try XCTUnwrap(self.scrollView(in: window))
            let scrollFrame = loadingScroll.convert(loadingScroll.bounds, to: window)
            let attachment = XCTAttachment(image: DetailTransitionSnapshot.image(of: window))
            attachment.name = "Episode loading skeleton"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            await provider.release("series")
            try await self.waitUntil { browser.hasLoaded && !self.nativePosters(in: window).isEmpty }
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertTrue(UIFocusSystem.focusSystem(for: window)?.focusedItem === before)
            XCTAssertEqual(model.observedFocus, .button(.episodes))
            let loadedScroll = try XCTUnwrap(self.scrollView(in: window))
            XCTAssertEqual(loadedScroll.convert(loadedScroll.bounds, to: window).height, scrollFrame.height, accuracy: 1)
        }
    }

    func testOnlyCurrentArtworkKeepsNativeFocusAndOverflowStaysInsidePanel() async throws {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let model = EpisodeArtworkFixtureModel()
        let entries = (1...6).map { (number: Int) in
            PlayerEpisodeEntry(
                item: MediaItem(
                    id: "episode-\(number)", title: "Episode \(number)",
                    kind: .episode, episodeNumber: number
                ),
                seasonID: "season", seasonNumber: 2
            )
        }
        let host = UIHostingController(rootView: EpisodeArtworkFixture(
            model: model, entries: entries
        ))
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }

        try await waitUntil { self.nativePosters(in: window).count == entries.count }
        for index in [0, 1, 2, 3, 2] {
            model.target = entries[index].id
            try await waitUntil {
                (UIFocusSystem.focusSystem(for: window)?.focusedItem as? TVPosterView)?
                    .accessibilityLabel == entries[index].item.title
            }
            try await Task.sleep(for: .milliseconds(250))
            let posters = nativePosters(in: window)
            XCTAssertEqual(posters.filter(\.isFocused).count, 1)
            XCTAssertEqual(model.observedFocus, .episodeItem(entries[index].id))
            XCTAssertTrue(posters.filter { $0.accessibilityLabel != entries[index].item.title }
                .allSatisfy { !$0.isFocused })
            XCTAssertTrue(posters.allSatisfy { $0.footerView == nil },
                          "Titles must remain outside the native artwork projection.")
        }

        let screenshot = DetailTransitionSnapshot.image(of: window)
        let image = try XCTUnwrap(screenshot.cgImage)
        let scale = CGFloat(image.width) / window.bounds.width
        for x: CGFloat in [448, 1468] {
            let strip = try XCTUnwrap(image.cropping(to: CGRect(
                x: x * scale, y: 440 * scale, width: 4 * scale, height: 180 * scale
            )))
            var pixels = [UInt8](repeating: 0, count: strip.width * strip.height * 4)
            let context = try XCTUnwrap(CGContext(
                data: &pixels, width: strip.width, height: strip.height,
                bitsPerComponent: 8, bytesPerRow: strip.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(strip, in: CGRect(x: 0, y: 0, width: strip.width, height: strip.height))
            let brightPixels = stride(from: 0, to: pixels.count, by: 4).filter {
                max(pixels[$0], pixels[$0 + 1], pixels[$0 + 2]) > 30
            }
            XCTAssertTrue(brightPixels.isEmpty,
                          "Artwork and native focus projection must not bleed past the panel.")
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "Episode row native focus and clipped edges"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func nativePosters(in view: UIView) -> [TVPosterView] {
        (view as? TVPosterView).map { [$0] } ?? view.subviews.flatMap { nativePosters(in: $0) }
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
    }

    private func views<T: UIView>(in view: UIView, of type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { views(in: $0, of: type) }
    }

    private func withProductionPanel(
        _ player: PlayerViewModel,
        direction: LayoutDirection = .leftToRight,
        body: (EpisodeArtworkFixtureModel, UIWindow) async throws -> Void
    ) async throws {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let model = EpisodeArtworkFixtureModel()
        window.rootViewController = UIHostingController(rootView: ProductionEpisodeFixture(
            player: player, model: model
        ).environment(\.layoutDirection, direction))
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await body(model, window)
    }

    private func waitUntil(
        file: StaticString = #filePath, line: UInt = #line,
        _ condition: () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for the episode row.", file: file, line: line)
        throw EpisodeArtworkFixtureError.focusTimeout
    }
}

private enum EpisodeArtworkFixtureError: Error { case focusTimeout }

@MainActor @Observable
private final class EpisodeArtworkFixtureModel {
    var target: PlayerEpisodeEntry.ID?
    var observedFocus: PlayerControls.FocusSlot?
}

private struct EpisodeArtworkFixture: View {
    let model: EpisodeArtworkFixtureModel
    let entries: [PlayerEpisodeEntry]
    @FocusState private var focus: PlayerControls.FocusSlot?
    private let layout = PlayerSequenceLayout(
        metrics: .tv, cardMetrics: .standard, contained: true, hasError: false
    )

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: layout.columnSpacing) {
                        ForEach(entries) { entry in
                            PlayerEpisodeArtworkCard(entry: entry, layout: layout, focus: $focus) {}
                                .id(entry.id)
                        }
                    }
                }
                .scrollClipDisabled()
                .modifier(PlayerEpisodePanelSurface(layout: layout))
                .frame(width: 1000)
                .onChange(of: model.target) { _, id in
                    if let id {
                        proxy.scrollTo(id, anchor: .center)
                        focus = .episodeItem(id)
                    }
                }
            }
        }
        .environment(\.plozzCardFocusStyle, .system)
        .onChange(of: focus) { _, value in model.observedFocus = value }
    }
}

private struct ProductionEpisodeFixture: View {
    let player: PlayerViewModel
    let model: EpisodeArtworkFixtureModel
    @FocusState private var focus: PlayerControls.FocusSlot?

    var body: some View {
        VStack {
            Button("Browse") {}
                .focused($focus, equals: .button(.episodes))
            PlayerSequencePanel(player: player, source: .episodes, focus: $focus)
                .frame(width: 1000)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .environment(\.plozzCardFocusStyle, .system)
        .onAppear { focus = .button(.episodes) }
        .onChange(of: model.target) { _, id in
            if let id { focus = .episodeItem(id) }
        }
        .onChange(of: focus) { _, value in model.observedFocus = value }
    }
}

private actor EpisodeRowProvider: MediaProvider {
    nonisolated let kind = ProviderKind.jellyfin
    nonisolated let session = UserSession(
        server: MediaServer(id: "fixture", name: "Fixture", baseURL: URL(string: "https://fixture.test")!, provider: .jellyfin),
        userID: "viewer", userName: "Viewer", deviceID: "fixture", accessToken: "fixture"
    )
    private var heldIDs: Set<String> = []
    private var pending: [String: CheckedContinuation<Void, Never>] = [:]
    private(set) var requests: [String] = []

    nonisolated static func episode(season: Int, number: Int) -> MediaItem {
        MediaItem(
            id: "\(season)-\(number)", title: "Season \(season) Episode \(number)", kind: .episode,
            seasonNumber: season, episodeNumber: number, seriesID: "series", seasonID: "season-\(season)"
        )
    }

    func hold(_ id: String) { heldIDs.insert(id) }
    func isHolding(_ id: String) -> Bool { pending[id] != nil }
    func release(_ id: String) {
        heldIDs.remove(id)
        pending.removeValue(forKey: id)?.resume()
    }
    func children(of itemID: String) async throws -> [MediaItem] {
        requests.append(itemID)
        if heldIDs.contains(itemID) {
            await withCheckedContinuation { pending[itemID] = $0 }
        }
        if itemID == "series" {
            return (1...3).map { (number: Int) in
                MediaItem(id: "season-\(number)", title: "Season", kind: .season, seasonNumber: number)
            }
        }
        guard let season = Int(itemID.replacingOccurrences(of: "season-", with: "")) else {
            throw AppError.notFound
        }
        return (1...8).map { Self.episode(season: season, number: $0) }
    }
    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: page.startIndex, totalCount: 0)
    }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    nonisolated func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
