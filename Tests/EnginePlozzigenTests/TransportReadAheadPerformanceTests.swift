#if canImport(AetherEngine)
import Foundation
import XCTest
@testable import EnginePlozzigen
@testable import MediaTransportHTTP
@testable import MediaTransportWebDAV
@testable import TestSupportNetworking
@testable import TestSupportPerformance

private final class LatencyByteSource: TransportByteSource, @unchecked Sendable {
    let byteSize: Int64 = 512 * 1024 * 1024
    let preferredReadSize = 32 * 1024 * 1024
    private let lock = NSLock()
    private var reads = 0
    private var bytes = 0
    private var largest = 0

    var counters: [String: Int] {
        lock.withLock {
            ["transportReads": reads, "transportBytes": bytes, "largestRequest": largest]
        }
    }

    func read(at offset: Int64, length: Int) async throws -> Data {
        try await Task.sleep(for: .milliseconds(5))
        let count = min(length, Int(byteSize - offset))
        lock.withLock {
            reads += 1
            bytes += count
            largest = max(largest, length)
        }
        return Data(repeating: 0x5a, count: count)
    }

    func shutdown() async {}
}

@MainActor
final class TransportReadAheadPerformanceTests: XCTestCase {
    func testPerformancePacedWebDAVPlayback() async throws {
        try await measurePacedPlayback(scenario: "webdav-paced-playback", cachedSeeks: false)
    }

    func testPerformanceCachedWebDAVSeeks() async throws {
        try await measurePacedPlayback(scenario: "webdav-cached-seeks", cachedSeeks: true)
    }

    private func measurePacedPlayback(scenario: String, cachedSeeks: Bool) async throws {
        try PerformanceProbe.requireEnabled()
        try await PerformanceProbe.measure(self, scenario: scenario) {
            StubURLProtocol.reset()
            let url = try XCTUnwrap(URL(string: "https://media.example.com/fixture.m2ts"))
            let total = 128 * 1024 * 1024
            let registry = TransportSessionRegistry(testProtocolClasses: [StubURLProtocol.self])
            let key = try TransportSessionKey(
                accountID: "fixture", credentialRevision: UUID(),
                origin: XCTUnwrap(TransportOrigin(url: url)), trustRevision: UUID(), role: .playback
            )
            let source = WebDAVByteSource(
                client: WebDAVClient(registry: registry),
                representation: RangeProbeResult(
                    etag: try XCTUnwrap(ETag(headerValue: "\"fixture\"")),
                    totalLength: Int64(total), resourceURL: url
                ),
                sessionKey: key, credential: .anonymous, trustPolicy: .system
            )
            var offset = 0
            var window = 256 * 1024
            while offset < total {
                let length = min(window, total - offset)
                let ranges = length > 16 * 1024 * 1024
                    ? [(offset, length), (offset, 16 * 1024 * 1024),
                       (offset + 16 * 1024 * 1024, length - 16 * 1024 * 1024)]
                    : [(offset, length)]
                for (start, count) in ranges {
                    let range = "\(start)-\(start + count - 1)"
                    let response = StubResponse(
                        statusCode: 206,
                        headers: ["ETag": "\"fixture\"", "Content-Range": "bytes \(range)/\(total)"],
                        body: Data(repeating: 0x5a, count: count),
                        matchesRequest: { $0.value(forHTTPHeaderField: "Range") == "bytes=\(range)" },
                        delay: .milliseconds(100 + count / (256 * 1024))
                    )
                    for _ in 0..<(cachedSeeks ? 33 : 1) {
                        StubURLProtocol.queue(response, for: url)
                    }
                }
                offset += length
                window = min(window * 4, 32 * 1024 * 1024)
            }
            let reader = TransportIOReader(source: source)
            let completed = await Task.detached {
                var buffer = [UInt8](repeating: 0, count: 256 * 1024)
                var consumed = 0
                var probes = 0
                var waitNanoseconds: UInt64 = 0
                while consumed < total {
                    let started = DispatchTime.now().uptimeNanoseconds
                    let count = buffer.withUnsafeMutableBufferPointer {
                        reader.read($0.baseAddress, size: Int32($0.count))
                    }
                    waitNanoseconds += DispatchTime.now().uptimeNanoseconds - started
                    guard count > 0 else {
                        XCTFail("The complete paced workload must be delivered")
                        break
                    }
                    XCTAssertTrue(buffer.prefix(Int(count)).allSatisfy { $0 == 0x5a })
                    consumed += Int(count)
                    if cachedSeeks, consumed < total, consumed.isMultiple(of: 4 * 1024 * 1024) {
                        let probeOffset = Int64(consumed - 2 * 1024 * 1024)
                        let started = DispatchTime.now().uptimeNanoseconds
                        XCTAssertEqual(reader.seek(offset: probeOffset, whence: SEEK_SET), probeOffset)
                        let probeCount = buffer.withUnsafeMutableBufferPointer {
                            reader.read($0.baseAddress, size: 2048)
                        }
                        XCTAssertEqual(probeCount, 2048)
                        XCTAssertTrue(buffer.prefix(2048).allSatisfy { $0 == 0x5a })
                        XCTAssertEqual(reader.seek(offset: Int64(consumed), whence: SEEK_SET), Int64(consumed))
                        waitNanoseconds += DispatchTime.now().uptimeNanoseconds - started
                        probes += 1
                    }
                    // 32 MiB/s consumer work, independent of the download wait.
                    try await Task.sleep(for: .nanoseconds(Int64(count) * 1_000_000_000 / (32 * 1024 * 1024)))
                }
                return (consumed, waitNanoseconds, probes)
            }.result
            reader.close()
            await reader.waitForFinalShutdown()
            await registry.drainAll()
            let (consumed, waitNanoseconds, probes) = try completed.get()
            XCTAssertEqual(consumed, total)
            XCTAssertEqual(probes, cachedSeeks ? 31 : 0)
            let requests = StubURLProtocol.requests(for: url)
            let fetched = requests.reduce(0) { count, request in
                let bounds = request.value(forHTTPHeaderField: "Range")!
                    .dropFirst("bytes=".count).split(separator: "-")
                return count + Int(bounds[1])! - Int(bounds[0])! + 1
            }
            if cachedSeeks {
                XCTAssertGreaterThanOrEqual(fetched, total)
            } else {
                XCTAssertEqual(fetched, total, "Overlap must not duplicate or skip any window")
            }
            StubURLProtocol.reset()
            return [
                "consumedBytes": consumed, "requestedRangeBytes": fetched, "cachedProbes": probes,
                "transportReads": requests.count, "readerWaitNanoseconds": Int(waitNanoseconds)
            ]
        }
    }

