#if os(iOS)
import CoreModels
import CoreUI
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlaybackDiagnosticsLocalizationTests: XCTestCase {
    func testErrorDetailsSheetUsesCenteredInlineTitleAndLeadingCloseIcon() async throws {
        try await assertDetailsHeader(.onDemand(
            error: .noStreams, provider: .jellyfin, engine: nil, stage: .preparation
        ))
        try await assertDetailsHeader(.library(.init(
            provider: .jellyfin, operation: .libraryBrowse,
            failures: [.init(section: .collections, error: .invalidResponse, paging: [
                .init(stage: .collectionMembers, reason: .nonAdvancing, start: 24, rows: 1, total: 25)
            ])]
        )))
    }

    private func assertDetailsHeader(_ report: PlaybackDiagnosticReport) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer {
            presenter.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        let sheet = UIHostingController(rootView: PlaybackDiagnosticDetailsSheet(
            report: report
        ).environment(\.locale, Locale(identifier: "en_US")))
        sheet.modalPresentationStyle = .pageSheet
        await withCheckedContinuation { continuation in
            presenter.present(sheet, animated: true) { continuation.resume() }
        }
        sheet.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        func descendants(_ view: UIView) -> [UIView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let bar = try XCTUnwrap(descendants(sheet.view).compactMap { $0 as? UINavigationBar }.first)
        let item = try XCTUnwrap(bar.topItem)
        XCTAssertEqual(item.title, "Details")
        XCTAssertLessThanOrEqual(bar.bounds.height, 64, "The title must remain inline, not a large scrolling heading.")
        let buttons = (item.leftBarButtonItems ?? []) + item.leadingItemGroups.flatMap(\.barButtonItems)
        XCTAssertEqual(buttons.count, 1)
        XCTAssertNotNil(buttons.first?.image)
        XCTAssertTrue((item.rightBarButtonItems ?? []).isEmpty && item.trailingItemGroups.isEmpty)
        let title = try XCTUnwrap(descendants(bar).compactMap { $0 as? UILabel }.first { $0.text == "Details" })
        XCTAssertEqual(title.convert(title.bounds, to: bar).midX, bar.bounds.midX, accuracy: 2)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        })
        attachment.name = "Centered Details title and leading Close"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private let commonLabelKeys = [
        "File", "Size", "Delivery", "Stream", "Codec", "Resolution", "Frame Rate",
        "Color", "Codec Tag", "Channels", "Sample Rate", "Bitrate", "System output", "Connection", "Track",
        "State", "Buffer", "Engine buffer", "Stalls", "Dropped",
        "Declared stream bitrate", "Network throughput", "Disk", "Memory", "Thermal", "Instances"
    ]

    func testMobileDiagnosticsLocalizeLabelsAndPreserveMediaContent() throws {
        for mode in [PlaybackDiagnostics.PlaybackMode.directPlay, .transcode, .plozzigen] {
            let panel = PlaybackDiagnosticsOverlay(diagnostics: fixture(mode: mode), presentation: .mobile)
            let text = try renderedText(
                panel.mobileContent(width: 844)
                    .frame(width: 844)
                    .fixedSize(horizontal: false, vertical: true),
                locale: "cs"
            )
            try assertLabels(in: text, mode: mode)
            assertMediaContent(in: text)
        }
    }

    func testMobileEngineHeaderIncludesVersionWithoutRepeatingTheOldBrand() throws {
        var diagnostics = fixture(mode: .plozzigen)
        diagnostics.engineName = "AetherEngine v7.44.0"
        let panel = PlaybackDiagnosticsOverlay(diagnostics: diagnostics, presentation: .mobile)
        let text = try renderedText(
            panel.mobileContent(width: 390).frame(width: 390).fixedSize(horizontal: false, vertical: true),
            locale: "en_US"
        )
        XCTAssertTrue(text.contains("AetherEngine"), text)
        XCTAssertTrue(text.contains("v7.44.0"), text)
        XCTAssertFalse(text.contains("Plozzigen"), text)
    }

    func testTelevisionDiagnosticsUseTheSameLocalizedLabels() throws {
        let panel = PlaybackDiagnosticsOverlay(diagnostics: fixture(mode: .transcode), presentation: .television)
        let text = try renderedText(
            panel.televisionPanel(width: 1280),
            locale: "cs"
        )
        try assertLabels(in: text, mode: .transcode, wrapped: true, compact: true)
        assertMediaContent(in: text)
        for value in ["720", "300", "24.00", "Stereo", "48", "128", "HDMI", "628", "8.0"] {
            XCTAssertTrue(text.contains(value), "Combining rows must preserve their measurements: \(text)")
        }
    }

    func testAudioOutputLocalizesDescriptionsButPreservesConnectionFormats() throws {
        var diagnostics = fixture(mode: .plozzigen)
        diagnostics.audioOutput = .init(
            renderingMode: .localized("Surround"),
            connections: [.localized("Headphones"), .format("AirPlay")]
        )
        let bundleURL = try XCTUnwrap(Bundle.main.url(forResource: "cs", withExtension: "lproj"))
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        for presentation in [PlaybackDiagnosticsOverlay.Presentation.mobile, .television] {
            let panel = PlaybackDiagnosticsOverlay(diagnostics: diagnostics, presentation: presentation)
            let text: String
            if presentation == .mobile {
                text = try renderedText(
                    panel.mobileContent(width: 844).frame(width: 844).fixedSize(horizontal: false, vertical: true),
                    locale: "cs"
                )
            } else {
                text = try renderedText(panel.televisionPanel(width: 1280), locale: "cs")
            }
            for key in ["Surround", "Headphones"] {
                let translated = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
                XCTAssertNotEqual(translated, key)
                XCTAssertTrue(normalized(text).contains(normalized(translated)), text)
            }
            XCTAssertTrue(text.contains("AirPlay"), text)
        }
    }

    func testOneRowRespondsToTheEnvironmentLanguageWithoutTranslatingItsValue() throws {
        let row = PlaybackDiagnosticsOverlay.MobileDiagnosticsRow(
            label: Text(LocalizedStringResource("File")),
            value: Text(verbatim: "File")
        )
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        let english = try renderedText(row, locale: "en")
        let czech = try renderedText(row, locale: "cs")
        XCTAssertEqual(normalized(english).components(separatedBy: "file").count - 1, 2, english)
        XCTAssertTrue(normalized(czech).contains("soubor"), czech)
        XCTAssertTrue(normalized(czech).contains("file"), "Provider content must remain verbatim: \(czech)")
    }

    func testAudioProcessingShowsActualPipelineWithoutClaimingReceiverOutput() throws {
        for pipeline in ["TRUEHD Atmos → APAC 7.1.4", "TRUEHD → FLAC bridge", "TRUEHD → EAC3 bridge"] {
            var diagnostics = fixture(mode: .plozzigen)
            diagnostics.audioPipelineDescription = pipeline
            for width in [390.0, 844.0] {
                let panel = PlaybackDiagnosticsOverlay(diagnostics: diagnostics, presentation: .mobile)
                let text = try renderedText(
                    panel.mobileContent(width: width).frame(width: width)
                        .fixedSize(horizontal: false, vertical: true),
                    locale: "en"
                )
                assertAudioProcessing(in: text, pipeline: pipeline)
            }
            let panel = PlaybackDiagnosticsOverlay(diagnostics: diagnostics, presentation: .television)
            let text = try renderedText(
                panel.televisionPanel(width: 1280), locale: "en"
            )
            assertAudioProcessing(in: text, pipeline: pipeline, compact: true)
        }
    }

    private func assertAudioProcessing(in text: String, pipeline: String, compact: Bool = false) {
        let tokens = ["Processing", "System output", "Dolby Atmos", "HDMI", "TRUEHD"] + (compact ? [] : ["Connection"])
        for token in tokens {
            XCTAssertTrue(normalized(text).contains(normalized(token)), text)
        }
        let format = pipeline.contains("APAC") ? "APAC" : (pipeline.contains("FLAC") ? "FLAC" : "EAC3")
        XCTAssertTrue(text.contains(format), text)
        XCTAssertFalse(text.contains("Bridged on-device"), text)
        XCTAssertFalse(normalized(text).contains("not verified"), text)
        XCTAssertFalse(normalized(text).contains("managed by"), text)
        if format == "APAC" { XCTAssertTrue(text.contains("7.1.4"), text) }
    }

    func testUnreportedSystemOutputIsOmittedInsteadOfReplacingItWithAnExpectation() throws {
        var diagnostics = fixture(mode: .plozzigen)
        diagnostics.audioOutput = nil
        diagnostics.audioOutputDescription = "Atmos passthrough expected"
        let panel = PlaybackDiagnosticsOverlay(diagnostics: diagnostics, presentation: .mobile)
        let text = try renderedText(
            panel.mobileContent(width: 844).frame(width: 844).fixedSize(horizontal: false, vertical: true),
            locale: "en"
        )
        for missing in ["System output", "Connection", "expected", "not verified", "managed by"] {
            XCTAssertFalse(normalized(text).contains(normalized(missing)), text)
        }
    }

    func testCompactDiagnosticsKeepPartialMeasurementsIndependent() throws {
        var diagnostics = fixture(mode: .plozzigen)
        diagnostics.audioOutput = .init(connections: [.format("AirPlay")])
        diagnostics.audioPipelineDescription = "TRUEHD → FLAC bridge"
        diagnostics.frameRate = nil
        diagnostics.observedFps = 23
        diagnostics.bufferedSecondsAhead = nil
        diagnostics.engineBufferedSecondsAhead = 45
        diagnostics.videoBitDepth = 10
        diagnostics.hdr = .dolbyVision
        diagnostics.dolbyVisionProfile = 8
        diagnostics.colorTransfer = "arib-std-b67"
        diagnostics.videoRangeType = "DOVIWITHHLG"
        let panel = PlaybackDiagnosticsOverlay(diagnostics: diagnostics)
        let text = try renderedText(panel.televisionPanel(width: 1280), locale: "en")
        for token in ["AirPlay", "FLAC", "23 fps live", "Player", "Engine", "45.0", "P8", "10-bit", "DOVIWITHHLG"] {
            XCTAssertTrue(normalized(text).contains(normalized(token)), text)
        }
        for absent in ["Dolby Atmos", "HDR10", "Healthy", "24.00", "10.0s"] {
            XCTAssertFalse(normalized(text).contains(normalized(absent)), text)
        }
    }

    private func assertLabels(
        in text: String, mode: PlaybackDiagnostics.PlaybackMode, wrapped: Bool = false, compact: Bool = false
    ) throws {
        var labels = commonLabelKeys
        if compact {
            labels.removeAll { ["Codec", "Resolution", "Frame Rate", "Channels", "Sample Rate", "Connection", "Engine buffer"].contains($0) }
        }
        labels += mode == .plozzigen ? ["AVPlayer time", "AVPlayer window"] : ["Position", "Seekable"]
        labels += mode == .transcode ? ["Estimated bitrate", "Video", "Audio", "Container"] : ["Container"]
        let bundleURL = try XCTUnwrap(Bundle.main.url(forResource: "cs", withExtension: "lproj"))
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        for key in labels + ["playback.diagnostics.device"] {
            let translated = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
            if ["File", "Size", "Delivery", "Resolution", "Memory", "playback.diagnostics.device"].contains(key) {
                XCTAssertNotEqual(translated, key, "Czech catalog must translate \(key)")
            }
            let expected = wrapped ? translated.split(separator: " ").map(String.init) : [translated]
            for fragment in expected {
                XCTAssertTrue(normalized(text).contains(normalized(fragment)),
                              "Missing Czech label \(key) (\(translated)): \(text)")
            }
        }
    }

    private func assertMediaContent(in text: String) {
        for content in ["Fixture Server", "Fixture.mkv", "AVPlayer", "HLS", "h264", "HDR10", "HDR", "hvc1", "Dolby Atmos", "HDMI"] {
            XCTAssertTrue(normalized(text).contains(normalized(content)), "Missing verbatim content \(content): \(text)")
        }
    }

    private func fixture(mode: PlaybackDiagnostics.PlaybackMode) -> PlaybackDiagnostics {
        var value = PlaybackDiagnostics(
            videoCodec: "h264", audioCodec: "aac", audioChannels: 2, container: "mkv",
            mode: mode, hdr: .hdr10, engineName: "AVPlayer", frameRate: 24
        )
        value.sourceProvider = .emby
        value.serverName = "Fixture Server"
        value.sourceFileName = "Fixture.mkv"
        value.sourceFileSizeBytes = 5_300_000_000
        value.resolution = .init(width: 720, height: 300)
        value.originalSource = .init(container: "mkv", video: .init(codec: "hevc", width: 3840, height: 2160),
                                     audio: .init(codec: "aac", channels: 2))
        value.streamTransport = PlaybackDiagnostics.streamTransportFacts(url: URL(string: "https://media.example/stream.m3u8"))
        value.videoBitrate = 500_000
        value.videoCodecTag = "hvc1"
        value.colorTransfer = "smpte2084"
        value.audioSampleRate = 48_000
        value.audioBitrate = 128_000
        value.audioOutputDescription = "Stereo"
        value.audioOutput = .init(renderingMode: .format("Dolby Atmos"), connections: [.format("HDMI")])
        value.subtitleDescription = "SubRip"
        value.positionSeconds = 30
        value.durationSeconds = 300
        value.seekableStartSeconds = 0
        value.seekableEndSeconds = 300
        value.playbackState = "Ready"
        value.bufferedSecondsAhead = 10
        value.engineBufferedSecondsAhead = 20
        value.stallCount = 0
        value.droppedVideoFrames = 0
        value.indicatedBitrate = 628_000
        value.observedBitrate = 8_000_000
        value.deviceModel = "iPad"
        value.deviceMemoryBytes = 8_000_000_000
        value.freeDiskBytes = 10_000_000_000
        value.totalDiskBytes = 128_000_000_000
        value.memoryFootprintBytes = 200_000_000
        value.thermalState = .nominal
        value.liveViewModels = 1
        value.liveNativeEngines = 1
        return value
    }

    private func renderedText(_ view: some View, locale: String) throws -> String {
        let renderer = ImageRenderer(content: view
            .environment(\.themePalette, .dark)
            .environment(\.locale, Locale(identifier: locale))
            .background(.black)
        )
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.cgImage)
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = "Diagnostics \(locale)"
        attachment.lifetime = .keepAlways
        add(attachment)
        // Vision downsamples tall or TV-wide panels. Overlapping tiles retain
        // the rendered font size and complete words in both presentations.
        var lines: [String] = []
        for y in stride(from: 0, to: image.height, by: 1000) {
            for x in stride(from: 0, to: image.width, by: 600) {
                let tile = try XCTUnwrap(image.cropping(to: CGRect(
                    x: x, y: y, width: min(1200, image.width - x), height: min(1200, image.height - y)
                )))
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                let supported = try request.supportedRecognitionLanguages()
                request.recognitionLanguages = locale == "cs" && supported.contains("cs-CZ") ? ["cs-CZ", "en-US"] : ["en-US"]
                try VNImageRequestHandler(cgImage: tile).perform([request])
                lines += (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            }
        }
        return lines.joined(separator: " ")
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
#endif
