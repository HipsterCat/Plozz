import CoreModels
import Foundation
import XCTest
@testable import CoreNetworking

final class SiloSetupRequestTests: XCTestCase {
    func testStatusAndResponseClassificationNeverRetainsBodyOrAddress() async throws {
        struct Value: Decodable { let ok: Bool }
        for (status, mime, reason) in [
            (502, "text/html", SiloSetupDiagnostic.Reason.server),
            (302, "text/html", .redirect),
            (401, "application/problem+json", .unauthorized),
            (200, "text/html", .malformed),
            (429, "application/json", .rateLimited)
        ] {
            do {
                _ = try await SiloSetupRequest.decode(
                    Value.self, endpoint: Endpoint(path: "/private/profile"),
                    baseURL: URL(string: "https://private.invalid")!,
                    http: SiloSetupHTTP(status: status, mime: mime), stage: .start
                )
                XCTFail("Expected failure")
            } catch let failure as SiloSetupFailure {
                XCTAssertEqual(failure.diagnostic.stage, .start)
                XCTAssertEqual(failure.diagnostic.reason, reason)
                XCTAssertEqual(failure.diagnostic.httpStatus, status)
                let data = try JSONEncoder().encode(failure.diagnostic)
                let text = String(decoding: data, as: UTF8.self)
                XCTAssertFalse(text.contains("private"))
                XCTAssertFalse(text.contains("secret"))
            }
        }
    }
}

private struct SiloSetupHTTP: HTTPClient {
    let status: Int
    let mime: String
    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        (Data("<html>secret-private-token</html>".utf8),
         HTTPURLResponse(url: baseURL, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": mime])!)
    }
}
