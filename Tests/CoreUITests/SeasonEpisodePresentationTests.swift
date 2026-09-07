#if canImport(UIKit)
import CoreModels
import CoreUI
import SwiftUI
import UIKit
import XCTest
#if os(iOS)
import Vision
#endif

@MainActor
final class SeasonEpisodePresentationTests: XCTestCase {
    func testUnavailableArtworkIsAnEmptyThemeAwareBoxWithOnlyADashedOutline() throws {
        var themedPixels: [[UInt8]] = []
        for colorScheme in [ColorScheme.light, .dark] {
            for symbol in [MediaArtworkPlaceholder.Symbol.playback, .media] {
                let content = SeasonEpisodeRowArtwork(showsMediaEdge: symbol == .playback) {
                    MediaArtworkPlaceholder(glyphSize: 16, symbol: symbol)
                }
                .environment(\.colorScheme, colorScheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, 80, accuracy: 0.5)
                XCTAssertEqual(image.size.height, 45, accuracy: 0.5)
                if symbol == .media {
                    let bitmap = try rgbaPixels(in: image)
                    themedPixels.append(bitmap.pixels)
                    for y in 12..<(bitmap.height - 12) {
                        for x in 12..<(bitmap.width - 12) {
                            XCTAssertEqual(
                                bitmap.pixels[(y * bitmap.width + x) * 4 + 3], 0,
                                "Unavailable artwork must have no interior fill or center glyph."
                            )
                        }
                    }
                    let edgeAlpha = (16..<(bitmap.width - 16)).map { x in bitmap.pixels[x * 4 + 3] }
                    XCTAssertTrue(edgeAlpha.contains { $0 > 0 }, "The outline must reach the box edge.")
                    XCTAssertTrue(edgeAlpha.contains(0), "Dashes must have gaps, with no solid border underneath.")
                }
            }
        }
        XCTAssertNotEqual(themedPixels[0], themedPixels[1], "The gray outline must adapt to light and dark themes.")
    }

