import CoreModels
import Foundation
import XCTest
@testable import CoreNetworking
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class HTTPResponseDiagnosticsTests: XCTestCase {
    private struct Envelope: Decodable, Sendable {
        struct Item: Decodable, Sendable { let Id: String }
        let Items: [Item]
    }

    func testCapturePreservesAppErrorAndResponseStructureWithoutPrivateValues() async throws {
        let captured = await HTTPResponseDiagnostics.capture {
            try await FixtureHTTP(json: #"{"Items":[{"Id":false}],"private-key":"private-value"}"#).decode(
                Envelope.self, from: Endpoint(path: "/private-path", headers: ["Authorization": "private-token"]),
                baseURL: URL(string: "https://private-host.invalid")!
            )
        }
        guard case .failure(let error) = captured.result else { return XCTFail("Expected decoding failure") }
        XCTAssertEqual(error as? AppError, .decoding)
        let response = try XCTUnwrap(captured.responses.first)
        XCTAssertEqual(response.httpStatus, 200)
        XCTAssertEqual(response.payload, .object)
        XCTAssertEqual(response.reason, .wrongType)
        XCTAssertEqual(response.path, "Items.[0].Id")
        XCTAssertEqual(response.expected, .string)
        let report = LibraryLoadDiagnostic(
            provider: .plex, failures: [.init(section: .recommendations, error: .decoding, responses: captured.responses)]
        )
        XCTAssertFalse(report.supportText.contains("private"))
    }

    func testConcurrentScopesDoNotMixResponsesAndSuccessfulFallbackDiscardsFailures() async throws {
        async let object = HTTPResponseDiagnostics.capture {
            try await FixtureHTTP(json: #"{"Items":false}"#).decode(
                Envelope.self, from: Endpoint(path: "/a"), baseURL: URL(string: "https://fixture.invalid")!
            )
        }
        async let html = HTTPResponseDiagnostics.capture {
            try await FixtureHTTP(json: "<html>private response</html>").decode(
                Envelope.self, from: Endpoint(path: "/b"), baseURL: URL(string: "https://fixture.invalid")!
            )
        }
        let (first, second) = await (object, html)
        XCTAssertEqual(first.responses.map(\.payload), [.object])
        XCTAssertEqual(second.responses.map(\.payload), [.nonJSON])
        let recovered = await HTTPResponseDiagnostics.capture {
            do {
                return try await FixtureHTTP(json: "{}").decode(
                    Envelope.self, from: Endpoint(path: "/fallback"), baseURL: URL(string: "https://fixture.invalid")!
                )
            } catch AppError.decoding {
                return Envelope(Items: [])
            }
        }
        XCTAssertTrue(recovered.responses.isEmpty)
        XCTAssertNotNil(try? recovered.result.get())
    }

    func testDynamicCodingKeysAndDescriptionsNeverEnterSupportReport() throws {
        struct DynamicKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        let key = try XCTUnwrap(DynamicKey(stringValue: "https://private.invalid/?token=secret"))
        let error = DecodingError.keyNotFound(key, .init(codingPath: [], debugDescription: "private secret"))
        let response = ResponseDecodingDiagnostic(
            route: .other, httpStatus: 200, bytes: 20, payload: .object, error: error
        )
        XCTAssertEqual(response.path, "<field>")
        let report = PlaybackDiagnosticReport.library(.init(provider: .jellyfin, failures: [
            .init(section: .recentlyAdded, error: .unknown("private secret"), responses: [response])
        ]))
        XCTAssertTrue(report.supportText.contains("failure_0.reason=unknown"))
        XCTAssertFalse(report.supportText.contains("private"))
        XCTAssertFalse(report.supportText.contains("secret"))
    }

    func testFailureCaptureIsBoundedAndMissingKeysStayActionable() async throws {
        let captured = await HTTPResponseDiagnostics.capture { () async throws -> Envelope in
            for _ in 0..<7 {
                do {
                    _ = try await FixtureHTTP(json: "{}").decode(
                        Envelope.self, from: Endpoint(path: "/fixture"), baseURL: URL(string: "https://fixture.invalid")!
                    )
                } catch AppError.decoding {
                    continue
                }
            }
            throw AppError.decoding
        }
        XCTAssertEqual(captured.responses.count, 4)
        XCTAssertEqual(captured.responses.last?.reason, .missingKey)
        XCTAssertEqual(captured.responses.last?.path, "Items")
    }

    func testPagingEvidenceIsBoundedIsolatedAndDiscardedOnSuccess() async throws {
        let diagnostic = LibraryPagingDiagnostic(
            stage: .collectionMembers, reason: .nonAdvancing, start: 24, rows: 1, total: 25
        )
        async let failed = HTTPResponseDiagnostics.capture { () async throws -> Int in
            for _ in 0..<7 { HTTPResponseDiagnostics.recordPagingFailure(diagnostic) }
            throw AppError.invalidResponse
        }
        async let recovered = HTTPResponseDiagnostics.capture {
            HTTPResponseDiagnostics.recordPagingFailure(diagnostic)
            return 1
        }
        let (failure, success) = await (failed, recovered)
        XCTAssertEqual(failure.paging, Array(repeating: diagnostic, count: 4))
        XCTAssertTrue(success.paging.isEmpty)
        XCTAssertEqual(try success.result.get(), 1)
        let report = PlaybackDiagnosticReport.library(.init(
            provider: .emby, operation: .libraryBrowse,
            failures: [.init(section: .collections, error: .invalidResponse, paging: failure.paging)]
        ))
        XCTAssertTrue(report.supportText.contains("operation=libraryBrowse"))
        XCTAssertTrue(report.supportText.contains("failure_0.section=collections"))
        XCTAssertTrue(report.supportText.contains("failure_0.page_0.stage=collectionMembers"))
        XCTAssertTrue(report.supportText.contains("failure_0.page_0.reason=nonAdvancing"))
        XCTAssertTrue(report.supportText.contains("failure_0.page_0.start=24"))
        XCTAssertFalse(report.supportText.contains("page_4"))
    }

    func testTransportEvidenceKeepsOnlyNumericCodesAndRoutesAndDiscardsRecoveredFailures() async throws {
        let failed = await HTTPResponseDiagnostics.capture { () async throws -> Int in
            HTTPResponseDiagnostics.$route.withValue(.collectionMembers) {
                for _ in 0..<7 {
                    HTTPResponseDiagnostics.recordTransportFailure(URLError(.timedOut, userInfo: [
                        NSURLErrorFailingURLStringErrorKey: "https://private.invalid/?token=secret"
                    ]))
                }
                HTTPResponseDiagnostics.recordTransportFailure(URLError(.cancelled))
            }
            throw AppError.serverUnreachable
        }
        XCTAssertEqual(failed.transport.count, 4)
        XCTAssertTrue(failed.transport.allSatisfy { $0.route == .collectionMembers && $0.urlErrorCode == -1001 })
        let report = LibraryLoadDiagnostic(provider: .jellyfin, operation: .libraryBrowse, failures: [
            .init(section: .collections, error: .serverUnreachable, transport: failed.transport)
        ])
        XCTAssertTrue(report.supportText.contains("transport_0.url_error_code=-1001"))
        XCTAssertFalse(report.supportText.contains("private"))
        XCTAssertFalse(report.supportText.contains("secret"))
        let recovered = await HTTPResponseDiagnostics.capture {
            HTTPResponseDiagnostics.recordTransportFailure(URLError(.networkConnectionLost))
            return 1
        }
        XCTAssertTrue(recovered.transport.isEmpty)
    }

    func testURLSessionTransportFailureReachesTheLibraryCapture() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportFailureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let http = URLSessionHTTPClient(session: session)
        let captured = await HTTPResponseDiagnostics.capture {
            try await HTTPResponseDiagnostics.$route.withValue(.collectionLibraryScope) {
                try await http.decode(
                    Envelope.self, from: Endpoint(path: "/fixture"), baseURL: URL(string: "https://fixture.invalid")!
                )
            }
        }
        guard case .failure(let error) = captured.result else { return XCTFail("Expected transport failure") }
        XCTAssertEqual(error as? AppError, .serverUnreachable)
        XCTAssertEqual(captured.transport, [.init(route: .collectionLibraryScope, urlErrorCode: -1001)])
    }

    func testHTTPStatusesAreBoundedAndRecoveredFailuresAreDiscarded() async throws {
        let captured = await HTTPResponseDiagnostics.capture { () async throws -> Int in
            HTTPResponseDiagnostics.$route.withValue(.continueWatchingItems) {
                for _ in 0..<7 { HTTPResponseDiagnostics.recordHTTPFailure(status: 503) }
                HTTPResponseDiagnostics.recordHTTPFailure(status: 200)
            }
            throw AppError.invalidResponse
        }
        XCTAssertEqual(captured.http, Array(repeating: .init(route: .continueWatchingItems, httpStatus: 503), count: 4))
        let report = LibraryLoadDiagnostic(provider: .plex, operation: .homeContinueWatching, failures: [
            .init(section: .continueWatching, error: .unknown("private-token"), http: captured.http)
        ])
        XCTAssertTrue(report.supportText.contains("operation=homeContinueWatching"))
        XCTAssertTrue(report.supportText.contains("http_0.route=continueWatchingItems"))
        XCTAssertTrue(report.supportText.contains("http_0.status=503"))
        XCTAssertFalse(report.supportText.contains("http_4"))
        XCTAssertFalse(report.supportText.contains("private-token"))
        let recovered = await HTTPResponseDiagnostics.capture {
            HTTPResponseDiagnostics.recordHTTPFailure(status: 500)
            return 1
        }
        XCTAssertTrue(recovered.http.isEmpty)
    }

    func testURLSessionHTTPFailureRetainsStatusWithoutChangingErrorMapping() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatusFailureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let captured = await HTTPResponseDiagnostics.capture {
            try await HTTPResponseDiagnostics.$route.withValue(.continueWatchingHub) {
                try await URLSessionHTTPClient(session: session).decode(
                    Envelope.self, from: Endpoint(path: "/private-path"),
                    baseURL: URL(string: "https://private-host.invalid")!
                )
            }
        }
        guard case .failure(let error) = captured.result else { return XCTFail("Expected HTTP failure") }
        XCTAssertEqual(error as? AppError, .invalidResponse)
        XCTAssertEqual(captured.http, [.init(route: .continueWatchingHub, httpStatus: 503)])
    }

    private final class StatusFailureURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("private response".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private final class TransportFailureURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)) }
        override func stopLoading() {}
    }

    private struct FixtureHTTP: HTTPClient {
        let json: String
        func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
            (Data(json.utf8), HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
}
