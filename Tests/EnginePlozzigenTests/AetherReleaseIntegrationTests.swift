import AetherEngine
import CoreModels
import FeaturePlayback
import XCTest
@testable import EnginePlozzigen

final class AetherReleaseIntegrationTests: XCTestCase {
    func testResolvedEngineAndSourceCreditIdentifyPinnedMainIntegration() throws {
        XCTAssertEqual(AetherEngine.version, "7.44.0")
        let credit = try XCTUnwrap(PlozzAttributions.entries.first { $0.title == "AetherEngine" })
        XCTAssertTrue(credit.detail.contains(
            "https://github.com/brandomoore/AetherEngine/tree/86af70ddfe7bcde27e06356dc7aa81e8997d43c4"
        ))
    }

    @MainActor
    func testPlaybackLabelUsesTheLinkedEngineVersion() throws {
        let engine = try PlozzigenVideoEngine()
        defer { engine.stop() }
        XCTAssertEqual(engine.displayName, "AetherEngine v\(AetherEngine.version)")
    }

    func testPreviouslyIncludedOptionalComponentsRemainBuiltIn() {
        for component in [
            AetherEngine.OptionalComponent.trueHDObjectAudio,
            .dtsxObjectAudio, .dualLayerDolbyVision, .dolbyVisionStillReshaping
        ] {
            XCTAssertTrue(component.isBuiltIn, "\(component.traitName) must not silently become a no-op")
        }
    }

    func testEngineLivesInItsOwnDynamicFramework() {
        let engineBundle = Bundle(for: AetherEngine.self)
        XCTAssertEqual(engineBundle.bundleURL.lastPathComponent, "AetherEngine.framework")
        XCTAssertNotEqual(engineBundle.bundleURL, Bundle.main.bundleURL)
    }

    func testUpstreamDefaultsRemainOptIn() {
        let options = LoadOptions()
        XCTAssertEqual(options.objectAudioRendering, .off)
        XCTAssertFalse(options.progressiveSegmentDelivery)
        XCTAssertFalse(options.preferDualLayerDolbyVision)
        XCTAssertFalse(PlozzigenVideoEngine.onDemandLoadOptions(audioChannels: 8).preferDualLayerDolbyVision)
    }

