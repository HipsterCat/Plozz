import CoreModels
@testable import CoreUI
import XCTest

@MainActor
final class PlaybackSourceMenuPerformanceTests: XCTestCase {
    func testPerformanceVersionPresentation() async throws {
        try PerformanceProbe.requireEnabled()
        let versions = (0..<32).map { index in
            MediaVersion(
                id: "file-\(index)",
                name: "A.Movie.With.A.Long.Release.Name.2026.2160p.WEB-DL.DDP5.1.HEVC-Group\(index)",
                fileName: "A.Movie.With.A.Long.Release.Name.2026.Extended.Directors.Cut.2160p.mkv",
                height: 2160, bitrate: 40_000_000, sizeBytes: 12_000_000_000,
                duration: 7_200, videoRange: "HDR10", audioChannels: 6
            )
        }
        let expected = versions.map { version in
            let title = version.displayLabel
            let facts = Set((title ?? "").components(separatedBy: " · "))
            return (title, version.menuFacts.filter { !facts.contains($0) })
        }
        try await PerformanceProbe.measure(self, scenario: "source-menu-version-presentation") {
            var rows = 0
            for _ in 0..<32 {
                for (index, version) in versions.enumerated() {
                    let presentation = MediaVersion.PickerPresentation(version)
                    XCTAssertEqual(presentation.title, expected[index].0)
                    XCTAssertEqual(presentation.supplementalFacts, expected[index].1)
                    rows += 1
                }
            }
            return ["versions": versions.count, "menuUpdates": 32, "presentedRows": rows]
        }
    }

    func testVersionPresentationPreservesLabelsFactsAndUnknownFallback() {
        for name: String? in [nil, "", "Server Copy", "WEB-DL", "Extended Remux", "5.1", "2h"] {
            for height: Int? in [nil, 1080, 2160] {
                for edition: String? in [nil, "", "  ", "Director's Cut"] {
                    let version = MediaVersion(
                        id: "file", name: name, fileName: "Movie.Theatrical.mkv", edition: edition,
                        height: height, bitrate: 20_000_000, sizeBytes: 8_000_000_000,
                        duration: 7_200, videoRange: "HDR10", audioChannels: 6
                    )
                    let title = version.displayLabel
                    let facts = Set((title ?? "").components(separatedBy: " · "))
                    let result = MediaVersion.PickerPresentation(version)
                    XCTAssertEqual(result.title, title)
                    XCTAssertEqual(result.supplementalFacts, version.menuFacts.filter { !facts.contains($0) })
                }
            }
        }
        XCTAssertNil(MediaVersion.PickerPresentation(MediaVersion(id: "unknown")).title)
        XCTAssertEqual(MediaVersion.PickerPresentation(MediaVersion(id: "unknown")).supplementalFacts, [])
    }
}
