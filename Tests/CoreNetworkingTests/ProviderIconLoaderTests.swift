import Foundation
import XCTest
@testable import CoreNetworking

final class ProviderIconLoaderTests: XCTestCase {
    func testIconAddressContainsOnlyOriginAndConventionalPath() throws {
        for (input, expected) in [
            ("https://user:password@provider.invalid:8443/live/user/token/1.ts?token=secret#fragment",
             "https://provider.invalid:8443/favicon.ico"),
            ("http://provider.invalid/playlist.m3u?username=alex&password=example",
             "http://provider.invalid/favicon.ico"),
            ("https://[::1]:8443/playlist.m3u", "https://[::1]:8443/favicon.ico")
        ] {
            let source = try XCTUnwrap(URL(string: input))
            XCTAssertEqual(ProviderIconLoader.iconURL(for: source)?.absoluteString, expected)
        }
        for input in ["file:///tmp/playlist.m3u", "plozz-playlist://source", "ftp://provider.invalid/file", "/playlist.m3u"] {
            XCTAssertNil(ProviderIconLoader.iconURL(for: try XCTUnwrap(URL(string: input))))
        }
    }

    func testLoadDoesNotForwardSourceCredentials() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let loader = ProviderIconLoader(session: session)
        let data = try await loader.load(from: XCTUnwrap(URL(
            string: "https://user:password@valid.invalid/private/path?token=secret"
        )))
        XCTAssertEqual(data, Data("icon".utf8))
    }

    func testRejectsFailedAndOversizedResponses() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let loader = ProviderIconLoader(session: session)
        for (host, code) in [
            ("missing.invalid", URLError.Code.badServerResponse),
            ("declared-large.invalid", .dataLengthExceedsMaximum),
            ("streamed-large.invalid", .dataLengthExceedsMaximum)
        ] {
            do {
                _ = try await loader.load(from: XCTUnwrap(URL(string: "https://\(host)/playlist.m3u")))
                XCTFail("The icon request must fail for \(host).")
            } catch let error as URLError {
                XCTAssertEqual(error.code, code)
            }
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderIconProtocol.self]
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }
}

private final class ProviderIconProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        XCTAssertNil(url.user)
        XCTAssertNil(url.password)
        XCTAssertNil(url.query)
        XCTAssertNil(url.fragment)
        XCTAssertEqual(url.path, "/favicon.ico")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let oversized = url.host == "declared-large.invalid" || url.host == "streamed-large.invalid"
        let data = oversized ? Data(repeating: 1, count: ProviderIconLoader.maximumBytes + 1) : Data("icon".utf8)
        let headers = url.host == "declared-large.invalid" ? ["Content-Length": "\(data.count)"] : [:]
        guard let response = HTTPURLResponse(
            url: url, statusCode: url.host == "missing.invalid" ? 404 : 200,
            httpVersion: "HTTP/1.1", headerFields: headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
