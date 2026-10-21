import Foundation
import XCTest
@testable import CoreUI
@testable import TestSupportPerformance

final class PosterPreviewAdmissionTests: XCTestCase {
    @MainActor
    func testPerformanceOverlappingPosterWindows() async throws {
        try PerformanceProbe.requireEnabled()
        let count = 181
        let sources = try (0..<4).map { provider in
            try (0..<count).map { index in
                let path = switch provider {
                case 0: "jellyfin.example.test/Items/\(index)/Images/Primary?maxWidth=2000&quality=90"
                case 1: "emby.example.test/Items/\(index)/Images/Primary?maxWidth=2000&quality=90"
                case 2: "plex.example.test/photo/:/transcode?url=%2Flibrary%2Fmetadata%2F\(index)%2Fthumb&width=2000&height=3000&minSize=1"
                default: "image.tmdb.org/t/p/original/poster-\(index).jpg"
                }
                return try XCTUnwrap(URL(string: "https://\(path)"))
            }
        }
        try await PerformanceProbe.measure(self, scenario: "poster-preview-admission") {
            var visits = 0
            var checks = 0
            var queued = 0
            for urls in sources {
                for direction in [1, -1] {
                    var prefetchedIDs = Set<String>()
                    var admitted: [Int] = []
                    let traversal = direction > 0 ? Array(0..<count) : Array((0..<count).reversed())
                    for index in traversal {
                        let window = MediaRowPrefetchWindow.indices(
                            from: index, direction: direction, count: count,
                            lookahead: MediaRowPrefetchWindow.previewArtworkLookahead
                        )
                        for _ in 0..<3 {
                            for candidate in window {
                                visits += 1
                                func isDistinct() -> Bool {
                                    checks += 1
                                    return ArtworkImageVariant.posterPreview.hasDistinctRequestURL(
                                        from: .posterCard, for: urls[candidate]
                                    )
                                }
                                if MediaArtworkPrefetchPolicy.claimPreview(
                                    for: String(candidate), prefetchedIDs: &prefetchedIDs,
                                    isDistinct: isDistinct()
                                ) {
                                    admitted.append(candidate)
                                    queued += 1
                                }
                            }
                        }
                    }
                    XCTAssertEqual(admitted, traversal, "Duplicate suppression must preserve the complete nearest-first queue.")
                }
            }
            XCTAssertEqual(queued, count * sources.count * 2)
            return ["candidateVisits": visits, "distinctURLChecks": checks, "queuedPreviews": queued]
        }
    }
}