    func testPerformanceRepeatedDiscMetadataProbes() async throws {
        try PerformanceProbe.requireEnabled()
        try await PerformanceProbe.measure(self, scenario: "disc-probe-cache") {
            let source = LatencyByteSource()
            let reader = TransportIOReader(source: source)
            let completed = await Task.detached {
                let offsets = [32, 512, 64, 576, 704, 896, 706, 898, 708, 930, 710,
                               932, 712, 934, 714, 936, 580, 716, 580, 676, 828]
                var buffer = [UInt8](repeating: 0, count: 2048)
                var completed = 0
                for offsetKiB in offsets {
                    let offset = Int64(offsetKiB * 1024)
                    XCTAssertEqual(reader.seek(offset: offset, whence: SEEK_SET), offset)
                    let count = buffer.withUnsafeMutableBufferPointer {
                        reader.read($0.baseAddress, size: Int32($0.count))
                    }
                    XCTAssertEqual(count, 2048)
                    XCTAssertTrue(buffer.allSatisfy { $0 == 0x5a })
                    completed += 1
                }
                return completed
            }.value
            reader.close()
            await reader.waitForFinalShutdown()
            XCTAssertEqual(completed, 21)
            return source.counters.merging(["metadataReads": completed]) { _, new in new }
        }
    }

    func testPerformanceRandomAndSequentialReads() async throws {
        try PerformanceProbe.requireEnabled()
        try await PerformanceProbe.measure(self, scenario: "network-file-read-ahead") {
            let source = LatencyByteSource()
            let reader = TransportIOReader(source: source)
            let completed = await Task.detached {
                var buffer = [UInt8](repeating: 0, count: 256 * 1024)
                var metadataReads = 0
                let offsets: [Int64] = [32_768, 128 * 1024 * 1024, 64 * 1024 * 1024, 384 * 1024 * 1024]
                for offset in offsets {
                    XCTAssertEqual(reader.seek(offset: offset, whence: SEEK_SET), offset)
                    let read = buffer.withUnsafeMutableBufferPointer {
                        reader.read($0.baseAddress, size: 2048)
                    }
                    XCTAssertEqual(read, 2048)
                    XCTAssertTrue(buffer.prefix(2048).allSatisfy { $0 == 0x5a })
                    metadataReads += 1
                }
                XCTAssertEqual(reader.seek(offset: 256 * 1024 * 1024, whence: SEEK_SET), 256 * 1024 * 1024)
                var consumed = 0
                while consumed < 64 * 1024 * 1024 {
                    let length = min(buffer.count, 64 * 1024 * 1024 - consumed)
                    let read = buffer.withUnsafeMutableBufferPointer {
                        reader.read($0.baseAddress, size: Int32(length))
                    }
                    guard read > 0 else {
                        XCTFail("The complete sequential workload must be delivered")
                        break
                    }
                    XCTAssertTrue(buffer.prefix(Int(read)).allSatisfy { $0 == 0x5a })
                    consumed += Int(read)
                }
                return (metadataReads, consumed)
            }.value
            reader.close()
            await reader.waitForFinalShutdown()
            XCTAssertEqual(completed.0, 4)
            XCTAssertEqual(completed.1, 64 * 1024 * 1024)
            return source.counters.merging([
                "metadataReads": completed.0, "consumedBytes": completed.1
            ]) { _, new in new }
        }
    }
}
#endif
