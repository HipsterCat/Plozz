import Foundation
import XCTest
@testable import MediaTransportHTTP
@testable import TestSupportPerformance

private final class ResponseCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Result<TransportDataResponse, TransportError>?

    func set(_ result: Result<TransportDataResponse, TransportError>) {
        lock.withLock { storage = result }
    }

    func get() -> Result<TransportDataResponse, TransportError>? {
        lock.withLock { storage }
    }
}

@MainActor
final class TransportResponsePerformanceTests: XCTestCase {
    func testPerformanceChunkedResponseAssembly() async throws {
        try PerformanceProbe.requireEnabled()
        try await PerformanceProbe.measure(self, scenario: "http-response-assembly") {
            let bytes = 32 * 1024 * 1024
            let chunk = Data(repeating: 0x5a, count: 16 * 1024)
            let result = try self.receive(chunks: Array(repeating: chunk, count: bytes / chunk.count), limit: bytes)
            let response = try result.get()
            XCTAssertEqual(response.data.count, bytes)
            XCTAssertTrue(response.data.allSatisfy { $0 == 0x5a })
            return ["responseBytes": response.data.count, "callbacks": bytes / chunk.count]
        }
    }

    func testChunkedResponsePreservesOrderAndExactLimit() throws {
        let response = try receive(
            chunks: [Data([1, 2]), Data([3]), Data([4, 5])], limit: 5
        ).get()
        XCTAssertEqual(response.data, Data([1, 2, 3, 4, 5]))
    }

    func testOversizedCallbackRejectsAllPartialBytes() throws {
        guard case .failure(.responseTooLarge(limitBytes: 4)) = try receive(
            chunks: [Data([1, 2]), Data([3, 4, 5])], limit: 4
        ) else {
            return XCTFail("An oversized body must not succeed with partial bytes")
        }
    }

    func testCancellationRejectsPartialBody() throws {
        guard case .failure(.cancelled) = try receive(
            chunks: [Data([1, 2])], limit: 4, error: URLError(.cancelled)
        ) else {
            return XCTFail("Cancellation must not return the partially received body")
        }
    }

    private func receive(
        chunks: [Data], limit: Int, error: Error? = nil
    ) throws -> Result<TransportDataResponse, TransportError> {
        let url = URL(string: "https://nas.example.com/movie.mkv")!
        let delegate = TransportSessionDelegate(
            credential: .anonymous, trustPolicy: .system, origin: TransportOrigin(url: url)!
        )
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url)
        let capture = ResponseCapture()
        delegate.register(task: task, maxResponseBytes: limit) { capture.set($0) }
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: [:]
        ))
        delegate.urlSession(session, dataTask: task, didReceive: response) {
            XCTAssertEqual($0, .allow)
        }
        for chunk in chunks {
            delegate.urlSession(session, dataTask: task, didReceive: chunk)
        }
        delegate.urlSession(session, task: task, didCompleteWithError: error)
        return try XCTUnwrap(capture.get())
    }
}
