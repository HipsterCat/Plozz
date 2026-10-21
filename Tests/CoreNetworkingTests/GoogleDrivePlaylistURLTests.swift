import CoreNetworking
import Foundation
import XCTest

final class GoogleDrivePlaylistURLTests: XCTestCase {
    func testFileViewerAndLegacyDownloadFormsResolveToThePublicDownloadEndpoint() throws {
        for address in [
            "https://drive.google.com/file/d/file_ID-123/view?usp=sharing",
            "https://drive.google.com/file/d/file_ID-123/preview",
            "https://drive.google.com/file/d/file_ID-123/edit",
            "https://drive.google.com/file/d/file_ID-123",
            "https://drive.google.com/file/d/file_ID-123/",
            "https://drive.google.com/file/u/0/d/file_ID-123/view",
            "https://drive.google.com/open?id=file_ID-123",
            "https://drive.google.com/uc?export=download&id=file_ID-123",
            "https://DRIVE.GOOGLE.COM:443/uc?id=file_ID-123&export=download"
        ] {
            let result = GoogleDrivePlaylistURL.downloadURL(for: try XCTUnwrap(URL(string: address)))
            XCTAssertEqual(result.absoluteString,
                           "https://drive.usercontent.google.com/download?id=file_ID-123&export=download")
        }
    }

    func testResourceKeyAndExplicitDownloadGrantArePreservedButNotInvented() throws {
        let url = try XCTUnwrap(URL(string:
            "https://drive.google.com/uc?id=fixture&resourcekey=key%2Bvalue&confirm=true&uuid=grant&authuser=0"
        ))
        let result = GoogleDrivePlaylistURL.downloadURL(for: url)
        let query = try XCTUnwrap(URLComponents(url: result, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query, [
            .init(name: "id", value: "fixture"), .init(name: "export", value: "download"),
            .init(name: "resourcekey", value: "key+value"), .init(name: "confirm", value: "true"),
            .init(name: "uuid", value: "grant")
        ])
        let share = try XCTUnwrap(URL(string: "https://drive.google.com/file/d/fixture/view?resourcekey=key"))
        XCTAssertEqual(GoogleDrivePlaylistURL.downloadURL(for: share).absoluteString,
                       "https://drive.usercontent.google.com/download?id=fixture&export=download&resourcekey=key")
    }

    func testOtherHostsRoutesCredentialsAndAmbiguousLinksAreUntouched() throws {
        for address in [
            "https://drive.usercontent.google.com/download?id=fixture&export=download&confirm=t",
            "https://provider.test/uc?id=fixture",
            "https://drive.google.com.evil.test/file/d/fixture/view",
            "http://drive.google.com/file/d/fixture/view",
            "https://drive.google.com:444/file/d/fixture/view",
            "https://user:password@drive.google.com/file/d/fixture/view",
            "https://drive.google.com/drive/folders/fixture",
            "https://drive.google.com/file/d/fixture/view/extra",
            "https://drive.google.com/file//d/fixture/view",
            "https://drive.google.com/file/u/not-a-number/d/fixture/view",
            "https://drive.google.com/open",
            "https://drive.google.com/uc?id=",
            "https://drive.google.com/uc?id=one&id=two",
            "https://drive.google.com/uc?id=one&resourcekey=a&resourcekey=b",
            "https://drive.google.com/uc?id=one%2Ftwo",
            "https://drive.google.com/file/d/one/view?id=two",
            "https://drive.google.com/file/d/fixture/view?token=secret"
        ] {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertEqual(GoogleDrivePlaylistURL.downloadURL(for: url), url, address)
        }
    }
}
