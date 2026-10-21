#if os(iOS)
import CoreModels
@testable import CoreUI
import Observation
import FeatureHomeCore
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import AppShelliOS

@MainActor
final class SeasonRequestLayoutTests: XCTestCase {
    func testAdaptiveHeroRetainsPresentedVersionMenuWhileMetadataChanges() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let fixture = UpdatingDetailHero()
        let host = UIHostingController(rootView: UpdatingDetailHeroView(fixture: fixture))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            fixture.menu.isPresented = false
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        fixture.menu.open(from: CGRect(x: 300, y: 180, width: 48, height: 48))
        let presentationDeadline = ContinuousClock.now + .seconds(5)
        while host.presentedViewController?.view.window == nil, ContinuousClock.now < presentationDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let presented = try XCTUnwrap(host.presentedViewController)
        fixture.menu.page = .versions
        try await Task.sleep(for: .milliseconds(300))

        // Trailer arrival and narrowing force different ViewThatFits candidates.
        for width in [350.0, 280.0, 390.0] {
            fixture.hasTrailer.toggle()
            fixture.width = width
            fixture.versions.append(.init(id: "copy-\(width)", name: "Another copy", height: 1080))
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertTrue(fixture.menu.isPresented)
            XCTAssertEqual(fixture.menu.page, .versions, "Relayout must not reset the drill-in page.")
            XCTAssertTrue(host.presentedViewController === presented, "Keep the original native presentation alive.")
            XCTAssertFalse(presented.isBeingDismissed)
            XCTAssertNotNil(presented.view.window)
        }
        let image = UIGraphicsImageRenderer(bounds: presented.view.bounds).image { _ in
            XCTAssertTrue(presented.view.drawHierarchy(in: presented.view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "versions-survive-hero-enrichment"
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Version"), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Another copy"), "Live inventory must still update: \(text)")
        fixture.menu.isPresented = false
        let dismissalDeadline = ContinuousClock.now + .seconds(5)
        while host.presentedViewController != nil, ContinuousClock.now < dismissalDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(host.presentedViewController, "Deliberate dismissal must still work.")
    }

    private let item = MediaItem(id: "unreleased-series", title: "Phony", kind: .series)
    private var availability: MediaRequestAvailability {
        .init(status: .processing, seasons: [
            .init(number: 1, title: "Season 1", status: .processing,
                  premiereDate: MediaItem.calendarDayReleaseDate(from: "2099-10-20"))
        ])
    }

    private var request: PlozziOSHeroRequest {
        .init(
            cta: .requested, isRequesting: false, actingName: nil, onRequest: { _ in },
            seasonAvailability: availability,
            onOpenSeasonRequests: {}
        )
    }

    func testActualDetailHeroUsesOverflowBeforeStackingAndKeepsButtonsTheSameHeight() throws {
        let app = PlozziOSAppModel()
        let button = PlozziOSHeroRequestButton(item: item, request: request)
            .environment(\.dynamicTypeSize, .large)
        let primary = size(button, width: 2_000)
        let singleLine = size(Button("Play", action: {})
            .buttonStyle(PlozziOSHeroActionButtonStyle(kind: .primary)), width: 2_000)
        XCTAssertEqual(primary.height, singleLine.height, accuracy: 0.5,
                       "The complete request status must remain a native single-line button, not a subtitle card.")
        XCTAssertLessThan(primary.width, 500, "Request buttons must report their readable width, not fill the proposal.")
        let overflowSpacingAndWidth: CGFloat = 12 + 48
        for width in [primary.width + overflowSpacingAndWidth - 2,
                      primary.width + overflowSpacingAndWidth + 2, 500, 720] {
            let baseline = foreground(app: app, extras: false)
            let actual = foreground(app: app, extras: true)
            let baselineSize = size(baseline, width: width)
            let actualSize = size(actual, width: width)
            XCTAssertLessThanOrEqual(actualSize.width, width + 0.5)
            if width >= primary.width + overflowSpacingAndWidth {
                XCTAssertEqual(actualSize.height, baselineSize.height, accuracy: 1,
                               "Secondary actions must enter the real overflow menu before the row grows taller.")
            } else {
                XCTAssertEqual(actualSize.height, baselineSize.height + overflowSpacingAndWidth, accuracy: 1,
                               "The secondary icons must share one row below the primary request.")
            }
            let image = try capture(actual, width: width, name: "actual-detail-overflow-\(Int(width))pt")
            if width < primary.width + overflowSpacingAndWidth {
                try assertBottomIconCount(2, in: image)
            }
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([recognition])
            let lines = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            XCTAssertTrue(lines.contains { $0.contains("Requested") && $0.contains("Unreleased") },
                          "Both facts must appear together on one line: \(lines)")
            if width < 500 {
                XCTAssertFalse(lines.contains { $0 == "Trailer" },
                               "Trailer must use its icon or overflow rather than forcing a taller request button.")
            }
        }
    }