    func testUnavailableSeasonArtworkOutlinesTheEntirePortraitBox() throws {
        let renderer = ImageRenderer(content: SeasonDownloadRowArtwork(showsMediaEdge: false) {
            MediaArtworkPlaceholder(symbol: .media)
        })
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, 46, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 68, accuracy: 0.5)
        let bitmap = try rgbaPixels(in: image)
        let centerAlpha = bitmap.pixels[((bitmap.height / 2) * bitmap.width + bitmap.width / 2) * 4 + 3]
        XCTAssertEqual(centerAlpha, 0)
        let edgeAlpha = (16..<(bitmap.width - 16)).map { x in bitmap.pixels[x * 4 + 3] }
        XCTAssertTrue(edgeAlpha.contains { $0 > 0 })
        XCTAssertTrue(edgeAlpha.contains(0))
    }

    private func rgbaPixels(in image: UIImage) throws -> (width: Int, height: Int, pixels: [UInt8]) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        return (width, height, pixels)
    }

    private func requestControls(
        _ state: MediaSeasonRequestState?,
        unavailable: Bool = true,
        submitting: Bool = false,
        failed: Bool = false
    ) -> some View {
        SeasonEpisodeRequestControls(
            state: state, hasUnavailableEpisodes: unavailable,
            isSubmitting: submitting, isRefreshing: false, refreshFailed: failed,
            actingName: nil, managementURL: URL(string: "https://example.com/tv/100"),
            onRefresh: {}, onRequest: {}
        )
    }

    private func state(_ status: MediaAvailabilityStatus) -> MediaSeasonRequestState {
        .init(number: 8, title: "Season 8", status: status, isPresentInLibrary: true)
    }

    func testRequestAndManagedStatesRenderWithoutPerEpisodeActions() throws {
        for status in [
            MediaAvailabilityStatus.unknown, .deleted, .partiallyAvailable,
            .available, .pending, .processing,
        ] {
            let content = VStack { requestControls(state(status)) }
                .frame(width: 320).padding(16)
            let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
            XCTAssertGreaterThanOrEqual(image.size.height, 76)
        }
    }

    func testFullyPresentSeasonDoesNotOfferAnotherRequest() throws {
        let content = VStack { requestControls(state(.unknown), unavailable: false) }
            .frame(width: 320).padding(16)
        let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
        XCTAssertEqual(image.size.height, 32, accuracy: 0.5)
    }

    func testMetadataRowsKeepTheSameArtworkAndWrappingAtLargeText() throws {
        for availability in [
            SeasonEpisodeAvailability.inLibrary, .missing, .unaired,
            .airingToday, .recentlyReleased, .releaseDateUnknown,
        ] {
            let content = episodeRow(number: 1, availability: availability)
                .environment(\.dynamicTypeSize, .accessibility5)
                .frame(width: 320).padding(16)
            let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
            XCTAssertEqual(image.size.width, 352, accuracy: 0.5)
            XCTAssertGreaterThan(image.size.height, 90)
            let attachment = XCTAttachment(image: image)
            attachment.name = "episode-row-large-\(availability)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func downloadButton(destination: MediaDownloadDestination = .iPhone) -> some View {
        Button {} label: {
            SeriesDownloadActionLabel(
                title: SeriesDownloadAction.download.title(for: destination),
                subtitle: "All available episodes in this season, for offline viewing.",
                systemImage: SeriesDownloadAction.download.systemImage
            ) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 25))
                    .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.plain)
    }

    private func episodeRow(number: Int, availability: SeasonEpisodeAvailability) -> some View {
        SeasonEpisodeRowContent(
            number: number,
            title: number == 1 ? "The Beginning of a Very Long Adventure" : "Episode title"
        ) {
            SeasonEpisodeRowArtwork(showsMediaEdge: availability == .inLibrary) {
                MediaArtworkPlaceholder(
                    glyphSize: 16, symbol: availability == .inLibrary ? .playback : .media
                )
            }
        } status: {
            SeasonEpisodeAvailabilityLabel(
                availability: availability,
                airDate: MediaItem.calendarDayReleaseDate(from: "2026-09-13")
            )
        } accessory: {
            if availability == .inLibrary {
                Button {} label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 25))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Download Episode")
            }
        }
    }

    #if os(iOS)
    func testFullDownloadLabelNeverTruncatesOnSmallPhoneOrLargestText() throws {
        for (destination, deviceName) in [
            (MediaDownloadDestination.iPhone, "iphone"), (.iPad, "ipad"),
        ] {
            for size in [DynamicTypeSize.large, .accessibility5] {
                let content = downloadButton(destination: destination)
                    .font(.body)
                    .environment(\.dynamicTypeSize, size)
                    .environment(\.colorScheme, .light)
                    .frame(width: 280)
                    .padding(16)
                    .background(.white)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 3
                let image = try XCTUnwrap(renderer.uiImage)
                let text = try recognizedText(in: image).lowercased()
                for word in [
                    "download", "to", "this", deviceName, "all", "available",
                    "episodes", "season", "offline", "viewing",
                ] {
                    XCTAssertTrue(text.contains(word), "Missing \(word) at \(size): \(text)")
                }
                XCTAssertFalse(text.contains("…"), text)
                let attachment = XCTAttachment(image: image)
                attachment.name = "episode-download-label-\(deviceName)-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testRequestCopyExplainsLibraryDestinationWithoutTruncation() throws {
        for size in [DynamicTypeSize.large, .accessibility5] {
            let content = VStack { requestControls(state(.unknown)) }
                .font(.body)
                .environment(\.dynamicTypeSize, size)
                .environment(\.colorScheme, .light)
                .frame(width: 280).padding(16).background(.white)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            let text = try recognizedText(in: XCTUnwrap(renderer.uiImage)).lowercased()
            for word in ["request", "season", "ask", "missing", "episodes", "added", "your", "library"] {
                XCTAssertTrue(text.contains(word), "Missing \(word) at \(size): \(text)")
            }
            XCTAssertFalse(text.contains("download"), text)
            XCTAssertFalse(text.contains("…"), text)
        }
    }

    func testPendingRequestNamesTheLibraryRatherThanTheDevice() throws {
        let content = VStack { requestControls(state(.pending)) }
            .font(.body).frame(width: 320).padding(16).background(.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        let text = try recognizedText(in: XCTUnwrap(renderer.uiImage)).lowercased()
        XCTAssertTrue(text.contains("requested for your library"), text)
        XCTAssertFalse(text.contains("downloading"), text)
    }

    func testManagedSeasonShowsManagementInsteadOfAnotherRequest() throws {
        let content = VStack { requestControls(state(.partiallyAvailable)) }
            .font(.body).frame(width: 320).padding(16).background(.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        let text = try recognizedText(in: XCTUnwrap(renderer.uiImage))
        XCTAssertTrue(text.contains("Season Already Managed"), text)
        XCTAssertTrue(text.contains("Seerr"), text)
        XCTAssertFalse(text.contains("Request Season"), text)
    }

    func testNativeCompleteSeasonScreenAcrossPhoneTabletAndAppearance() async throws {
        for (name, size) in [
            ("phone", CGSize(width: 375, height: 812)),
            ("landscape", CGSize(width: 812, height: 375)),
            ("tablet", CGSize(width: 768, height: 1024)),
        ] {
            try await captureNativeSheet(
                screen(destination: name == "tablet" ? .iPad : .iPhone),
                size: size, name: "episode-coverage-\(name)"
            )
        }
        for style in [ColorScheme.light, .dark] {
            try await captureNativeSheet(
                screen(style: style).environment(\.dynamicTypeSize, .accessibility5),
                size: CGSize(width: 375, height: 812),
                name: "episode-coverage-accessibility-\(style)", colorScheme: style
            )
        }
        try await captureNativeSheet(
            screen(metadataFailed: true),
            size: CGSize(width: 375, height: 812), name: "episode-coverage-retry"
        )
        try await captureNativeSheet(
            screen(managed: true),
            size: CGSize(width: 375, height: 812), name: "episode-coverage-managed"
        )
    }

    private func screen(
        destination: MediaDownloadDestination = .iPhone,
        style: ColorScheme = .dark,
        metadataFailed: Bool = false,
        managed: Bool = false
    ) -> some View {
        var series = MediaItem(id: "show", title: "Show", kind: .series, providerIDs: ["Tmdb": "100"])
        series.sourceAccountID = "server-a"
        let library = (4...10).map { number in
            var episode = MediaItem(
                id: "episode-\(number)", title: "Episode title", kind: .episode,
                seasonNumber: 8, episodeNumber: number, seriesID: "show"
            )
            episode.sourceAccountID = "server-a"
            return episode
        }
        let roster = SeasonEpisodeRoster(
            seriesTMDbID: 100, seasonNumber: 8,
            episodes: (1...11).map {
                SeasonEpisodeMetadata(
                    id: 1000 + $0, seasonNumber: 8, episodeNumber: $0,
                    airDate: MediaItem.calendarDayReleaseDate(from: $0 == 11 ? "2099-09-13" : "2020-01-01")
                )
            }
        )
        let list = SeasonEpisodeList(
            series: series, seasonNumber: 8, libraryEpisodes: library,
            roster: metadataFailed ? nil : roster
        )
        return NavigationStack {
            List {
                Section {
                    downloadButton(destination: destination)
                    if metadataFailed {
                        Button {} label: {
                            SeriesDownloadActionLabel(
                                title: "Retry Episode Information",
                                subtitle: "Couldn’t load the full episode list. Library downloads are still available.",
                                systemImage: "arrow.clockwise"
                            ) {}
                        }
                        .buttonStyle(.plain)
                    } else {
                        requestControls(state(managed ? .partiallyAvailable : .unknown))
                    }
                } header: {
                    SeasonEpisodeCoverageHeader(
                        coverage: list.coverage, isLoading: false, hasNumberingConflict: false
                    )
                }
                Section("Episodes") {
                    ForEach(list.rows) { row in
                        self.episodeRow(number: row.episodeNumber ?? 1, availability: row.availability)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 12, for: .scrollContent)
            .listSectionSpacing(16)
            .navigationTitle("Season 8")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") {}
                }
            }
        }
        .tint(.blue)
        .environment(\.colorScheme, style)
        .environment(\.locale, Locale(identifier: "en"))
        .transaction { $0.disablesAnimations = true }
    }

    private func recognizedText(in image: UIImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
    #endif
}
#endif
