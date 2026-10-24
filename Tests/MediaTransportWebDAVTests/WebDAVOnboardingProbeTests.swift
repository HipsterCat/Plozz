import Foundation
@testable import MediaTransportHTTP
@testable import MediaTransportWebDAV
@testable import TestSupportNetworking
import XCTest

final class WebDAVOnboardingProbeTests: XCTestCase {
    private let url = URL(string: "https://nas.example.com/dav/Movies%20%25%3F%23/")!

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeProbe() -> WebDAVOnboardingProbe {
        WebDAVOnboardingProbe(
            registryFactory: { TransportSessionRegistry(testProtocolClasses: [StubURLProtocol.self]) }
        )
    }

    private func collectionResponse(
        href: String = "/dav/Movies%20%25%3F%23/",
        property: String = "<resourcetype><collection/></resourcetype>",
        status: String = "HTTP/1.1 200 OK"
    ) -> Data {
        Data("""
        <multistatus xmlns="DAV:"><response>
          <href>\(href)</href>
          <propstat><prop>\(property)</prop><status>\(status)</status></propstat>
        </response></multistatus>
        """.utf8)
    }

    func testValidationUsesDepthZeroAndPreservesEncodedRoot() async throws {
        let request = LockedValue<URLRequest?>(nil)
        StubURLProtocol.queue(
            StubResponse(
                statusCode: 207, body: collectionResponse(),
                onRequest: { request.set($0) }
            ),
            for: url
        )
        try await makeProbe().validate(url: url, credential: .anonymous, trust: .system).get()
        XCTAssertEqual(request.get()?.httpMethod, "PROPFIND")
        XCTAssertEqual(request.get()?.value(forHTTPHeaderField: "Depth"), "0")
        XCTAssertEqual(request.get()?.url, url)
    }

    func testValidationRejectsUnprovenCollections() async {
        let bodies = [
            Data("<html><body>Sign in</body></html>".utf8),
            Data("<multistatus xmlns=\"DAV:\"/>".utf8),
            collectionResponse(property: "<resourcetype/>"),
            collectionResponse(status: "HTTP/1.1 403 Forbidden"),
            collectionResponse(href: "/dav/Movies%20%25%3F%23/child/"),
            collectionResponse(href: "/outside/"),
            collectionResponse(href: "https://other.example.com/dav/Movies%20%25%3F%23/"),
            collectionResponse(property: "<extension><resourcetype><collection/></resourcetype></extension>")
        ]
        for body in bodies {
            let received = LockedValue(false)
            StubURLProtocol.queue(
                StubResponse(statusCode: 207, body: body, onRequest: { _ in received.set(true) }),
                for: url
            )
            let result = await makeProbe().validate(url: url, credential: .anonymous, trust: .system)
            XCTAssertTrue(received.get())
            guard case .failure(.notWebDAV) = result else {
                XCTFail("expected notWebDAV, got \(result)")
                continue
            }
        }
    }

    func testValidationPreservesHTTPFailures() async {
        let cases: [(Int, WebDAVOnboardingError)] = [
            (401, .authenticationFailed), (403, .forbidden),
            (405, .notWebDAV), (500, .serverError), (503, .serverError)
        ]
        for (status, expected) in cases {
            let received = LockedValue(false)
            StubURLProtocol.queue(
                StubResponse(statusCode: status, onRequest: { _ in received.set(true) }),
                for: url
            )
            let result = await makeProbe().validate(url: url, credential: .anonymous, trust: .system)
            XCTAssertTrue(received.get())
            guard case .failure(let error) = result else {
                XCTFail("expected \(expected), got \(result)")
                continue
            }
            XCTAssertEqual(error, expected)
        }
    }
}
