import XCTest
@testable import CoreModels

final class WebVTTColorStylesTests: XCTestCase {
    private let darkGreen = SubtitleColor(red: 0, green: 128.0 / 255, blue: 0)
    private let red = SubtitleColor(red: 1, green: 0, blue: 0)
    private let blue = SubtitleColor(red: 0, green: 0, blue: 1)

    private func parse(_ payload: String, style: String = "") throws -> SubtitleText {
        let header = style.isEmpty ? "WEBVTT\n\n" : "WEBVTT\n\nSTYLE\n\(style)\n\n"
        let file = header + "00:00:01.000 --> 00:00:03.000\n\(payload)\n"
        let stream = SubtitleCueParser.parse(file)
        XCTAssertEqual(stream.metadata.format, .webVTT)
        XCTAssertEqual(stream.cues, SubtitleCueParser.parseCues(file))
        let cue = try XCTUnwrap(stream.cues.first)
        guard case .text(let text) = cue.body else {
            XCTFail("Expected a text cue")
            throw NSError(domain: "WebVTTColorStylesTests", code: 1)
        }
        return text
    }

    func testUnstyledCaptionGreenAndLimeAreBright() throws {
        let text = try parse("<c.green>Caller</c> <c.lime>Friend</c>")
        XCTAssertEqual(text.string, "Caller Friend")
        XCTAssertEqual(text.runs?.compactMap(\.color), [.green, .green])
        XCTAssertNil(text.runs?[1].color)
    }

    func testCCExtractorGreenClassAndBackgroundDoNotConfuseForeground() throws {
        let text = try parse("<c.green.bg_green>Caller</c>: plain", style: """

        /* CCExtractor's styled 608 export uses these class names. */
        ::cue { color: white; background-color: black; }
        ::cue(c.green) { color: lime; }
        ::cue(c.bg_green) { background-color: lime; }
        """)
        XCTAssertEqual(text.runs?.map(\.text), ["Caller", ": plain"])
        XCTAssertEqual(text.runs?.map(\.color), [.green, .white])
        let backgroundOnly = try parse("<c.bg_green>Uncolored</c>")
        XCTAssertNil(backgroundOnly.runs)
    }

    func testExplicitDarkGreenOverridesTheCompatibilityAlias() throws {
        for selector in ["::cue(.green)", "::cue(c.green)"] {
            for value in ["green", "#008000", "rgb(0,128,0)", "rgb(0 128 0)"] {
                let text = try parse("<c.green>Caller</c>", style: "\(selector) { color: \(value); }")
                XCTAssertEqual(text.runs?.first?.color, darkGreen, "\(selector) \(value)")
            }
        }
    }

    func testSubtitleEditRGBStylePreservesTheSelectedSwatch() throws {
        for value in ["lime", "#00FF00", "#0f0", "rgb(0,255,0)", "rgb(0%,100%,0%)"] {
            let text = try parse("<c.speaker>Caller</c>", style: "::cue(.speaker) { color: \(value); }")
            XCTAssertEqual(text.runs?.first?.color, .green, value)
        }
        let limegreen = try parse("<c.speaker>Caller</c>", style: "::cue(.speaker) { color: limegreen; }")
        XCTAssertEqual(limegreen.runs?.first?.color, SubtitleColor(red: 50.0 / 255, green: 205.0 / 255, blue: 50.0 / 255))
    }

    func testAlphaAndNumericColorsAreNotRemappedToThePreset() throws {
        for value in ["rgba(0,128,0,0.5)", "rgb(0 128 0 / 50%)"] {
            let text = try parse("Caller", style: "::cue { color: \(value); }")
            XCTAssertEqual(text.runs?.first?.color, SubtitleColor(red: 0, green: 128.0 / 255, blue: 0, alpha: 0.5))
        }
        for value in ["#0f08", "#00ff0088"] {
            let text = try parse("Caller", style: "::cue { color: \(value); }")
            XCTAssertEqual(text.runs?.first?.color, SubtitleColor(red: 0, green: 1, blue: 0, alpha: 136.0 / 255))
        }
    }

    func testNestedTagsRestoreTheirParentAndRootColors() throws {
        let text = try parse("A<c.green>B<i>C</i><c.sign>D</c>E</c>F", style: """
        ::cue { color: green; }
        ::cue(.sign) { color: red; }
        """)
        XCTAssertEqual(text.string, "ABCDEF")
        XCTAssertTrue(text.isItalic)
        XCTAssertEqual(text.runs?.map(\.text), ["A", "BC", "D", "E", "F"])
        XCTAssertEqual(text.runs?.map(\.color), [darkGreen, .green, red, .green, darkGreen])
    }