    func testStackedIconsRetainSeparateSourceSelectionWithoutHidingActions() throws {
        let app = PlozziOSAppModel()
        let view = foreground(app: app, extras: true, sources: [
            .init(accountID: "jellyfin", itemID: "show-jellyfin", kind: .series, providerKind: .jellyfin),
            .init(accountID: "plex", itemID: "show-plex", kind: .series, providerKind: .plex)
        ])
        let image = try capture(view, width: 276, name: "stacked-icons-with-source-menu")
        try assertBottomIconCount(3, in: image)
        let narrowWidth: CGFloat = 156
        let baseline = size(foreground(app: app, extras: false), width: narrowWidth)
        XCTAssertEqual(size(view, width: narrowWidth).height, baseline.height + 120, accuracy: 1,
                       "All three controls must wrap into two icon rows rather than disappearing into overflow.")
        _ = try capture(view, width: narrowWidth, name: "stacked-icons-wrapping-with-source-menu")
    }

    func testActualDetailHeroPreservesTheCompleteStatusAtPhoneTabletAndLargeTextSizes() throws {
        let app = PlozziOSAppModel()
        for width in [CGFloat(276), 331, 386, 720] {
            for typeSize in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
                let view = foreground(app: app, extras: true, typeSize: typeSize)
                XCTAssertLessThanOrEqual(size(view, width: width).width, width + 0.5)
                _ = try capture(view, width: width, name: "actual-detail-\(Int(width))pt-\(typeSize)")
            }
        }
    }

    func testCircularHeroIconsStayInsetAtAccessibilityTextSizes() throws {
        for typeSize in [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5] {
            for symbol in ["film.fill", "bookmark", "ellipsis"] {
                let button = Button {} label: {
                    Image(systemName: symbol).font(.headline.weight(.bold))
                }
                .buttonStyle(TouchHeroActionButtonStyle(kind: .secondary, circular: true))
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.themePalette, ThemePalette.dark)
                .environment(\.colorScheme, .dark)
                XCTAssertEqual(size(button, width: 48), CGSize(width: 48, height: 48))
                let image = try capture(button, width: 48, name: "circular-\(symbol)-\(typeSize)")
                let glyph = try brightPixelBounds(image)
                let inset: CGFloat = 16 + 8
                XCTAssertGreaterThanOrEqual(glyph.minX, inset)
                XCTAssertGreaterThanOrEqual(glyph.minY, inset)
                XCTAssertLessThanOrEqual(glyph.maxX, 16 + 48 - 8)
                XCTAssertLessThanOrEqual(glyph.maxY, 16 + 48 - 8)
            }
        }
    }

    private func foreground(
        app: PlozziOSAppModel, extras: Bool, typeSize: DynamicTypeSize = .large,
        sources: [MediaSourceRef] = [], noStreams: Bool = false,
        isRetrying: Bool = false, colorScheme: ColorScheme = .dark
    ) -> some View {
        let presentation = HeroPresentation(item: item, artworkStyle: .compactPortrait, surface: .detail)
        return PlozziOSDetailHeroForeground(
            item: item, rootItem: item, playableItem: nil,
            onRetryPlaybackInventory: noStreams ? {} : nil,
            isRetryingPlaybackInventory: isRetrying,
            sources: sources, selectedSourceAccountID: sources.first?.accountID,
            versions: [], selectedVersionID: nil,
            onSelectSource: { _ in }, onSelectVersion: { _ in },
            presentation: presentation, fallbackPresentation: presentation,
            style: .compactPortrait,
            actionHandler: RequestLayoutActions(showsWatchlist: extras, includesWatched: noStreams && extras),
            onPlay: { _, _ in }, trailerItem: extras ? item : nil,
            onPlayTrailer: extras ? { _ in } : nil, heroRequest: noStreams ? nil : request
        )
        .environment(app)
        .environment(\.dynamicTypeSize, typeSize)
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.themePalette, colorScheme == .dark ? ThemePalette.dark : .light)
        .environment(\.colorScheme, colorScheme)
    }

    private func size(_ view: some View, width: CGFloat) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 3_000))
    }

    func testNoStreamsLabelKeepsSecondaryActionsInOverflowOnNarrowPhones() throws {
        let app = PlozziOSAppModel()
        let sources = [MediaSourceRef(accountID: "first", itemID: item.id),
                       MediaSourceRef(accountID: "second", itemID: item.id)]
        for width in [320.0, 345.0, 360.0, 390.0] {
            for sources in [[], sources] {
                let baseline = foreground(app: app, extras: false, sources: sources, noStreams: true)
                let actual = foreground(app: app, extras: true, sources: sources, noStreams: true)
                XCTAssertLessThanOrEqual(size(actual, width: width).width, width + 0.5)
                XCTAssertEqual(size(actual, width: width).height, size(baseline, width: width).height, accuracy: 1)
                let image = try capture(actual, width: width, name: "no-streams-\(Int(width))-sources-\(sources.count)")
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US"]
                try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: " ")
                XCTAssertTrue(lines.contains { $0.localizedCaseInsensitiveContains("No streams found") },
                              "The complete label must occupy one line, not just appear somewhere in the button: \(lines)")
                XCTAssertFalse(text.localizedCaseInsensitiveContains("Play"), text)
            }
        }
    }

    func testNoStreamsLabelReportsItsFullSingleLineWidthBeforeOverflow() {
        for isLoading in [false, true] {
            let label = NoStreamsButtonLabel(isLoading: isLoading, onLight: true)
                .font(.headline.weight(.semibold))
            let natural = size(label, width: 2_000)
            for width in [natural.width - 30, natural.width / 2] {
                let constrained = size(label, width: width)
                XCTAssertEqual(constrained.width, natural.width, accuracy: 0.5)
                XCTAssertEqual(constrained.height, natural.height, accuracy: 0.5)
            }
        }
    }

    func testNoStreamsSpinnerIsCompactAndContrastsWithTheActualButtonSurface() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let app = PlozziOSAppModel()
        for scheme in [ColorScheme.dark, .light] {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 844)
            window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            window.rootViewController = UIHostingController(rootView:
                foreground(app: app, extras: true, noStreams: true, isRetrying: true, colorScheme: scheme)
                    .frame(width: 345)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previous?.makeKeyAndVisible()
            }
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            let indicators = activityIndicators(in: window).filter { $0.window != nil && !$0.isHidden }
            XCTAssertFalse(indicators.isEmpty, "Inspect the real native spinner, not an ImageRenderer placeholder.")
            for indicator in indicators {
                XCTAssertTrue(indicator.isAnimating)
                XCTAssertLessThanOrEqual(indicator.bounds.width, 20)
                XCTAssertLessThanOrEqual(indicator.bounds.height, 20)
                let color = try XCTUnwrap(indicator.color).resolvedColor(with: indicator.traitCollection)
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
                XCTAssertGreaterThanOrEqual(alpha, 0.8)
                if scheme == .dark {
                    XCTAssertLessThanOrEqual(max(red, green, blue), 0.2, "White primary button needs dark ink.")
                } else {
                    XCTAssertGreaterThanOrEqual(min(red, green, blue), 0.8, "Black primary button needs light ink.")
                }
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "no-streams-native-spinner-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([recognition])
            let lines = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            XCTAssertTrue(lines.contains { $0.localizedCaseInsensitiveContains("No streams found") }, "\(lines)")
        }
    }

    private func activityIndicators(in view: UIView) -> [UIActivityIndicatorView] {
        (view as? UIActivityIndicatorView).map { [$0] } ?? view.subviews.flatMap { activityIndicators(in: $0) }
    }

    private func assertBottomIconCount(
        _ expected: Int, in image: UIImage, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let cgImage = try XCTUnwrap(image.cgImage)
        // The capture has 16pt padding; sample the centers of the bottom 48pt controls.
        let row = try XCTUnwrap(cgImage.cropping(to: CGRect(
            x: 0, y: cgImage.height - Int(40 * image.scale), width: cgImage.width, height: 1
        )))
        var bytes = [UInt8](repeating: 0, count: row.width * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: row.width, height: 1, bitsPerComponent: 8,
                bytesPerRow: row.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(row, in: CGRect(x: 0, y: 0, width: row.width, height: 1))
        }
        var widths: [Int] = []
        var currentWidth = 0
        for x in 0..<row.width {
            if bytes[x * 4] > 8 || bytes[x * 4 + 1] > 8 || bytes[x * 4 + 2] > 8 {
                currentWidth += 1
            } else if currentWidth > 0 {
                widths.append(currentWidth)
                currentWidth = 0
            }
        }
        if currentWidth > 0 { widths.append(currentWidth) }
        XCTAssertEqual(widths.count, expected, "Expected direct secondary icon buttons.", file: file, line: line)
        for width in widths {
            XCTAssertEqual(CGFloat(width) / image.scale, 48, accuracy: 2, file: file, line: line)
        }
    }

    private func brightPixelBounds(_ image: UIImage) throws -> CGRect {
        let cgImage = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        var bounds = CGRect.null
        for y in 0..<cgImage.height {
            for x in 0..<cgImage.width {
                let offset = (y * cgImage.width + x) * 4
                if bytes[offset] > 200, bytes[offset + 1] > 200, bytes[offset + 2] > 200 {
                    bounds = bounds.union(CGRect(
                        x: CGFloat(x) / image.scale, y: CGFloat(y) / image.scale,
                        width: 1 / image.scale, height: 1 / image.scale
                    ))
                }
            }
        }
        XCTAssertFalse(bounds.isNull, "The icon must be visible, not clipped away.")
        return bounds
    }

    private func capture(_ view: some View, width: CGFloat, name: String) throws -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: width).padding(16).background(.black))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }
}

