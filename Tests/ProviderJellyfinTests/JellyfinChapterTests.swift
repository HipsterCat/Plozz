import CoreModels
import Foundation
import XCTest
@testable import ProviderJellyfin

final class JellyfinChapterTests: XCTestCase {
    func testBothProvidersMapChaptersWithoutTurningSkipMarkersIntoChapters() async throws {
        for kind in [ProviderKind.jellyfin, .emby] {
            let provider = fixture(kind: kind, chapters: """
            [{"StartPositionTicks":0,"Name":"Opening","ImageTag":"first"},
             {"StartPositionTicks":100000000,"MarkerType":"IntroStart"},
             {"StartPositionTicks":200000000,"MarkerType":"IntroEnd"},
             {"StartPositionTicks":3005000000,"Name":" Middle ","ImageTag":"second","MarkerType":"Chapter"},
             {"StartPositionTicks":4000000000,"Name":" ","MarkerType":"None"},
             {"StartPositionTicks":-10},
             {"Name":"Missing position"},
             {"StartPositionTicks":3005000000,"Name":"Duplicate"},
             {"StartPositionTicks":5900000000,"MarkerType":"CreditsStart"},
             {"StartPositionTicks":6000000000}]
            """)
            let request = try await provider.playbackInfo(for: "movie")
            XCTAssertEqual(request.chapters.map(\.start), [0, 300.5, 400])
            XCTAssertEqual(request.chapters.map(\.title), ["Opening", "Middle", nil])
            XCTAssertEqual(request.chapters[0].imageURL?.path, "/media/Items/movie/Images/Chapter/0")
            XCTAssertEqual(request.chapters[1].imageURL?.path, "/media/Items/movie/Images/Chapter/3",
                           "Image indexes belong to the original array, before filtering and sorting.")
            let url = try XCTUnwrap(request.chapters[1].imageURL)
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
                $0.name == "tag"
            }?.value, "second")
            XCTAssertNil(request.chapters[2].imageURL)
        }
    }

    func testMissingChaptersOrOnlySkipMarkersDoNotExposeChapterNavigation() async throws {
        for kind in [ProviderKind.jellyfin, .emby] {
            for chapters in ["null", "[]", #"[{"StartPositionTicks":0,"MarkerType":"IntroStart"}]"#] {
                let request = try await fixture(kind: kind, chapters: chapters).playbackInfo(for: "movie")
                XCTAssertTrue(request.chapters.isEmpty)
                XCTAssertNotNil(request.playbackSource)
            }
        }
    }

    private func fixture(kind: ProviderKind, chapters: String) -> JellyfinProvider {
        let http = StubHTTPClient()
        http.stub(pathSuffix: "/Users/user/Items/movie", json: """
        {"Id":"movie","Name":"Movie","Type":"Movie","RunTimeTicks":6000000000,"Chapters":\(chapters)}
        """)
        http.stub(pathSuffix: "/Items/movie/PlaybackInfo", json: """
        {"MediaSources":[{"Id":"movie","Container":"mp4","SupportsDirectPlay":true,
         "RunTimeTicks":6000000000,"MediaStreams":[{"Index":0,"Type":"Video","Codec":"h264"}]}]}
        """)
        return JellyfinProvider(session: .init(
            server: .init(id: "server", name: "Server", baseURL: URL(string: "https://fixture.test/media")!, provider: kind),
            userID: "user", userName: "User", deviceID: "device", accessToken: "fixture"
        ), http: http)
    }
}