    func testSpecificitySourceOrderAndImportantDeclarations() throws {
        let text = try parse("<c.green.speaker>Caller</c>", style: """
        ::cue(c.green.speaker) { color: blue; }
        ::cue(.green) { color: red; }
        """)
        XCTAssertEqual(text.runs?.first?.color, blue)

        let important = try parse("<c.green.speaker>Caller</c>", style: """
        ::cue(c.green.speaker) { color: blue; }
        ::cue(.green) { color: red !important; color: lime; }
        ::cue(.green) { COLOR: green ! IMPORTANT; }
        """)
        XCTAssertEqual(important.runs?.first?.color, darkGreen)
    }

    func testSelectorListsCompoundClassesAndCaseSensitiveNames() throws {
        let text = try parse("<c.Speaker.green>A</c> <c.speaker.green>B</c> <v.Other>C</v>", style: """
        ::cue(.Speaker.green), ::cue(v.Other) { color: red; }
        """)
        XCTAssertEqual(text.runs?.compactMap(\.color), [red, .green, red])
    }

    func testExplicitInheritanceOverridesClassDefaults() throws {
        for value in ["inherit", "unset", "currentColor"] {
            let text = try parse("<c.green>Caller</c>", style: """
            ::cue { color: red; }
            ::cue(.green) { color: \(value); }
            """)
            XCTAssertEqual(text.runs?.first?.color, red)
        }
    }

    func testUnsupportedRulesAndQuotedPropertiesCannotLeakColors() throws {
        let text = try parse("<c.green>Caller</c>", style: """
        @import url("https://example.invalid/colors.css");
        @media print { ::cue(.green) { color: red; } }
        ::cue(.parent .green) { color: red; }
        ::cue(v[voice="Caller"]) { color: red; }
        ::cue(.green), .unsupported { color: red; }
        ::cue(.green) { background-color: red; font-family: "name;color:red;"; }
        """)
        XCTAssertEqual(text.runs?.first?.color, .green)
    }

    func testInvalidColorsDoNotReplaceAnEarlierValidDeclaration() throws {
        for invalid in ["invalid", "008000", "rgb(nan,0,0)", "rgb(inf,0,0)",
                        "rgb(0,,0)", "rgb(0,50%,0)", "rgb(0 128 0 /)", "#xyz", "#12345"] {
            let text = try parse("<c.green>Caller</c>", style: """
            ::cue(.green) { color: red; color: \(invalid); }
            """)
            XCTAssertEqual(text.runs?.first?.color, red, invalid)
        }
    }

    func testMultipleStyleBlocksAndCommentsKeepTheirOrder() throws {
        let text = try parse("<c.green>Caller</c>", style: """
        ::cue(.green) { color: red; }

        NOTE ::cue(.green) { color: blue; }

        STYLE
        ::cue(.green) { /* authored color */ color: green; }
        """)
        XCTAssertEqual(text.runs?.first?.color, darkGreen)
    }

    func testStylesAfterTheFirstCueAreNotAppliedOrShown() throws {
        let file = """
        WEBVTT

        00:00:01.000 --> 00:00:02.000
        <c.green>First</c>

        STYLE
        ::cue(.green) { color: red; }

        00:00:03.000 --> 00:00:04.000
        <c.green>Second</c>
        """
        let cues = SubtitleCueParser.parseCues(file)
        XCTAssertEqual(cues.map(\.text), ["First", "Second"])
        for cue in cues {
            guard case .text(let text) = cue.body else { return XCTFail("Expected text") }
            XCTAssertEqual(text.runs?.first?.color, .green)
        }
    }

    func testNoStylesAndUnknownClassesLeaveViewerColorUntouched() throws {
        let text = try parse("<c.speaker><i>Plain</i></c>")
        XCTAssertEqual(text.string, "Plain")
        XCTAssertNil(text.runs)
        XCTAssertTrue(text.isItalic)
        XCTAssertNil(text.layout)
    }

    func testSubRipDoesNotAcquireWebVTTStyleRulesOrAliases() throws {
        let file = """
        STYLE
        ::cue { color: red; }

        1
        00:00:01,000 --> 00:00:02,000
        <font color="green">Caller</font>
        """
        let cue = try XCTUnwrap(SubtitleCueParser.parseCues(file).first)
        guard case .text(let text) = cue.body else { return XCTFail("Expected text") }
        XCTAssertEqual(text.runs?.first?.color, darkGreen)
    }
}
