import XCTest
@testable import CoreModels

final class EngineRoutingTests: XCTestCase {
    func testLinkedFormatFamiliesIncludeTheirAudioAndContainer() {
        for (container, video, audio) in [
            ("mp4", "h264", "pcm_s16le"),
            ("mkv", "hevc", "truehd"),
            ("avi", "mpeg4", "mp3"),
            ("mpegts", "mpeg2video", "mp2"),
            ("wmv", "wmv3", "wmapro"),
            ("flv", "vp6f", "nellymoser"),
            ("rmvb", "rv40", "cook"),
            ("3gp", "h263", "amr_nb"),
            ("ogg", "theora", "vorbis")
        ] {
            XCTAssertTrue(PlozzigenMediaFormats.supports(container: container))
            XCTAssertTrue(PlozzigenMediaFormats.supports(videoCodec: video))
            XCTAssertTrue(PlozzigenMediaFormats.supports(audioCodec: audio))
        }
    }

    func testNegotiationDoesNotClaimUnlinkedCodecsOrDASH() {
        XCTAssertFalse(PlozzigenMediaFormats.supports(container: "dash"))
        XCTAssertFalse(PlozzigenMediaFormats.supports(videoCodec: "flashsv"))
        XCTAssertFalse(PlozzigenMediaFormats.supports(videoCodec: "unknown"))
        XCTAssertFalse(PlozzigenMediaFormats.supports(audioCodec: "unknown"))
    }

    func testProviderAliasesAndCaseAreAccepted() {
        for codec in ["H265", "AVC", "av01", "vc-1", "mpeg2"] {
            XCTAssertTrue(PlozzigenMediaFormats.supports(videoCodec: codec))
        }
        for codec in ["PCM", "lpcm", "dca-ma", "DTS-HD", "ec3"] {
            XCTAssertTrue(PlozzigenMediaFormats.supports(audioCodec: codec))
        }
    }
}