    func testFELPreferenceReachesOnDemandOptionsWithoutDisablingAudioForOtherSources() {
        for enabled in [false, true] {
            let options = PlozzigenVideoEngine.onDemandLoadOptions(
                audioChannels: 8, dolbyVisionFELEnabled: enabled
            )
            XCTAssertEqual(options.preferDualLayerDolbyVision, enabled)
            XCTAssertEqual(options.dolbyVisionHandling, .automatic)
            XCTAssertFalse(options.isLive)
            XCTAssertTrue(options.matchContentEnabled)
            XCTAssertEqual(options.audioBridgeMode, .lossless)
            #if os(tvOS)
            if #available(tvOS 26.0, *) {
                XCTAssertEqual(options.objectAudioRendering, .apac(.l714))
            }
            #else
            XCTAssertEqual(options.objectAudioRendering, .off)
            #endif
        }
    }

    @MainActor
    func testResolvedRequestCarriesFELPreferenceIntoActualAdapterOptions() throws {
        let engine = try PlozzigenVideoEngine()
        defer { engine.stop() }
        for provider in [ProviderKind.plex, .jellyfin, .emby, .mediaShare, .silo] {
            for enabled in [false, true] {
                var request = PlaybackRequest(
                    item: MediaItem(id: "fel", title: "FEL fixture", kind: .movie),
                    streamURL: URL(string: "https://media.example/movie.mkv")!
                )
                request.sourceProvider = provider
                request.dolbyVisionFELEnabled = enabled
                XCTAssertEqual(engine.onDemandLoadOptions(for: request).preferDualLayerDolbyVision, enabled)
            }
        }
    }

    func testLivePlaybackNeverRequestsFEL() {
        for suffix in ["ts", "m3u8", ""] {
            let options = PlozzigenVideoEngine.liveLoadOptions(
                httpHeaders: [:], url: URL(string: "https://media.example/live.\(suffix)")!
            )
            XCTAssertTrue(options.isLive)
            XCTAssertFalse(options.preferDualLayerDolbyVision)
        }
    }

    func testPlozzAutomaticallyRequestsSpatialAudioOnSupportedTVOS() {
        for channels in [0, 2, 6, 8] {
            let options = PlozzigenVideoEngine.onDemandLoadOptions(audioChannels: channels)
            #if os(tvOS)
            if #available(tvOS 26.0, *) {
                XCTAssertEqual(options.objectAudioRendering, .apac(.l714))
            } else {
                XCTAssertEqual(options.objectAudioRendering, .off)
            }
            #else
            XCTAssertEqual(options.objectAudioRendering, .off)
            #endif
            XCTAssertEqual(options.audioBridgeMode, channels > 6 ? .lossless : .surroundCompat)
            XCTAssertTrue(options.matchContentEnabled)
            XCTAssertFalse(options.isLive)
            XCTAssertFalse(options.progressiveSegmentDelivery)
        }
    }

    func testSharedLivePlayersAndMutedPreviewsKeepTheOrdinaryAudioBridge() {
        for policy in [
            LiveChannelOutputPolicy(isAudible: false),
            .init(isAudible: true, sharesAudioSession: true),
            .init(isAudible: false, sharesAudioSession: true, suppressesDisplayMatching: true)
        ] {
            let options = PlozzigenVideoEngine.onDemandLoadOptions(
                audioChannels: 8, dolbyVisionFELEnabled: true, outputPolicy: policy
            )
            XCTAssertEqual(options.objectAudioRendering, .off)
            XCTAssertFalse(options.preferDualLayerDolbyVision)
            XCTAssertEqual(options.audioBridgeMode, .lossless)
            XCTAssertEqual(options.suppressDisplayCriteria, policy.suppressesDisplayMatching)
            XCTAssertEqual(options.matchContentEnabled, !policy.suppressesDisplayMatching)
        }
    }

    func testDisplaySuppressedPreviewDoesNotRequestFEL() {
        let options = PlozzigenVideoEngine.onDemandLoadOptions(
            audioChannels: 8, dolbyVisionFELEnabled: true,
            outputPolicy: .init(isAudible: true, suppressesDisplayMatching: true)
        )
        XCTAssertFalse(options.preferDualLayerDolbyVision)
    }

    func testDisablingSpatialAudioKeepsTheExistingChannelBridge() {
        for channels in [0, 2, 6, 8] {
            let options = PlozzigenVideoEngine.onDemandLoadOptions(
                audioChannels: channels, trueHDAtmosEnabled: false
            )
            XCTAssertEqual(options.objectAudioRendering, .off)
            XCTAssertEqual(options.audioBridgeMode, channels > 6 ? .lossless : .surroundCompat)
            XCTAssertTrue(options.matchContentEnabled)
            XCTAssertFalse(options.isLive)
        }
    }

    func testTrueHDLegalCreditIncludesSourceAndBothLicenses() throws {
        let credit = try XCTUnwrap(PlozzAttributions.entries.first { $0.title == "LibTrueHD" })
        XCTAssertTrue(credit.detail.contains(
            "https://github.com/superuser404notfound/LibTrueHD/tree/3.0.0"
        ))
        XCTAssertTrue(credit.detail.contains("Quick104"))
        XCTAssertTrue(credit.detail.contains("Rainbaby"))
        XCTAssertTrue(credit.detail.contains("LibTrueHDNotices.txt"))
        XCTAssertEqual(Set(credit.licenses.map(\.label)), ["MIT", "Apache-2.0"])
    }

    func testDTSXRemainsBuiltInWithoutTheRetiredLibDTSXCredit() {
        XCTAssertTrue(AetherEngine.OptionalComponent.dtsxObjectAudio.isBuiltIn)
        XCTAssertFalse(PlozzAttributions.entries.contains { $0.title == "LibDTSX" })
        XCTAssertTrue(PlozzAttributions.entries.contains { $0.title == "FFmpeg" })
    }

    func testReleasedProbeCancellationAPIIsAvailable() {
        let cancellation = ProbeCancellation()
        XCTAssertFalse(cancellation.isCancelled)
        cancellation.cancel()
        XCTAssertTrue(cancellation.isCancelled)
    }

    func testInformationalRemoteHLSTracksDoNotBecomeNonworkingMenuActions() {
        let tracks = [
            TrackInfo(id: 400_000, name: "English", codec: "aac", language: "en", channels: 2, isDefault: true),
            TrackInfo(id: 400_001, name: "French", codec: "aac", language: "fr", channels: 2, isDefault: false)
        ]
        XCTAssertTrue(PlozzigenVideoEngine.selectableAudioTracks(from: tracks, route: .remoteBypass).isEmpty)
    }

    func testSelectableRoutesKeepAudioTrackIdentityAndFlags() {
        let tracks = [
            TrackInfo(
                id: 3, name: "English", codec: "eac3", language: "en",
                channels: 6, isDefault: true, isCommentary: true, isAtmos: true
            )
        ]
        for route in [VideoRoute.loopback, .software, .audio] {
            let mapped = PlozzigenVideoEngine.selectableAudioTracks(from: tracks, route: route)
            XCTAssertEqual(mapped.map(\.id), [3])
            XCTAssertEqual(mapped.first?.language, "en")
            XCTAssertEqual(mapped.first?.channels, 6)
            XCTAssertEqual(mapped.first?.isAtmos, true)
            XCTAssertEqual(mapped.first?.isCommentary, true)
            XCTAssertEqual(mapped.first?.isDefault, true)
        }
    }
}
