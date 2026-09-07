#if DEBUG
import Foundation
import XCTest
import zlib
@testable import FeatureLiveTVCore

final class LiveTVXMLTVParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_225_600)

    func testParsesChunksEntitiesOffsetsAndMapsToApplicationChannelID() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="guide.one"><display-name>News HD</display-name></channel>
          <programme channel="guide.one" start="20251231210000 -0500" stop="20251231223000 -0500">
            <title>Tom &amp; Jerry</title>
            <sub-title>Part <![CDATA[One]]></sub-title>
          </programme>
        </tv>
        """
        let channel = makeChannel(id: "app-channel", name: "News HD", guideID: "playlist.id")
        let result = try LiveTVXMLTVParser().parseXML(
            data: Data(xml.utf8),
            channels: [channel],
            now: now
        )

        XCTAssertEqual(result.guideChannelCount, 1)
        XCTAssertEqual(result.matchedChannelCount, 1)
        XCTAssertEqual(result.programCount, 1)
        XCTAssertEqual(result.programs[0].channelID, "app-channel")
        XCTAssertEqual(result.programs[0].title, "Tom & Jerry")
        XCTAssertEqual(result.programs[0].subtitle, "Part One")
        XCTAssertEqual(result.programs[0].start, date("20260101020000 +0000"))
        XCTAssertEqual(result.programs[0].end, date("20260101033000 +0000"))
        XCTAssertEqual(result.coverageStart, result.programs[0].start)
        XCTAssertEqual(result.coverageEnd, result.programs[0].end)
    }

    func testPreservesGuideGapsAndDoesNotFabricateMissingStops() throws {
        let xml = """
        <tv>
          <channel id="gap"><display-name>Gap TV</display-name></channel>
          <programme channel="gap" start="20251231230000 +0000" stop="20260101000000 +0000"><title>First</title></programme>
          <programme channel="gap" start="20260101010000 +0000" stop="20260101020000 +0000"><title>Second</title></programme>
          <programme channel="gap" start="20260101020000 +0000"><title>No Stop</title></programme>
          <programme channel="gap" start="20260101030000 +0000" stop="20260101020000 +0000"><title>Backwards</title></programme>
        </tv>
        """
        let result = try LiveTVXMLTVParser().parseXML(
            data: Data(xml.utf8),
            channels: [makeChannel(id: "gap-app", name: "Gap TV", guideID: "other")],
            now: now
        )
        XCTAssertEqual(result.programs.map(\.title), ["First", "Second"])
        XCTAssertEqual(
            result.programs[1].start.timeIntervalSince(result.programs[0].end),
            3_600
        )
    }

    func testNoMatchingOrCurrentProgramsReportsFeedCoverageHonestly() throws {
        let xml = """
        <tv>
          <channel id="old"><display-name>Old TV</display-name></channel>
          <programme channel="old" start="20200101000000 +0000" stop="20200101010000 +0000"><title>Old</title></programme>
        </tv>
        """
        let result = try LiveTVXMLTVParser().parseXML(
            data: Data(xml.utf8),
            channels: [makeChannel(id: "different", name: "Different", guideID: nil)],
            now: now
        )
        XCTAssertTrue(result.programs.isEmpty)
        XCTAssertEqual(result.matchedChannelCount, 0)
        XCTAssertEqual(result.guideChannelCount, 1)
        XCTAssertEqual(result.programCount, 0)
        XCTAssertEqual(result.coverageStart, date("20200101000000 +0000"))
        XCTAssertEqual(result.coverageEnd, date("20200101010000 +0000"))
    }

    func testMatchedChannelIsReportedEvenWhenItsProgramsAreOutsideTheWindow() throws {
        let xml = """
        <tv>
          <channel id="old"><display-name>Old TV</display-name></channel>
          <programme channel="old" start="20200101000000 +0000" stop="20200101010000 +0000"><title>Old</title></programme>
        </tv>
        """
        let result = try LiveTVXMLTVParser().parseXML(
            data: Data(xml.utf8),
            channels: [makeChannel(id: "old-app", name: "Old TV", guideID: nil)],
            now: now
        )
        XCTAssertEqual(result.matchedChannelCount, 1)
        XCTAssertEqual(result.programCount, 0)
    }

    func testExactIdentitySharesProgramsAcrossStreamVariants() throws {
        let xml = """
        <tv>
          <channel id="station"><display-name>Station</display-name></channel>
          <programme channel="station" start="20260101000000 +0000" stop="20260101010000 +0000"><title>Listing</title></programme>
        </tv>
        """
        let result = try LiveTVXMLTVParser().parseXML(
            data: Data(xml.utf8),
            channels: [
                makeChannel(id: "sd", name: "Station SD", guideID: "station"),
                makeChannel(id: "hd", name: "Station HD", guideID: "station")
            ],
            now: now
        )
        XCTAssertEqual(result.matchedChannelCount, 2)
        XCTAssertEqual(Set(result.programs.map(\.channelID)), ["sd", "hd"])
        XCTAssertEqual(Set(result.programs.map(\.id)).count, 2)
    }

    func testRejectsChannelDeclarationsAfterProgramsRatherThanLosingMatches() {
        let xml = """
        <tv>
          <programme channel="late" start="20260101000000 +0000" stop="20260101010000 +0000"><title>Listing</title></programme>
          <channel id="late"><display-name>Station</display-name></channel>
        </tv>
        """
        XCTAssertThrowsError(try LiveTVXMLTVParser().parseXML(data: Data(xml.utf8), channels: [], now: now))
    }

    func testRejectsDOCTYPEAndMalformedXML() {
        let xml = """
        <?xml version="1.0"?>
        <!DOCTYPE tv [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
        <tv><channel id="x"><display-name>&xxe;</display-name></channel></tv>
        """
        XCTAssertThrowsError(
            try LiveTVXMLTVParser().parseXML(
                data: Data(xml.utf8),
                channels: [],
                now: now
            )
        ) {
            XCTAssertEqual($0 as? LiveTVSourceImportError, .invalidGuide)
        }
        XCTAssertThrowsError(
            try LiveTVXMLTVParser().parseXML(
                data: Data("<tv><channel>".utf8),
                channels: [],
                now: now
            )
        )
    }

    func testGzipCorruptionAndExpansionLimitAreRejected() throws {
        XCTAssertThrowsError(
            try LiveTVXMLTVParser().parse(
                gzipData: Data([0x1f, 0x8b, 0x00, 0x01]),
                channels: [],
                now: now
            )
        ) {
            XCTAssertEqual($0 as? LiveTVSourceImportError, .invalidGuide)
        }

        let oversizedXML = "<tv><!--" + String(repeating: "x", count: 1_024) + "--></tv>"
        let compressed = try gzip(Data(oversizedXML.utf8))
        XCTAssertThrowsError(
            try LiveTVXMLTVParser(maximumExpandedBytes: 128).parse(
                gzipData: compressed,
                channels: [],
                now: now
            )
        )
    }

    func testCancellationPropagates() async {
        let xml = "<tv>" + (0..<20_000).map {
            #"<channel id="\#($0)"><display-name>Channel \#($0)</display-name></channel>"#
        }.joined() + "</tv>"
        let task = Task {
            try LiveTVXMLTVParser().parseXML(
                data: Data(xml.utf8),
                channels: [],
                now: now
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? LiveTVSourceImportError, .cancelled)
        }
    }

    func testDateParserRejectsInvalidFieldsAndPreservesOffsets() {
        XCTAssertNil(XMLTVDateParser.date(from: "20261301000000 +0000"))
        XCTAssertNil(XMLTVDateParser.date(from: "20260101000000 +2460"))
        XCTAssertNil(XMLTVDateParser.date(from: String(repeating: "\u{06F1}", count: 14) + " +0000"))
        XCTAssertEqual(
            XMLTVDateParser.date(from: "20260101010000 +0100"),
            XMLTVDateParser.date(from: "20260101000000 +0000")
        )
    }
    private func makeChannel(
        id: String,
        name: String,
        guideID: String?
    ) -> LiveTVPrototypeChannel {
        LiveTVPrototypeChannel(
            id: id,
            number: 1,
            name: name,
            category: "Test",
            symbol: "tv.fill",
            accent: 0,
            source: .iptv,
            tagline: "Test",
            streamURL: URL(string: "https://example.com/live.m3u8"),
            guideID: guideID
        )
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss Z"
        return formatter.date(from: value)!
    }

    private func gzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(
            &stream,
            Z_BEST_SPEED,
            Z_DEFLATED,
            15 + 16,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else {
            throw LiveTVSourceImportError.invalidGuide
        }
        defer { deflateEnd(&stream) }

        var result = Data()
        var input = [UInt8](data)
        let status = input.withUnsafeMutableBytes { bytes -> Int32 in
            stream.next_in = bytes.baseAddress!.assumingMemoryBound(to: Bytef.self)
            stream.avail_in = uInt(bytes.count)
            repeat {
                var output = [UInt8](repeating: 0, count: 64 * 1_024)
                let code = output.withUnsafeMutableBytes { outputBytes -> Int32 in
                    stream.next_out = outputBytes.baseAddress!
                        .assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(outputBytes.count)
                    return deflate(&stream, Z_FINISH)
                }
                let produced = output.count - Int(stream.avail_out)
                result.append(contentsOf: output.prefix(produced))
                if code == Z_STREAM_END { return code }
                if code != Z_OK { return code }
            } while true
        }
        guard status == Z_STREAM_END else {
            throw LiveTVSourceImportError.invalidGuide
        }
        return result
    }
}
#endif
