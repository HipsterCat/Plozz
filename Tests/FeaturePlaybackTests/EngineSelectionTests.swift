#if canImport(AVFoundation)
import XCTest
import CoreModels
@testable import FeaturePlayback

final class EngineSelectionTests: XCTestCase {
    private func request(
        url: URL = URL(string: "https://example.test/movie.mp4")!,
        transcoding: Bool = false,
        metadata: MediaSourceMetadata? = nil
    ) -> PlaybackRequest {
        PlaybackRequest(
            item: MediaItem(id: "m1", title: "Movie", kind: .movie),
            streamURL: url, isTranscoding: transcoding, sourceMetadata: metadata
        )
    }

    func testAllKnownVideoFormatsAndMissingMetadataUseAether() {
        for container in PlozzigenMediaFormats.containers {
            for codec in PlozzigenMediaFormats.videoCodecs {
                let value = request(metadata: .init(
                    container: container, video: .init(codec: codec),
                    audio: .init(codec: "pcm_s16le")
                ))
                XCTAssertEqual(
                    EngineSelection.route(request: value, plozzigenAvailable: true),
                    .plozzigen, "\(container)/\(codec)"
                )
            }
        }
        XCTAssertEqual(EngineSelection.route(request: request(), plozzigenAvailable: true), .plozzigen)
    }

    func testServerChosenHLSAndQualityLimitsDoNotChangeEngineOwnership() {
        var value = request(url: URL(string: "https://example.test/master.m3u8")!, transcoding: true)
        value.isManifestStream = true
        XCTAssertEqual(EngineSelection.route(request: value, plozzigenAvailable: true), .plozzigen)
        value.streamingOptions = .init(quality: .hd720)
        XCTAssertEqual(EngineSelection.route(request: value, plozzigenAvailable: true), .plozzigen)
        XCTAssertEqual(EngineSelection.route(request: value, plozzigenAvailable: false), .native)
    }

    func testSourceProfileAndSubtitleClassDoNotReintroduceNativeFormatGates() {
        for profile in [5, 7, 8] {
            var value = request(metadata: .init(
                container: "mp4",
                video: .init(codec: "hevc", videoRangeType: "DOVI", dolbyVisionProfile: profile),
                audio: .init(codec: "truehd")
            ))
            for bitmap in [false, true] {
                value.subtitleTracks = [.init(
                    id: 1, kind: .subtitle, displayTitle: "English", language: "en",
                    isImageBasedSubtitle: bitmap
                )]
                XCTAssertEqual(EngineSelection.route(request: value, plozzigenAvailable: true), .plozzigen)
            }

        }
    }

    func testServerHEVCInitializationRepairKeepsItsAVAssetLoader() {
        var value = request(url: URL(string: "https://example.test/master.m3u8")!, transcoding: true)
        value.isManifestStream = true
        value.streamingOptions = .init(quality: .hd720)
        value.negotiatedStreamingVideoCodec = .hevc
        XCTAssertEqual(EngineSelection.route(request: value, plozzigenAvailable: true), .native)
        value.isTranscoding = false
        XCTAssertEqual(EngineSelection.route(request: value, plozzigenAvailable: true), .plozzigen)
    }

    func testNativeOnlyHostRetainsNativePlayback() {
        XCTAssertEqual(EngineSelection.route(request: request(), plozzigenAvailable: false), .native)
    }

    func testSeparateTrailerAudioKeepsItsNativeComposition() {
        var value = request()
        value.externalAudioURL = URL(string: "https://example.test/audio.m4a")!
        XCTAssertEqual(EngineSelection.route(request: value, plozzigenAvailable: true), .native)
    }

    func testDownloadedFilesUseAetherButMissingAssetPackageStaysNative() {
        for suffix in ["mp4", "mkv", "ts"] {
            let value = request(url: URL(fileURLWithPath: "/downloads/movie.\(suffix)"))
            XCTAssertEqual(EngineSelection.route(request: value, plozzigenAvailable: true), .plozzigen)
        }
        XCTAssertEqual(EngineSelection.route(
            request: request(url: URL(fileURLWithPath: "/downloads/movie.movpkg")),
            plozzigenAvailable: true
        ), .native)
    }

    func testDistinguishesAssetPackageFromLegacyProgressiveMovpkgFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("asset.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("legacy.movpkg")
        try Data("matroska".utf8).write(to: file)
        XCTAssertEqual(EngineSelection.route(request: request(url: package), plozzigenAvailable: true), .native)
        XCTAssertEqual(EngineSelection.route(request: request(url: file), plozzigenAvailable: true), .plozzigen)
    }

    func testNetworkFileNeverReachesNativeURLLoader() throws {
        let identity = try RemoteFileIdentity(kind: .strongETag, value: "\"movie-v1\"")
        let representation = try RemoteFileRepresentation(size: 1_024, identity: identity, consistency: .stronglyBound)
        let locator = try NetworkFileLocator(
            accountID: "account", sourceID: "source", credentialRevision: CredentialRevision(),
            relativePath: "Movies/Movie.mkv", representation: representation,
            formatHint: MediaFormatHint(container: "mkv", mimeType: "video/x-matroska")
        )
        var value = request()
        value.playbackSource = .networkFile(locator)
        for available in [false, true] {
            XCTAssertEqual(EngineSelection.route(request: value, plozzigenAvailable: available), .plozzigen)
        }
    }
}
#endif
