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
    func testLeavingCollectionReplacesArtworkButHorizontalMovesPreserveIt() async throws {
        let playing = EpisodeRowProvider.episode(season: 2, number: 2)
        let player = PlayerViewModel(provider: EpisodeRowProvider(), itemID: playing.id, episodeItem: playing)
        let browser = try XCTUnwrap(player.episodeBrowser)
        await browser.loadIfNeeded()
        try await withProductionPanel(player) { model, window in
            try await self.waitUntil { model.observedFocus == .button(.episodes) }
            let entry = try XCTUnwrap(browser.initialEntryID)
            model.target = entry
            try await self.waitUntil {
                (UIFocusSystem.focusSystem(for: window)?.focusedItem as? PlayerEpisodeNativeCell)?
                    .accessibilityLabel == playing.title
            }
            let cell = try XCTUnwrap(self.nativePosters(in: window).first(where: \.isFocused))
            let artwork = try XCTUnwrap(cell.contentView as? TVMediaItemContentView)
            let configuration = try XCTUnwrap(artwork.configuration as? TVMediaItemContentConfiguration)
            let next = try XCTUnwrap(browser.episodes.first { $0.item.id == "2-3" })
            try self.focusEpisode(next.id, in: window)
            try await self.waitUntil { !cell.isFocused }
            XCTAssertTrue(cell.contentView === artwork, "Horizontal browsing must not recreate artwork.")
            try self.focusEpisode(entry, in: window)
            try await self.waitUntil { cell.isFocused }
            let collection = try XCTUnwrap(self.scrollView(in: window) as? UICollectionView)
            let coordinator = try XCTUnwrap(collection.delegate as? PlayerEpisodeNativeRow.Coordinator)
            try await self.waitUntil {
                coordinator.focusAnimations == 0 && !browser.isLoadingPrevious && !browser.isLoadingNext
            }
            model.target = nil
            try await self.waitUntil { model.observedFocus == .button(.episodes) && !cell.isFocused }
            XCTAssertTrue(self.nativePosters(in: window).contains { $0 === cell })
            XCTAssertFalse(cell.contentView === artwork,
                           "Leaving for a SwiftUI tab must actually replace the native projection owner.")
            let replacement = try XCTUnwrap(cell.contentView as? TVMediaItemContentView)
            let replacementConfiguration = try XCTUnwrap(
                replacement.configuration as? TVMediaItemContentConfiguration
            )
            XCTAssertTrue(replacementConfiguration.image === configuration.image,
                          "Resetting focus must reuse the prepared artwork bitmap.")
        }
    }

    func testDisablingFocusedArtworkClearsPresentationBeforeUIKitMovesFocus() async throws {
        let provider = EpisodeRowProvider()
        let playing = EpisodeRowProvider.episode(season: 2, number: 2)
        let player = PlayerViewModel(provider: provider, itemID: playing.id, episodeItem: playing)
        let browser = try XCTUnwrap(player.episodeBrowser)
        await browser.loadIfNeeded()
        try await withProductionPanel(player) { model, window in
            try await self.waitUntil { model.observedFocus == .button(.episodes) }
            let entry = try XCTUnwrap(browser.episodes.first { $0.item.id == playing.id })
            model.target = entry.id
            try await self.waitUntil {
                (UIFocusSystem.focusSystem(for: window)?.focusedItem as? PlayerEpisodeNativeCell)?
                    .accessibilityLabel == playing.title
            }
            try await Task.sleep(for: .milliseconds(300))
            let cell = try XCTUnwrap(self.nativePosters(in: window).first(where: \.isFocused))
            let caption = try XCTUnwrap(self.views(in: cell, of: NativePosterCaptionLine.self).first)
            let layout = PlayerSequenceLayout(metrics: .tv, cardMetrics: .standard, contained: true, hasError: false)
            var environment = EnvironmentValues()
            environment.isEnabled = false
            cell.configure(.episode(entry), layout: layout, environment: environment)
            cell.updateConfiguration(using: cell.configurationState)
            cell.layoutIfNeeded()
            XCTAssertFalse(cell.canBecomeFocused)
            XCTAssertEqual(caption.transform.ty, 0, accuracy: 0.1,
                           "Parking must clear the caption without waiting for UIKit's focus departure.")
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Disabled episode artwork before focus departure"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            let cgImage = try XCTUnwrap(image.cgImage)
            let scale = CGFloat(cgImage.width) / window.bounds.width
            let frame = cell.convert(cell.bounds, to: window)
            let crop = try XCTUnwrap(cgImage.cropping(to: CGRect(
                x: frame.midX * scale, y: frame.minY * scale, width: 1, height: 30 * scale
            ).integral))
            var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            let firstArtworkRow = try pixels.withUnsafeMutableBytes { bytes -> Int? in
                let context = try XCTUnwrap(CGContext(
                    data: bytes.baseAddress, width: crop.width, height: crop.height,
                    bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
                return (0..<crop.height).first {
                    let offset = $0 * crop.width * 4
                    return max(bytes[offset], bytes[offset + 1], bytes[offset + 2]) > 50
                }
            }
            XCTAssertEqual(CGFloat(try XCTUnwrap(firstArtworkRow)) / scale, 12, accuracy: 2,
                           "A disabled card must paint at resting size, even before the focus system catches up.")
        }
    }

    func testNativeMarqueePaintFadesBothEdgesAndKeepsRestingTextInsideTheFade() throws {
        for direction in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
            let caption = NativePosterCaptionLine()
            caption.semanticContentAttribute = direction
            caption.frame = CGRect(x: 0, y: 0, width: 240, height: 26)
            caption.configure(
                text: "A long episode name that extends beyond the caption's readable area",
                font: .systemFont(ofSize: 21), color: .white, scrolls: false,
                centersShortText: false, horizontalInset: 12
            )
            caption.layoutIfNeeded()
            let label = try XCTUnwrap(views(in: caption, of: UILabel.self).first)
            if direction == .forceLeftToRight {
                XCTAssertEqual(label.frame.minX, 12, accuracy: 0.1)
            } else {
                XCTAssertEqual(label.frame.maxX, 228, accuracy: 0.1)
            }
            // Solid test ink isolates the mask from individual glyph shapes.
            let ink = UIView(frame: caption.bounds)
            ink.backgroundColor = .white
            caption.addSubview(ink)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let rendered = UIGraphicsImageRenderer(size: caption.bounds.size, format: format).image {
                caption.layer.render(in: $0.cgContext)
            }
            let image = try XCTUnwrap(rendered.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            try pixels.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(
                    data: bytes.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let row = image.height / 2 * image.width
                XCTAssertLessThan(bytes[(row + 1) * 4 + 3], 60)
                XCTAssertGreaterThan(bytes[(row + 12) * 4 + 3], 245)
                XCTAssertGreaterThan(bytes[(row + image.width - 13) * 4 + 3], 245)
                XCTAssertLessThan(bytes[(row + image.width - 2) * 4 + 3], 60)
            }
        }
    }

    func testSingleLineEpisodeCaptionFollowsLeadingEdgeWhenDirectionChanges() throws {
        let layout = PlayerSequenceLayout(metrics: .tv, cardMetrics: .standard, contained: true, hasError: false)
        let cell = PlayerEpisodeNativeCell(frame: CGRect(x: 0, y: 0, width: layout.cardWidth, height: layout.rowHeight))
        let entry = PlayerEpisodeEntry(
            item: MediaItem(id: "episode", title: "A short title", kind: .episode),
            seasonID: "season", seasonNumber: 1
        )
        var environment = EnvironmentValues()
        for direction in [LayoutDirection.leftToRight, .rightToLeft, .leftToRight] {
            environment.layoutDirection = direction
            cell.configure(.episode(entry), layout: layout, environment: environment)
            cell.updateConfiguration(using: cell.configurationState)
            cell.layoutIfNeeded()
            let caption = try XCTUnwrap(views(in: cell, of: NativePosterCaptionLine.self).first)
            caption.layoutIfNeeded()
            let label = try XCTUnwrap(views(in: caption, of: UILabel.self).first)
            XCTAssertEqual(label.numberOfLines, 1)
            let inset = layout.cardMetrics.landscapeCaptionInset
            XCTAssertEqual(
                label.frame.minX,
                direction == .rightToLeft ? caption.bounds.width - inset - label.frame.width : inset,
                accuracy: 0.1
            )
            XCTAssertNil(label.layer.animation(forKey: "captionMarquee"))
        }
        cell.prepareForReuse()
        XCTAssertNil(cell.contentConfiguration)
        XCTAssertFalse(cell.canBecomeFocused)
    }

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
                !self.views(in: window, of: PlayerEpisodeNativeCell.self).isEmpty && model.observedFocus == .button(.episodes)
            }
            let entry = try XCTUnwrap(browser.initialEntryID)
            model.target = entry
            try await self.waitUntil {
                (UIFocusSystem.focusSystem(for: window)?.focusedItem as? PlayerEpisodeNativeCell)?
                    .accessibilityLabel == playing.title
            }
            try await self.waitUntil { await provider.isHolding("season-1") }
            for number in [3, 2] {
                let target = try XCTUnwrap(browser.episodes.first { $0.item.id == "2-\(number)" })
                try self.focusEpisode(target.id, in: window)
                try await self.waitUntil {
                    (UIFocusSystem.focusSystem(for: window)?.focusedItem as? PlayerEpisodeNativeCell)?
                        .accessibilityLabel == target.item.title
                }
            }
            try await Task.sleep(for: .milliseconds(300))
            let poster = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem as? PlayerEpisodeNativeCell)
            let scroll = try XCTUnwrap(self.scrollView(in: window))
            try await self.waitUntil { !scroll.isDecelerating && !scroll.isDragging }
            // Preserve even a viewport parked between card slots.
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x + 47, y: 0), animated: false)
            try await Task.sleep(for: .milliseconds(100))
            let frame = poster.convert(poster.bounds, to: window)
            let width = scroll.contentSize.width
            let count = browser.episodes.count
            await provider.release("season-1")
            try await self.waitUntil { browser.episodes.count >= count + 8 && scroll.contentSize.width > width + 1000 }
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(20))
                XCTAssertTrue(UIFocusSystem.focusSystem(for: window)?.focusedItem === poster)
                XCTAssertEqual(model.observedFocus, .episodeItem(entry))
                XCTAssertEqual(poster.convert(poster.bounds, to: window).minX, frame.minX, accuracy: 1,
                               "Prepending must preserve the offset within the card, not realign it.")
            }
        }
    }

    func testPrependFinishingDuringNativeFocusTransitionNeverMovesFocusToAnotherEpisode() async throws {
        let provider = EpisodeRowProvider()
        await provider.hold("season-1")
        defer { Task { await provider.release("season-1") } }
        let playing = EpisodeRowProvider.episode(season: 2, number: 2)
        let player = PlayerViewModel(provider: provider, itemID: playing.id, episodeItem: playing)
        let browser = try XCTUnwrap(player.episodeBrowser)
        await browser.loadIfNeeded()
        try await withProductionPanel(player) { model, window in
            try await self.waitUntil {
                !self.views(in: window, of: PlayerEpisodeNativeCell.self).isEmpty && model.observedFocus == .button(.episodes)
            }
            model.target = browser.initialEntryID
            try await self.waitUntil {
                UIFocusSystem.focusSystem(for: window)?.focusedItem is PlayerEpisodeNativeCell
            }
            for number in [2, 3, 2] {
                let entry = try XCTUnwrap(browser.episodes.first { $0.item.id == "2-\(number)" })
                try self.focusEpisode(entry.id, in: window)
                try await self.waitUntil {
                    (UIFocusSystem.focusSystem(for: window)?.focusedItem as? PlayerEpisodeNativeCell)?
                        .accessibilityLabel == entry.item.title
                }
            }
            try await self.waitUntil { await provider.isHolding("season-1") }
            let poster = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem as? PlayerEpisodeNativeCell)
            let scroll = try XCTUnwrap(self.scrollView(in: window))
            let width = scroll.contentSize.width
            let count = browser.episodes.count
            let coordinator = try XCTUnwrap((scroll as? UICollectionView)?.delegate as? PlayerEpisodeNativeRow.Coordinator)
            XCTAssertGreaterThan(coordinator.focusAnimations, 0, "Complete the request during a native focus transition.")
            await provider.release("season-1")
            var priorX = poster.convert(poster.bounds, to: window).minX
            for _ in 0..<75 {
                try await Task.sleep(for: .milliseconds(20))
                XCTAssertTrue(UIFocusSystem.focusSystem(for: window)?.focusedItem === poster)
                let x = poster.convert(poster.bounds, to: window).minX
                XCTAssertLessThan(abs(x - priorX), 80, "Loading must not snap the viewport.")
                priorX = x
            }
            XCTAssertGreaterThanOrEqual(browser.episodes.count, count + 8)
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
                !self.views(in: window, of: PlayerEpisodeNativeCell.self).isEmpty && model.observedFocus == .button(.episodes)
            }
            model.target = browser.initialEntryID
            try await self.waitUntil {
                UIFocusSystem.focusSystem(for: window)?.focusedItem is PlayerEpisodeNativeCell
            }
            for number in [8, 7] {
                let target = try XCTUnwrap(browser.episodes.first { $0.item.id == "2-\(number)" })
                try self.focusEpisode(target.id, in: window)
                try await self.waitUntil {
                    (UIFocusSystem.focusSystem(for: window)?.focusedItem as? PlayerEpisodeNativeCell)?
                        .accessibilityLabel == target.item.title
                }
            }
            try await self.waitUntil { await provider.isHolding("season-3") }
            let scroll = try XCTUnwrap(self.scrollView(in: window))
            try await self.waitUntil { !scroll.isDecelerating && !scroll.isDragging }
            try await Task.sleep(for: .milliseconds(100))
            let poster = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem as? PlayerEpisodeNativeCell)
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

    func testLeadingRetryInsertionAndSelectionPreserveTheEpisodeViewport() async throws {
        let provider = EpisodeRowProvider()
        await provider.hold("season-1")
        await provider.failNext("season-1")
        defer { Task { await provider.release("season-1") } }
        let playing = EpisodeRowProvider.episode(season: 2, number: 2)
        let player = PlayerViewModel(provider: provider, itemID: playing.id, episodeItem: playing)
        let browser = try XCTUnwrap(player.episodeBrowser)
        await browser.loadIfNeeded()
        try await withProductionPanel(player) { model, window in
            try await self.waitUntil { model.observedFocus == .button(.episodes) }
            model.target = browser.initialEntryID
            try await self.waitUntil {
                UIFocusSystem.focusSystem(for: window)?.focusedItem is PlayerEpisodeNativeCell
            }
            try await self.waitUntil { await provider.isHolding("season-1") }
            let cell = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem as? PlayerEpisodeNativeCell)
            let collection = try XCTUnwrap(self.scrollView(in: window) as? UICollectionView)
            let source = try XCTUnwrap(collection.dataSource as? UICollectionViewDiffableDataSource<Int, NativeEpisodeElement.ID>)
            try await Task.sleep(for: .milliseconds(300))
            let x = cell.convert(cell.bounds, to: window).minX
            await provider.release("season-1")
            try await self.waitUntil { source.indexPath(for: .previousError) != nil }
            XCTAssertTrue(UIFocusSystem.focusSystem(for: window)?.focusedItem === cell)
            XCTAssertEqual(cell.convert(cell.bounds, to: window).minX, x, accuracy: 1)
            let retry = try XCTUnwrap(source.indexPath(for: .previousError))
            collection.delegate?.collectionView?(collection, didSelectItemAt: retry)
            try await self.waitUntil {
                browser.previousLoadError == nil && browser.episodes.first?.seasonNumber == 1
                    && source.indexPath(for: .previousError) == nil
            }
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(UIFocusSystem.focusSystem(for: window)?.focusedItem === cell)
            XCTAssertEqual(cell.convert(cell.bounds, to: window).minX, x, accuracy: 1)
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
            XCTAssertTrue(self.views(in: window, of: PlayerEpisodeNativeCell.self).isEmpty)
            XCTAssertTrue(self.views(in: window, of: UIActivityIndicatorView.self).isEmpty)
            let before = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem)
            let loadingScroll = try XCTUnwrap(self.scrollView(in: window))
            let scrollFrame = loadingScroll.convert(loadingScroll.bounds, to: window)
            let attachment = XCTAttachment(image: DetailTransitionSnapshot.image(of: window))
            attachment.name = "Episode loading skeleton"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            await provider.release("series")
            try await self.waitUntil { browser.hasLoaded && !self.views(in: window, of: PlayerEpisodeNativeCell.self).isEmpty }
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
                    id: "episode-\(number)",
                    title: number == 3
                        ? "An episode with a long title that must scroll without widening the artwork or wrapping"
                        : "Episode \(number)",
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

        try await waitUntil { !self.nativePosters(in: window).isEmpty }
        for index in [0, 1, 2, 3, 2] {
            if index == 0 {
                model.target = entries[index].id
            } else {
                try focusEpisode(entries[index].id, in: window)
            }
            try await waitUntil {
                (UIFocusSystem.focusSystem(for: window)?.focusedItem as? PlayerEpisodeNativeCell)?
                    .accessibilityLabel == entries[index].item.title
            }
            try await Task.sleep(for: .milliseconds(250))
            let posters = nativePosters(in: window)
            XCTAssertEqual(posters.filter(\.isFocused).count, 1)
            XCTAssertEqual(model.observedFocus, .episodeItem(entries[index].id))
            XCTAssertTrue(posters.filter { $0.accessibilityLabel != entries[index].item.title }
                .allSatisfy { !$0.isFocused })
            XCTAssertTrue(posters.filter(\.isFocused).allSatisfy {
                guard let media = self.views(in: $0, of: TVMediaItemContentView.self).first,
                      let configuration = media.configuration as? TVMediaItemContentConfiguration else { return false }
                return configuration.text?.isEmpty != false && configuration.secondaryText?.isEmpty != false
            },
                          "Titles must remain outside the native artwork projection.")
        }

        let focused = try XCTUnwrap(nativePosters(in: window).first(where: \.isFocused))
        let media = try XCTUnwrap(views(in: focused, of: TVMediaItemContentView.self).first)
        let caption = try XCTUnwrap(views(in: focused, of: NativePosterCaptionLine.self).first)
        let label = try XCTUnwrap(views(in: caption, of: UILabel.self).first)
        XCTAssertEqual(label.numberOfLines, 1)
        XCTAssertEqual(caption.bounds.height, caption.lineHeight, accuracy: 0.1)
        XCTAssertGreaterThan(media.bounds.height, 205)
        let travel: CGFloat = 8
        XCTAssertEqual(caption.transform.ty, travel, accuracy: 0.1)
        XCTAssertEqual(media.frame.minY, focused.bounds.maxY - caption.frame.maxY + travel, accuracy: 0.1,
                       "Resting insets remain balanced; focus only moves the caption down.")
        XCTAssertEqual(caption.bounds.width, media.bounds.width)
        let mask = try XCTUnwrap(caption.layer.mask as? CAGradientLayer)
        let colors = try XCTUnwrap(mask.colors as? [CGColor])
        XCTAssertEqual(colors.map(\.alpha), [0, 1, 1, 0])
        try await waitUntil { abs(label.layer.presentation()?.transform.m41 ?? 0) > 2 }
        XCTAssertNotNil(label.layer.animation(forKey: "captionMarquee"))
        for other in nativePosters(in: window) where other !== focused {
            for title in views(in: other, of: NativePosterCaptionLine.self).flatMap({ views(in: $0, of: UILabel.self) }) {
                XCTAssertNil(title.layer.animation(forKey: "captionMarquee"))
            }
        }
        let configuration = try XCTUnwrap(media.configuration as? TVMediaItemContentConfiguration)
        let projectedImage = try XCTUnwrap(configuration.image?.cgImage)
        var artworkPixels = [UInt8](repeating: 0, count: projectedImage.width * projectedImage.height * 4)
        let artworkContext = try XCTUnwrap(CGContext(
            data: &artworkPixels, width: projectedImage.width, height: projectedImage.height,
            bitsPerComponent: 8, bytesPerRow: projectedImage.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        artworkContext.draw(projectedImage, in: CGRect(x: 0, y: 0, width: projectedImage.width, height: projectedImage.height))
        XCTAssertGreaterThan(stride(from: 0, to: artworkPixels.count, by: 4).filter {
            min(artworkPixels[$0], artworkPixels[$0 + 1], artworkPixels[$0 + 2]) > 230
        }.count, 20, "The native focus projection must include the white season/episode label.")

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
        try focusEpisode(entries[1].id, in: window)
        try await waitUntil {
            !focused.isFocused && label.layer.animation(forKey: "captionMarquee") == nil
        }
        XCTAssertEqual(label.layer.transform.m41, 0, accuracy: 0.1,
                       "Leaving focus must restore the beginning of the title.")
        try await waitUntil {
            abs(caption.layer.presentation()?.transform.m42 ?? caption.layer.transform.m42) < 0.1
        }
        XCTAssertEqual(caption.transform.ty, 0, accuracy: 0.1)
    }

    private func focusEpisode(_ id: PlayerEpisodeEntry.ID, in window: UIWindow) throws {
        let collection = try XCTUnwrap(scrollView(in: window) as? UICollectionView)
        let dataSource = try XCTUnwrap(collection.dataSource as? UICollectionViewDiffableDataSource<Int, NativeEpisodeElement.ID>)
        let index = try XCTUnwrap(dataSource.indexPath(for: .episode(id)))
        if collection.cellForItem(at: index) == nil {
            collection.scrollToItem(at: index, at: [], animated: false)
            collection.layoutIfNeeded()
        }
        let coordinator = try XCTUnwrap(collection.delegate as? PlayerEpisodeNativeRow.Coordinator)
        coordinator.requestFocus(at: index)
    }

    private func nativePosters(in view: UIView) -> [PlayerEpisodeNativeCell] {
        (view as? PlayerEpisodeNativeCell).map { [$0] } ?? view.subviews.flatMap { nativePosters(in: $0) }
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
    @State private var currentID: PlayerEpisodeEntry.ID?
    private let layout = PlayerSequenceLayout(
        metrics: .tv, cardMetrics: .standard, contained: true, hasError: false
    )

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerEpisodeNativeRow(
                items: entries.map(NativeEpisodeElement.episode), initialID: entries.first?.id,
                layout: layout, focus: $focus, onVisible: { _ in },
                onFocus: { currentID = $0 }, onSelect: { _ in }
            )
                .frame(height: layout.rowHeight)
                .modifier(PlayerEpisodePanelSurface(layout: layout))
                .frame(width: 1000)
                .focused($focus, equals: (currentID ?? entries.first?.id).map(PlayerControls.FocusSlot.episodeItem))
                .onChange(of: currentID) { _, id in
                    if let id { focus = .episodeItem(id) }
                }
                .onChange(of: model.target) { _, id in
                    if let id { focus = .episodeItem(id) }
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
            focus = id.map(PlayerControls.FocusSlot.episodeItem) ?? .button(.episodes)
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
    private var failures: Set<String> = []
    private(set) var requests: [String] = []

    nonisolated static func episode(season: Int, number: Int) -> MediaItem {
        MediaItem(
            id: "\(season)-\(number)", title: "Season \(season) Episode \(number)", kind: .episode,
            seasonNumber: season, episodeNumber: number, seriesID: "series", seasonID: "season-\(season)"
        )
    }

    func hold(_ id: String) { heldIDs.insert(id) }
    func failNext(_ id: String) { failures.insert(id) }
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
        if failures.remove(itemID) != nil { throw AppError.invalidResponse }
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