@MainActor
private final class RequestLayoutActions: MediaItemActionHandling {
    let showsWatchlist: Bool
    let includesWatched: Bool
    init(showsWatchlist: Bool, includesWatched: Bool = false) {
        self.showsWatchlist = showsWatchlist
        self.includesWatched = includesWatched
    }
    func actions(for item: MediaItem, context: MediaItemActionContext) -> [MediaItemAction] {
        (showsWatchlist ? [.addToWatchlist] : []) + (includesWatched ? [.markWatched] : [])
    }
    func perform(_ action: MediaItemAction, on item: MediaItem, context: MediaItemActionContext) {}
}

@MainActor @Observable
private final class UpdatingDetailHero {
    let app = PlozziOSAppModel()
    let menu = PlaybackSourceMenuState()
    var hasTrailer = false
    var width = 350.0
    var versions: [MediaVersion] = [
        .init(id: "first", name: "Original copy", height: 2160),
        .init(id: "second", name: "Another copy", height: 1080)
    ]
}

private struct UpdatingDetailHeroView: View {
    let fixture: UpdatingDetailHero

    var body: some View {
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie)
        let presentation = HeroPresentation(item: item, artworkStyle: .compactPortrait, surface: .detail)
        PlozziOSDetailHeroForeground(
            sourceMenu: fixture.menu,
            item: item, rootItem: item, playableItem: item,
            sources: [], selectedSourceAccountID: nil,
            versions: fixture.versions, selectedVersionID: "first",
            onSelectSource: { _ in }, onSelectVersion: { _ in },
            presentation: presentation, fallbackPresentation: presentation, style: .compactPortrait,
            actionHandler: RequestLayoutActions(showsWatchlist: true), onPlay: { _, _ in },
            trailerItem: fixture.hasTrailer ? item : nil, onPlayTrailer: { _ in }
        )
        .frame(width: fixture.width)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .environment(fixture.app)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.themePalette, .dark)
        .environment(\.colorScheme, .dark)
    }
}
#endif
