import CoreModels
import CoreUI
import Observation
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import FeatureSettings

@MainActor
final class PlaybackSettingsHostedTests: XCTestCase {
    func testAdvancedPlaybackShowsFELControlAndAudioTradeoff() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let suite = "FELSettingsHosted-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let playback = PlaybackSettingsModel(store: PlaybackSettingsStore(defaults: defaults, namespace: "guest"))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        window.rootViewController = UIHostingController(rootView:
            PlaybackAdvancedSettingsView(
                playback: playback, model: ExternalPlayerSettingsModel(defaults: defaults)
            )
            .environment(\.settingsInWorkspace, true)
            .environment(\.themePalette, .dark)
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: SettingsFormMetrics.pageWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
        )
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
            defaults.removePersistentDomain(forName: suite)
        }
        try await Task.sleep(for: .milliseconds(400))
        let text = try visibleText(in: window, attachment: "FEL advanced playback setting")
        for label in ["FEL", "experimental", "GPU", "memory", "Dolby Atmos", "DTS:X"] {
            XCTAssertTrue(text.contains(label), "The setting and tradeoff must be visible: \(text)")
        }
        XCTAssertFalse(playback.settings.dolbyVisionFELEnabled)
    }

    func testLibrarySourcesShowConfiguredNamesAndUpdateWithProfileSelection() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let fixtures: [(String, String, ProviderKind)] = [
            ("plex", "Family Plex", .plex), ("jellyfin", "Cinema Server", .jellyfin),
            ("share", "Archive NAS", .mediaShare), ("silo", "Weekend Silo", .silo),
            ("emby", "Family Emby", .emby)
        ]
        let accounts = fixtures.map { id, name, provider in
            Account(
                id: id, server: MediaServer(
                    id: id, name: name,
                    baseURL: URL(string: "\(provider == .mediaShare ? "smb" : "https")://\(id).example/Media")!,
                    provider: provider
                ), userID: "viewer", userName: "Viewer", deviceID: "test"
            )
        }
        let selection = LibrarySourceSelection(includedIDs: Set(accounts.map(\.id)))
        var rootRenders = 0
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        window.rootViewController = UIHostingController(rootView:
            LibrarySummaryHost(accounts: accounts, selection: selection) {
                rootRenders += 1
            }
            .environment(SettingsNavigationModel())
            .environment(\.themePalette, .dark)
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: SettingsFormMetrics.pageWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
        )
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(400))
        let initialRenders = rootRenders
        XCTAssertGreaterThan(initialRenders, 0)
        for included: Set<String> in [Set(accounts.map(\.id)), ["silo", "emby"], []] {
            selection.includedIDs = included
            try await Task.sleep(for: .milliseconds(200))
            let text = try visibleText(in: window, attachment: "settings-library-sources-\(included.count)")
            XCTAssertTrue(text.contains("Libraries"), text)
            let visibleNames = Array(fixtures.filter { included.contains($0.0) }.prefix(3)).map(\.1)
            for (_, name, _) in fixtures {
                XCTAssertEqual(text.contains(name), visibleNames.contains(name), text)
            }
            XCTAssertEqual(text.replacingOccurrences(of: " ", with: "").contains("+2more"),
                           included.count == 5, text)
            XCTAssertEqual(text.contains("Choose what to watch"), included.isEmpty, text)
            XCTAssertEqual(rootRenders, initialRenders, "Source selection must update only the Libraries row.")
        }
    }

    func testSkipMarkerControlsAreInlineOnPlaybackPage() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let suite = "playback-settings-hosted-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let playback = PlaybackSettingsModel(store: PlaybackSettingsStore(defaults: defaults))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        window.rootViewController = UIHostingController(rootView:
            PlaybackDetailView(
                playback: playback,
                subtitleBehavior: SubtitleBehaviorModel(store: SubtitleBehaviorStore(defaults: defaults)),
                subtitleStyle: SubtitleStyleModel(store: SubtitleStyleStore(defaults: defaults)),
                subtitlePolicy: SubtitlePolicyModel(store: SubtitlePolicyStore(defaults: defaults)),
                audioPolicy: AudioPolicyModel(store: AudioPolicyStore(defaults: defaults))
            )
            .environment(\.settingsInWorkspace, true)
            .environment(\.themePalette, .dark)
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: SettingsFormMetrics.pageWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
        )
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
            defaults.removePersistentDomain(forName: suite)
        }
        try await Task.sleep(for: .milliseconds(400))
        window.layoutIfNeeded()
        let scroll = try XCTUnwrap(scrollView(in: window))
        for separate in [false, true] {
            if separate {
                playback.settings.skipModeOverrides = Dictionary(
                    uniqueKeysWithValues: MediaSegment.Kind.skippable.map { ($0, .on) }
                )
                try await Task.sleep(for: .milliseconds(400))
            }
            let top = -scroll.adjustedContentInset.top
            let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            var visible = ""
            for offset in stride(from: top, through: bottom + 540, by: 540) {
                scroll.setContentOffset(CGPoint(x: 0, y: min(offset, bottom)), animated: false)
                try await Task.sleep(for: .milliseconds(100))
                window.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US"]
                try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
                let page = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                visible += " " + page
                if page.contains("Skip intros") || page.contains("Use community markers") || page.contains("Version selection") {
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Playback-inline-skip-separate-\(separate)-\(Int(offset))"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                if offset >= bottom { break }
            }
            for label in [
                "Version selection", "Choose on first play", "Ask every time", "Choose automatically",
                "Remember series version choices",
                "Skip intros, credits", "Set each marker separately", "Use community markers",
                "Video buffer", "1 minute", "5 minutes", "10 minutes", "Maximum available"
            ] {
                XCTAssertTrue(visible.contains(label), "Missing inline control \(label): \(visible)")
            }
            if separate {
                for label in ["Intros", "Credits", "Recaps", "Previews", "Commercials"] {
                    XCTAssertTrue(visible.contains(label), "Missing inline per-kind control \(label)")
                }
            }
        }
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
    }

    private func visibleText(in window: UIWindow, attachment name: String) throws -> String {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
}

private struct LibrarySummaryHost: View {
    let accounts: [Account]
    let selection: LibrarySourceSelection
    let onRender: () -> Void

    var body: some View {
        let _ = onRender()
        SettingsLibrariesRow(
            accounts: accounts,
            isAccountIncluded: { selection.includedIDs.contains($0) }
        )
    }
}

@MainActor @Observable
private final class LibrarySourceSelection {
    var includedIDs: Set<String>

    init(includedIDs: Set<String>) {
        self.includedIDs = includedIDs
    }
}
