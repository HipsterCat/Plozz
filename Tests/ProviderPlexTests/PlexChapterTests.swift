import CoreModels
import Foundation
import XCTest
@testable import ProviderPlex

final class PlexChapterTests: XCTestCase {
    func testPlaybackRequestsChaptersAndMapsMillisecondsAndArtwork() async throws {
        let (provider, http) = fixture(chapters: """
        [{"startTimeOffset":300500,"tag":" Middle ","thumb":"/library/metadata/movie/chapter/1"},
         {"startTimeOffset":0},
         {"startTimeOffset":300500,"tag":"Duplicate"},
         {"startTimeOffset":-10},
         {"tag":"Missing position"},
         {"startTimeOffset":600000}]
        """)
        let request = try await provider.playbackInfo(for: "movie")
        XCTAssertEqual(request.chapters.map(\.start), [0, 300.5])
        XCTAssertNil(request.chapters[0].title)
        XCTAssertNil(request.chapters[0].imageURL)
        XCTAssertEqual(request.chapters[1].title, "Middle")
        let image = try XCTUnwrap(request.chapters[1].imageURL)
        XCTAssertEqual(image.host, "fixture.test")
        XCTAssertEqual(image.path, "/plex/photo/:/transcode")
        XCTAssertTrue(http.queryItems(forPathSuffix: "/metadata/movie")?.contains(
            URLQueryItem(name: "includeChapters", value: "1")
        ) == true)
    }

    func testAbsentAndEmptyChaptersLeavePlaybackAvailable() async throws {
        for chapters in ["null", "[]"] {
            let (provider, _) = fixture(chapters: chapters)
            let request = try await provider.playbackInfo(for: "movie")
            XCTAssertTrue(request.chapters.isEmpty)
            XCTAssertNotNil(request.playbackSource)
        }
    }

    private func fixture(chapters: String) -> (PlexProvider, StubHTTPClient) {
        let http = StubHTTPClient()
        http.stub(pathSuffix: "/library/metadata/movie", json: """
        {"MediaContainer":{"Metadata":[{
          "ratingKey":"movie","type":"movie","title":"Movie","duration":600000,
          "Chapter":\(chapters),
          "Media":[{"id":1,"container":"mp4","videoCodec":"h264","audioCodec":"aac",
            "Part":[{"id":2,"key":"/library/parts/2/file.mp4","container":"mp4","Stream":[]}]}]
        }]}}
        """)
        let provider = PlexProvider(session: .init(
            server: .init(id: "server", name: "Server", baseURL: URL(string: "https://fixture.test/plex")!, provider: .plex),
            userID: "user", userName: "User", deviceID: "device", accessToken: "fixture"
        ), http: http)
        return (provider, http)
    }
}
