import CoreModels
import Foundation
import XCTest
@testable import CoreNetworking

@MainActor
final class HTTPPerformanceDiagnosticsTests: XCTestCase {
    private struct Payload: Decodable { let value: String }

    func testTransportAndDecodeKeepProviderContextWithoutPrivateRequestOrPayloadData() async throws {
        PerformanceDiagnostics.shared.start()
        defer { PerformanceDiagnostics.shared.stop() }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = URLSessionHTTPClient(session: session)
        let endpoint = Endpoint(method: .get, path: "/success", headers: ["Authorization": "private-credential"])
        let payload = try await PerformanceDiagnostics.$provider.withValue(.emby) {
            try await client.decode(
                Payload.self, from: endpoint, baseURL: XCTUnwrap(URL(string: "https://private-server.invalid"))
            )
        }
        XCTAssertEqual(payload.value, "private-media-title")
        let snapshot = try XCTUnwrap(PerformanceDiagnostics.shared.snapshot())
        let records = snapshot.recent + snapshot.slow
        let transport = try XCTUnwrap(records.first { $0.operation == .serverRequest })
        let decode = try XCTUnwrap(records.first { $0.operation == .serverDecode })
        XCTAssertEqual(transport.httpStatus, 200)
        XCTAssertEqual(transport.metrics.bytes, Data(#"{"value":"private-media-title"}"#.utf8).count)
        XCTAssertEqual(decode.metrics.bytes, transport.metrics.bytes)
        XCTAssertEqual(transport.provider, .emby)
        XCTAssertEqual(decode.provider, .emby)
        XCTAssertTrue(snapshot.active.isEmpty)
        let encoded = try snapshotText()
        XCTAssertTrue(encoded.contains("serverRequest"))
        XCTAssertTrue(encoded.contains("serverDecode"))
        XCTAssertTrue(encoded.contains("emby"))
        XCTAssertTrue(encoded.contains("succeeded"))
        for secret in ["private-server", "private-credential", "private-media-title", "Authorization", "/success"] {
            XCTAssertFalse(encoded.contains(secret), secret)
        }
    }

    func testHTTPFailureAndCancellationPreserveCallerErrors() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = URLSessionHTTPClient(session: session)
        for (path, expected, outcome) in [
            ("/failure", AppError.invalidResponse, "failed"),
            ("/cancelled", AppError.cancelled, "cancelled")
        ] {
            PerformanceDiagnostics.shared.start()
            defer { PerformanceDiagnostics.shared.stop() }
            do {
                _ = try await client.send(
                    Endpoint(method: .get, path: path),
                    baseURL: XCTUnwrap(URL(string: "https://private-server.invalid"))
                )
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? AppError, expected)
            }
            let snapshot = try XCTUnwrap(PerformanceDiagnostics.shared.snapshot())
            let transport = try XCTUnwrap((snapshot.recent + snapshot.slow).first {
                $0.operation == .serverRequest
            })
            if path == "/failure" {
                XCTAssertEqual(transport.httpStatus, 500)
                XCTAssertEqual(transport.outcome, .failed)
            } else {
                XCTAssertEqual(transport.networkCode, URLError.Code.cancelled.rawValue)
                XCTAssertEqual(transport.outcome, .cancelled)
            }
            XCTAssertTrue(snapshot.active.isEmpty)
            let encoded = try snapshotText()
            XCTAssertTrue(encoded.contains("serverRequest"))
            XCTAssertTrue(encoded.contains(outcome))
            XCTAssertFalse(encoded.contains("private-server"))
            XCTAssertFalse(encoded.contains("private-media-title"))
        }
    }

    func testDisabledDiagnosticsDoNotCollectSuccessfulRequests() async throws {
        PerformanceDiagnostics.shared.stop()
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = URLSessionHTTPClient(session: session)
        let payload = try await client.decode(
            Payload.self, from: Endpoint(method: .get, path: "/success"),
            baseURL: XCTUnwrap(URL(string: "https://private-server.invalid"))
        )
        XCTAssertEqual(payload.value, "private-media-title")
        XCTAssertNil(PerformanceDiagnostics.shared.snapshot())
    }

    private func snapshotText() throws -> String {
        let snapshot = try XCTUnwrap(PerformanceDiagnostics.shared.snapshot())
        return String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PerformanceURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class PerformanceURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if url.path == "/cancelled" {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        guard let response = HTTPURLResponse(
            url: url, statusCode: url.path == "/failure" ? 500 : 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"value":"private-media-title"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
