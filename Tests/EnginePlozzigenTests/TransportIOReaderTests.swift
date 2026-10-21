#if canImport(AetherEngine)
import Foundation
import XCTest
import AetherEngine
@testable import EnginePlozzigen

private final class FakeTransportByteSource: TransportByteSource, @unchecked Sendable {
    enum FakeError: Error {
        case failed
    }

    private struct State {
        var closeCount = 0
        var shouldFailReads = false
    }

    let data: Data
    private let state = NSLock()
    private var storage = State()

    init(_ data: Data) {
        self.data = data
    }

    var byteSize: Int64 {
        Int64(data.count)
    }

    var closeCount: Int {
        state.withLock { storage.closeCount }
    }

    func failReads() {
        state.withLock { storage.shouldFailReads = true }
    }

    func resumeReads() {
        state.withLock { storage.shouldFailReads = false }
    }

    func read(at offset: Int64, length: Int) async throws -> Data {
        if state.withLock({ storage.shouldFailReads }) {
            throw FakeError.failed
        }
        guard offset >= 0, offset < data.count, length > 0 else { return Data() }
        let end = min(Int(offset) + length, data.count)
        return data.subdata(in: Int(offset)..<end)
    }

    func shutdown() async {
        state.withLock { storage.closeCount += 1 }
    }
}

private final class AsyncReadGate: @unchecked Sendable {
    private struct State {
        var isStarted = false
        var isOpen = false
        var startWaiters: [CheckedContinuation<Void, Never>] = []
        var openWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = NSLock()
    private var storage = State()

    func reachAndWait() async {
        let startWaiters = state.withLock { () -> [CheckedContinuation<Void, Never>] in
            storage.isStarted = true
            let waiters = storage.startWaiters
            storage.startWaiters.removeAll()
            return waiters
        }
        startWaiters.forEach { $0.resume() }

        await withCheckedContinuation { continuation in
            let resumeImmediately = state.withLock { () -> Bool in
                if storage.isOpen {
                    return true
                }
                storage.openWaiters.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = state.withLock { () -> Bool in
                if storage.isStarted {
                    return true
                }
                storage.startWaiters.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiters = state.withLock { () -> [CheckedContinuation<Void, Never>] in
            storage.isOpen = true
            let waiters = storage.openWaiters
            storage.openWaiters.removeAll()
            return waiters
        }
        waiters.forEach { $0.resume() }
    }
}

private final class BlockingTransportByteSource: TransportByteSource, @unchecked Sendable {
    private let readGate = AsyncReadGate()
    private let state = NSLock()
    private var closeCountStorage = 0

    let byteSize: Int64 = 1
    let preferredReadSize: Int

    init(preferredReadSize: Int = 1024 * 1024) {
        self.preferredReadSize = preferredReadSize
    }

    var closeCount: Int {
        state.withLock { closeCountStorage }
    }

    func read(at offset: Int64, length: Int) async throws -> Data {
        await readGate.reachAndWait()
        return Data([42])
    }

    func shutdown() async {
        state.withLock { closeCountStorage += 1 }
    }

    func waitUntilReadStarts() async {
        await readGate.waitUntilStarted()
    }

    func finishRead() {
        readGate.open()
    }
}

private final class CountingTransportByteSource: TransportByteSource, @unchecked Sendable {
    let data: Data
    private let state = NSLock()
    private var reads: [(offset: Int64, length: Int)] = []

    init(_ data: Data) { self.data = data }

    var byteSize: Int64 { Int64(data.count) }

    var readCount: Int { state.withLock { reads.count } }
    var readLog: [(offset: Int64, length: Int)] { state.withLock { reads } }

    func read(at offset: Int64, length: Int) async throws -> Data {
        state.withLock { reads.append((offset, length)) }
        guard offset >= 0, offset < data.count, length > 0 else { return Data() }
        let end = min(Int(offset) + length, data.count)
        return data.subdata(in: Int(offset)..<end)
    }

    func shutdown() async {}
}

private final class SparseTransportByteSource: TransportByteSource, @unchecked Sendable {
    let byteSize: Int64 = 256 * 1024 * 1024
    let preferredReadSize: Int
    private let lock = NSLock()
    private var reads: [(offset: Int64, length: Int)] = []

    init(preferredReadSize: Int = 1024 * 1024) {
        self.preferredReadSize = preferredReadSize
    }

    var readLog: [(offset: Int64, length: Int)] { lock.withLock { reads } }

    func read(at offset: Int64, length: Int) async throws -> Data {
        lock.withLock { reads.append((offset, length)) }
        return Data(repeating: 42, count: min(length, Int(byteSize - offset)))
    }

    func shutdown() async {}
}

private final class PrefetchTransportByteSource: TransportByteSource, @unchecked Sendable {
    let byteSize: Int64 = 96 * 1024 * 1024
    let preferredReadSize = 32 * 1024 * 1024
    private let gate = AsyncReadGate()
    private let lock = NSLock()
    private var reads: [(offset: Int64, length: Int)] = []
    private var cancellations = 0
    let failsPrefetch: Bool

    init(failsPrefetch: Bool = false) { self.failsPrefetch = failsPrefetch }
    var readLog: [(offset: Int64, length: Int)] { lock.withLock { reads } }
    var cancelledReads: Int { lock.withLock { cancellations } }

    func read(at offset: Int64, length: Int) async throws -> Data {
        lock.withLock { reads.append((offset, length)) }
        if offset == 40 * 1024 * 1024 {
            await withTaskCancellationHandler {
                await gate.reachAndWait()
            } onCancel: {
                self.lock.withLock { self.cancellations += 1 }
            }
            try Task.checkCancellation()
            if failsPrefetch { throw FakeTransportByteSource.FakeError.failed }
        }
        var data = Data(repeating: UInt8(offset / (1024 * 1024) + 1), count: min(length, Int(byteSize - offset)))
        if offset == 40 * 1024 * 1024 {
            data.replaceSubrange(0..<256, with: (0..<256).map { UInt8($0) })
        }
        return data
    }

    func waitForPrefetch() async { await gate.waitUntilStarted() }
    func finishPrefetch() { gate.open() }
    func shutdown() async {}
}

private func read(_ reader: IOReader, count: Int) -> (result: Int32, data: Data) {
    var bytes = [UInt8](repeating: 0, count: count)
    let result = bytes.withUnsafeMutableBufferPointer {
        reader.read($0.baseAddress, size: Int32(count))
    }
    return (result, Data(bytes.prefix(Int(max(result, 0)))))
}

private final class CappedTransportByteSource: TransportByteSource, @unchecked Sendable {
    let data: Data
    let perReadCap: Int
    let preferredReadSize: Int
    private let state = NSLock()
    private var reads: [(offset: Int64, length: Int)] = []

    init(_ data: Data, perReadCap: Int, preferredReadSize: Int = 1024 * 1024) {
        self.data = data
        self.perReadCap = perReadCap
        self.preferredReadSize = preferredReadSize
    }

    var byteSize: Int64 { Int64(data.count) }
    var readCount: Int { state.withLock { reads.count } }

    func read(at offset: Int64, length: Int) async throws -> Data {
        // Simulate a backend that never serves more than `perReadCap` per read.
        let capped = min(length, perReadCap)
        state.withLock { reads.append((offset, capped)) }
        guard offset >= 0, offset < data.count, capped > 0 else { return Data() }
        let end = min(Int(offset) + capped, data.count)
        return data.subdata(in: Int(offset)..<end)
    }

    func shutdown() async {}
}

final class TransportIOReaderReadAheadTests: XCTestCase {
    private func reachReadAhead(_ reader: TransportIOReader) {
        XCTAssertEqual(read(reader, count: 8 * 1024 * 1024).result, 8 * 1024 * 1024)
        XCTAssertEqual(read(reader, count: 8 * 1024 * 1024).result, 8 * 1024 * 1024)
        XCTAssertEqual(read(reader, count: 8 * 1024 * 1024).result, 8 * 1024 * 1024)
    }

    func testReadAheadOverlapsConsumptionWithoutFetchingASecondFutureWindow() async {
        let source = PrefetchTransportByteSource()
        let reader = TransportIOReader(source: source)
        reachReadAhead(reader)
        await source.waitForPrefetch()
        XCTAssertEqual(source.readLog.map(\.offset), [0, 8 * 1024 * 1024, 40 * 1024 * 1024])
        for _ in 0..<16 {
            XCTAssertEqual(read(reader, count: 1024 * 1024).data, Data(repeating: 9, count: 1024 * 1024))
        }
        XCTAssertEqual(source.readLog.count, 3, "Only one future window may be outstanding")
        source.finishPrefetch()
        XCTAssertEqual(read(reader, count: 16).data, Data((0..<16).map { UInt8($0) }))
        XCTAssertEqual(source.readLog.count, 3, "The demand read must adopt, not duplicate, the prefetch")
        reader.close()
        await reader.waitForFinalShutdown()
    }

    func testSeekOutsideBothWindowsCancelsReadAheadAndPreservesCachedBytes() async {
        let source = PrefetchTransportByteSource()
        let reader = TransportIOReader(source: source)
        reachReadAhead(reader)
        await source.waitForPrefetch()
        XCTAssertEqual(reader.seek(offset: 80 * 1024 * 1024, whence: SEEK_SET), 80 * 1024 * 1024)
        XCTAssertEqual(reader.seek(offset: 8 * 1024 * 1024, whence: SEEK_SET), 8 * 1024 * 1024)
        source.finishPrefetch()
        XCTAssertEqual(read(reader, count: 16).data, Data(repeating: 9, count: 16))
        XCTAssertEqual(source.readLog.count, 3)
        reader.close()
        await reader.waitForFinalShutdown()
        XCTAssertEqual(source.cancelledReads, 1)
    }

    func testCachedForwardAndBackwardSeeksKeepUsefulReadAhead() async {
        let source = PrefetchTransportByteSource()
        let reader = TransportIOReader(source: source)
        reachReadAhead(reader)
        await source.waitForPrefetch()
        for offsetMiB in [25, 23, 30, 8, 39] {
            let offset = Int64(offsetMiB * 1024 * 1024)
            XCTAssertEqual(reader.seek(offset: offset, whence: SEEK_SET), offset)
            XCTAssertEqual(read(reader, count: 16).data, Data(repeating: 9, count: 16))
        }
        XCTAssertEqual(source.cancelledReads, 0)
        XCTAssertEqual(source.readLog.count, 3)
        source.finishPrefetch()
        XCTAssertEqual(reader.seek(offset: 40 * 1024 * 1024, whence: SEEK_SET), 40 * 1024 * 1024)
        XCTAssertEqual(read(reader, count: 16).data, Data((0..<16).map { UInt8($0) }))
        XCTAssertEqual(source.readLog.count, 3)
        reader.close()
        await reader.waitForFinalShutdown()
    }

    func testCachedSeeksDoNotRetryAFailedFutureWindow() async {
        let source = PrefetchTransportByteSource(failsPrefetch: true)
        let reader = TransportIOReader(source: source)
        reachReadAhead(reader)
        await source.waitForPrefetch()
        source.finishPrefetch()
        for offsetMiB in [25, 8, 30] {
            let offset = Int64(offsetMiB * 1024 * 1024)
            XCTAssertEqual(reader.seek(offset: offset, whence: SEEK_SET), offset)
            XCTAssertEqual(read(reader, count: 16).data, Data(repeating: 9, count: 16))
        }
        XCTAssertEqual(reader.seek(offset: 40 * 1024 * 1024, whence: SEEK_SET), 40 * 1024 * 1024)
        XCTAssertEqual(read(reader, count: 1).result, -1)
        XCTAssertEqual(source.readLog.count, 3)
        reader.close()
        await reader.waitForFinalShutdown()
    }

    func testExplicitCancellationStillCancelsReadAheadInsideTheCachedWindow() async {
        let source = PrefetchTransportByteSource()
        let reader = TransportIOReader(source: source)
        reachReadAhead(reader)
        await source.waitForPrefetch()
        reader.cancel()
        source.finishPrefetch()
        reader.close()
        await reader.waitForFinalShutdown()
        XCTAssertEqual(source.cancelledReads, 1)
    }

    func testSeekIntoReadAheadUsesCorrectOffsetWithoutDuplicatingTheRequest() async {
        let source = PrefetchTransportByteSource()
        let reader = TransportIOReader(source: source)
        reachReadAhead(reader)
        await source.waitForPrefetch()
        source.finishPrefetch()
        let offset: Int64 = 40 * 1024 * 1024 + 123
        XCTAssertEqual(reader.seek(offset: offset, whence: SEEK_SET), offset)
        XCTAssertEqual(read(reader, count: 17).data, Data((123..<140).map { UInt8($0) }))
        XCTAssertEqual(reader.seek(offset: 0, whence: SEEK_CUR), offset + 17)
        XCTAssertEqual(source.readLog.count, 3)
        reader.close()
        await reader.waitForFinalShutdown()
    }

    func testFailedReadAheadIsNotSilentlyRetriedOrReturnedAsEOF() async {
        let source = PrefetchTransportByteSource(failsPrefetch: true)
        let reader = TransportIOReader(source: source)
        reachReadAhead(reader)
        await source.waitForPrefetch()
        source.finishPrefetch()
        XCTAssertEqual(reader.seek(offset: 40 * 1024 * 1024, whence: SEEK_SET), 40 * 1024 * 1024)
        XCTAssertEqual(read(reader, count: 1).result, -1)
        XCTAssertEqual(read(reader, count: 1).result, -1)
        XCTAssertEqual(source.readLog.count, 3)
        reader.close()
        await reader.waitForFinalShutdown()
    }

    func testCloseCancelsPendingReadAheadAndDrainsItsSource() async {
        let source = PrefetchTransportByteSource()
        let reader = TransportIOReader(source: source)
        reachReadAhead(reader)
        await source.waitForPrefetch()
        reader.close()
        source.finishPrefetch()
        await reader.waitForFinalShutdown()
        XCTAssertEqual(source.cancelledReads, 1)
        XCTAssertEqual(read(reader, count: 1).result, -1)
        XCTAssertEqual(source.readLog.count, 3)
    }

    func testSparseProbeCachePreservesOffsetsPartialReadsAndCloneIndependence() throws {
        let payload = Data((0..<(512 * 1024)).map { UInt8($0 % 251) })
        let source = CappedTransportByteSource(
            payload, perReadCap: 64 * 1024, preferredReadSize: 32 * 1024 * 1024
        )
        let reader = TransportIOReader(source: source)
        defer { reader.close() }
        XCTAssertEqual(read(reader, count: 16).data, payload.prefix(16))
        XCTAssertEqual(reader.seek(offset: 256 * 1024, whence: SEEK_SET), 256 * 1024)
        XCTAssertEqual(read(reader, count: 16).data, payload.subdata(in: (256 * 1024)..<(256 * 1024 + 16)))
        XCTAssertEqual(reader.seek(offset: 8, whence: SEEK_SET), 8)
        XCTAssertEqual(read(reader, count: 16).data, payload.subdata(in: 8..<24))
        XCTAssertEqual(source.readCount, 2)
        XCTAssertEqual(reader.seek(offset: 65_530, whence: SEEK_SET), 65_530)
        XCTAssertEqual(read(reader, count: 16).data, payload.subdata(in: 65_530..<65_536))
        XCTAssertEqual(read(reader, count: 10).data, payload.subdata(in: 65_536..<65_546))
        XCTAssertEqual(source.readCount, 3)
        let clone = try XCTUnwrap(reader.makeIndependentReader())
        defer { clone.close() }
        XCTAssertEqual(read(clone, count: 16).data, payload.prefix(16))
        XCTAssertEqual(source.readCount, 4, "A clone starts with an independent empty cache")
    }

    func testSparseProbeCacheEvictsLeastRecentlyUsedBeyondEightWindows() {
        let source = SparseTransportByteSource(preferredReadSize: 32 * 1024 * 1024)
        let reader = TransportIOReader(source: source)
        defer { reader.close() }
        for index in 0..<8 {
            let offset = Int64(index * 128 * 1024)
            XCTAssertEqual(reader.seek(offset: offset, whence: SEEK_SET), offset)
            XCTAssertEqual(read(reader, count: 2).data, Data([42, 42]))
        }
        for index in [0, 8, 0, 1] {
            let offset = Int64(index * 128 * 1024)
            XCTAssertEqual(reader.seek(offset: offset, whence: SEEK_SET), offset)
            XCTAssertEqual(read(reader, count: 2).result, 2)
        }
        XCTAssertEqual(source.readLog.count, 10)
        XCTAssertEqual(source.readLog.last?.offset, 128 * 1024, "Window one, not recently used window zero, was evicted")
        XCTAssertTrue(source.readLog.allSatisfy { $0.length == 64 * 1024 })
    }

    func testAdaptiveWindowPreservesShortReadsAndEOF() {
        let payload = Data((0..<4096).map { UInt8($0 & 0xff) })
        let source = CappedTransportByteSource(
            payload, perReadCap: 1000, preferredReadSize: 32 * 1024 * 1024
        )
        let reader = TransportIOReader(source: source)
        defer { reader.close() }
        XCTAssertEqual(read(reader, count: 256).data, Data(payload.prefix(256)))
        XCTAssertEqual(source.readCount, 5)
        XCTAssertEqual(read(reader, count: 4096).data, Data(payload.dropFirst(256)))
        XCTAssertEqual(read(reader, count: 1).result, 0)
        XCTAssertEqual(source.readCount, 5)
    }

    func testLargeRangeReadsStartSmallGrowContiguouslyAndStayBounded() {
        let source = SparseTransportByteSource(preferredReadSize: 64 * 1024 * 1024)
        let reader = TransportIOReader(source: source)
        defer { reader.close() }
        XCTAssertEqual(read(reader, count: 2).data, Data([42, 42]))
        for _ in 0..<6 {
            let previous = source.readLog.last!
            let next = previous.offset + Int64(previous.length)
            XCTAssertEqual(reader.seek(offset: next, whence: SEEK_SET), next)
            XCTAssertEqual(read(reader, count: 2).data, Data([42, 42]))
        }
        XCTAssertEqual(source.readLog.map(\.length), [
            64 * 1024, 256 * 1024, 1024 * 1024, 4 * 1024 * 1024,
            16 * 1024 * 1024, 32 * 1024 * 1024, 32 * 1024 * 1024
        ])
    }

    func testLargeRangeRandomSeekAndCloneRestartSmallWithoutLosingCacheHits() throws {
        let source = SparseTransportByteSource(preferredReadSize: 32 * 1024 * 1024)
        let reader = TransportIOReader(source: source)
        defer { reader.close() }
        XCTAssertEqual(read(reader, count: 256 * 1024).result, 256 * 1024)
        XCTAssertEqual(read(reader, count: 2).result, 2)
        XCTAssertEqual(source.readLog.map(\.length), [256 * 1024, 1024 * 1024])
        XCTAssertEqual(reader.seek(offset: 64 * 1024 * 1024, whence: SEEK_SET), 64 * 1024 * 1024)
        XCTAssertEqual(read(reader, count: 2).data, Data([42, 42]))
        XCTAssertEqual(source.readLog.last?.length, 64 * 1024)
        let count = source.readLog.count
        XCTAssertEqual(reader.seek(offset: 64 * 1024 * 1024 + 1, whence: SEEK_SET), 64 * 1024 * 1024 + 1)
        XCTAssertEqual(read(reader, count: 2).data, Data([42, 42]))
        XCTAssertEqual(source.readLog.count, count)

        let clone = try XCTUnwrap(reader.makeIndependentReader())
        defer { clone.close() }
        XCTAssertEqual(read(clone, count: 2).data, Data([42, 42]))
        XCTAssertEqual(source.readLog.last?.offset, 0)
        XCTAssertEqual(source.readLog.last?.length, 64 * 1024)
        XCTAssertEqual(read(reader, count: 2).data, Data([42, 42]))
        XCTAssertEqual(source.readLog.count, count + 1)
    }

    func testOtherTransportsKeepExistingWindowAndRequestSizes() {
        let source = SparseTransportByteSource()
        let reader = TransportIOReader(source: source)
        defer { reader.close() }
        XCTAssertEqual(read(reader, count: 2).data, Data([42, 42]))
        XCTAssertEqual(source.readLog.map(\.length), Array(repeating: 1024 * 1024, count: 4))
        let expectedOffsets: [Int64] = [0, 1_048_576, 2_097_152, 3_145_728]
        XCTAssertEqual(source.readLog.map(\.offset), expectedOffsets)
    }

    /// Many small sequential reads within one window collapse to a single
    /// underlying transport round-trip (the cold-start latency win).
    func testSequentialSmallReadsCoalesceIntoOneFetch() {
        let payload = Data((0..<4096).map { UInt8($0 & 0xFF) })
        let source = CountingTransportByteSource(payload)
        let reader = TransportIOReader(source: source, readAheadWindow: 4096)

        var assembled = Data()
        for _ in 0..<16 { // 16 × 256B = 4096B, exactly one window
            assembled.append(read(reader, count: 256).data)
        }
        XCTAssertEqual(assembled, payload, "bytes are served intact from the window")
        XCTAssertEqual(source.readCount, 1, "one underlying fetch served all 16 demux reads")
        XCTAssertEqual(source.readLog.first?.length, 4096, "the fetch requested a full window, not 256B")
    }

    /// A backend that caps each read below the window still fills a full window by
    /// concatenating partial reads — the data is intact and ffmpeg sees one window.
    func testWindowFillConcatenatesCappedBackendReads() {
        let payload = Data((0..<4096).map { UInt8($0 & 0xFF) })
        let source = CappedTransportByteSource(payload, perReadCap: 1000)
        let reader = TransportIOReader(source: source, readAheadWindow: 4096)

        // One 256B demux read triggers a window fill of 4096B via 1000B pieces.
        XCTAssertEqual(read(reader, count: 256).data, Data(payload[0..<256]))
        XCTAssertEqual(source.readCount, 5, "4096B window filled by 1000+1000+1000+1000+96")

        // The rest of the window serves from cache (no more transport reads).
        var assembled = Data(payload[0..<256])
        for _ in 0..<15 { assembled.append(read(reader, count: 256).data) }
        XCTAssertEqual(assembled, payload, "concatenated window bytes are intact")
        XCTAssertEqual(source.readCount, 5, "remaining demux reads all served from cache")
    }

    /// Crossing the window boundary triggers exactly one more fetch, and the
    /// reassembled bytes are correct across the seam.
    func testCrossingWindowBoundaryFetchesNextWindow() {
        let payload = Data((0..<3000).map { UInt8($0 & 0xFF) })
        let source = CountingTransportByteSource(payload)
        let reader = TransportIOReader(source: source, readAheadWindow: 1024)

        var assembled = Data()
        while true {
            let (result, chunk) = read(reader, count: 256)
            if result <= 0 { break }
            assembled.append(chunk)
        }
        XCTAssertEqual(assembled, payload, "bytes are intact across window seams")
        // 3000 bytes / 1024 window = 3 windows (1024 + 1024 + 952).
        XCTAssertEqual(source.readCount, 3, "one fetch per window, no per-256B round-trips")
    }

    /// A seek inside the cached window serves from memory (no new fetch); a seek
    /// outside it triggers a fresh fetch.
    func testSeekWithinWindowServesFromCacheSeekOutsideRefetches() {
        let payload = Data((0..<8192).map { UInt8($0 & 0xFF) })
        let source = CountingTransportByteSource(payload)
        let reader = TransportIOReader(source: source, readAheadWindow: 4096)

        XCTAssertEqual(read(reader, count: 16).data, Data(payload[0..<16]))
        XCTAssertEqual(source.readCount, 1)

        // Seek within the [0,4096) window — still served from cache.
        XCTAssertEqual(reader.seek(offset: 1000, whence: SEEK_SET), 1000)
        XCTAssertEqual(read(reader, count: 16).data, Data(payload[1000..<1016]))
        XCTAssertEqual(source.readCount, 1, "in-window seek does not hit the transport")

        // Seek beyond the window — one fresh fetch.
        XCTAssertEqual(reader.seek(offset: 6000, whence: SEEK_SET), 6000)
        XCTAssertEqual(read(reader, count: 16).data, Data(payload[6000..<6016]))
        XCTAssertEqual(source.readCount, 2, "out-of-window seek refetches")
    }

    /// A read whose span exceeds what remains in the already-cached window returns
    /// only the buffered prefix (a valid short read); the next read fetches the
    /// following window. (On a miss the window is fetched starting at the read
    /// offset, so only reads served from an existing window can be short.)
    func testReadPastCachedWindowTailReturnsPrefixThenRefetches() {
        let payload = Data((0..<2048).map { UInt8($0 & 0xFF) })
        let source = CountingTransportByteSource(payload)
        let reader = TransportIOReader(source: source, readAheadWindow: 1024)

        // Establish a window at [0,1024) with a small read.
        XCTAssertEqual(read(reader, count: 16).data, Data(payload[0..<16]))
        XCTAssertEqual(source.readCount, 1)

        // Seek to 900 (still inside the cached window) and ask for 800: only 124
        // bytes remain in the window, so expect a 124-byte short read from cache.
        XCTAssertEqual(reader.seek(offset: 900, whence: SEEK_SET), 900)
        let first = read(reader, count: 800)
        XCTAssertEqual(first.data, Data(payload[900..<1024]))
        XCTAssertEqual(source.readCount, 1, "the short read was served from cache, no fetch")

        // Next read at 1024 refetches the following window.
        let second = read(reader, count: 800)
        XCTAssertEqual(second.data, Data(payload[1024..<1824]))
        XCTAssertEqual(source.readCount, 2)
    }

    /// On a miss the fetched window starts at the read offset, so a large read is
    /// fully served in one shot (no artificial short read at a fixed grid).
    func testMissFetchesWindowStartingAtReadOffset() {
        let payload = Data((0..<4096).map { UInt8($0 & 0xFF) })
        let source = CountingTransportByteSource(payload)
        let reader = TransportIOReader(source: source, readAheadWindow: 1024)

        XCTAssertEqual(reader.seek(offset: 500, whence: SEEK_SET), 500)
        let chunk = read(reader, count: 800) // 800 ≤ window, fully served
        XCTAssertEqual(chunk.data, Data(payload[500..<1300]))
        XCTAssertEqual(source.readCount, 1)
        XCTAssertEqual(source.readLog.first?.offset, 500, "window is anchored at the read offset")
    }
}

final class TransportIOReaderTests: XCTestCase {
    private let payload = Data((0..<256).map { UInt8($0) })

    func testSequentialReadAdvancesCursor() {
        let reader = TransportIOReader(source: FakeTransportByteSource(payload))

        XCTAssertEqual(read(reader, count: 4).data, Data([0, 1, 2, 3]))
        XCTAssertEqual(read(reader, count: 4).data, Data([4, 5, 6, 7]))
    }

    func testSeekModesAndSizeQuery() {
        let reader = TransportIOReader(source: FakeTransportByteSource(payload))

        XCTAssertEqual(reader.seek(offset: 10, whence: SEEK_SET), 10)
        XCTAssertEqual(reader.seek(offset: 5, whence: SEEK_CUR), 15)
        XCTAssertEqual(reader.seek(offset: -1, whence: SEEK_END), 255)
        XCTAssertEqual(reader.seek(offset: 0, whence: 65_536), 256)
        XCTAssertEqual(read(reader, count: 1).data, Data([255]))
    }

    func testEOFAndSpanningRead() {
        let reader = TransportIOReader(source: FakeTransportByteSource(payload))

        XCTAssertEqual(reader.seek(offset: 254, whence: SEEK_SET), 254)
        XCTAssertEqual(read(reader, count: 16).data, Data([254, 255]))
        XCTAssertEqual(read(reader, count: 1).result, 0)
    }

    func testInvalidSeekDoesNotMoveCursor() {
        let reader = TransportIOReader(source: FakeTransportByteSource(payload))

        XCTAssertEqual(reader.seek(offset: 10, whence: SEEK_SET), 10)
        XCTAssertLessThan(reader.seek(offset: -999, whence: SEEK_SET), 0)
        XCTAssertLessThan(reader.seek(offset: 0, whence: 999), 0)
        XCTAssertEqual(read(reader, count: 2).data, Data([10, 11]))
    }

    func testOverflowingRelativeSeekDoesNotMoveCursor() {
        let reader = TransportIOReader(source: FakeTransportByteSource(payload))

        XCTAssertEqual(reader.seek(offset: 10, whence: SEEK_SET), 10)
        XCTAssertEqual(reader.seek(offset: Int64.max, whence: SEEK_CUR), -1)
        XCTAssertEqual(read(reader, count: 2).data, Data([10, 11]))
        XCTAssertEqual(reader.seek(offset: Int64.max, whence: SEEK_END), -1)
        XCTAssertEqual(read(reader, count: 2).data, Data([12, 13]))
    }

    func testReadFailureReturnsNegative() {
        let source = FakeTransportByteSource(payload)
        source.failReads()
        let reader = TransportIOReader(source: source)

        XCTAssertLessThan(read(reader, count: 4).result, 0)
    }

    func testDemandReadCanRecoverWithoutAStickyPrefetchFailure() {
        let source = FakeTransportByteSource(payload)
        source.failReads()
        let reader = TransportIOReader(source: source)
        defer { reader.close() }
        XCTAssertEqual(read(reader, count: 4).result, -1)
        source.resumeReads()
        XCTAssertEqual(read(reader, count: 4).data, Data([0, 1, 2, 3]))
    }

    func testSourceClosesOnceAfterEveryReaderCloses() async throws {
        let source = FakeTransportByteSource(payload)
        let primary = TransportIOReader(source: source)
        let independent = try XCTUnwrap(primary.makeIndependentReader())

        XCTAssertTrue(primary.discImageProbeEnabled)
        XCTAssertTrue(independent.discImageProbeEnabled)
        primary.close()
        primary.close()
        XCTAssertEqual(source.closeCount, 0)

        independent.close()
        await primary.waitForFinalShutdown()
        XCTAssertEqual(source.closeCount, 1)
        XCTAssertNil(primary.makeIndependentReader())
    }

    func testCloseWaitsForIndependentInflightReadToDrain() async throws {
        let source = BlockingTransportByteSource()
        let primary = TransportIOReader(source: source)
        let independent = try XCTUnwrap(primary.makeIndependentReader())
        let readTask = Task.detached { read(independent, count: 1).result }
        await source.waitUntilReadStarts()

        primary.close()
        independent.close()
        XCTAssertEqual(source.closeCount, 0)
        let cancelledResult = await readTask.value
        XCTAssertEqual(cancelledResult, -1)

        source.finishRead()
        await primary.waitForFinalShutdown()
        XCTAssertEqual(source.closeCount, 1)
    }

    func testPlaybackEndDrainsWhileStillExtractorAndClonedReadersRemainAlive() async throws {
        let source = FakeTransportByteSource(payload)
        let primary = TransportIOReader(source: source)
        let clone = try XCTUnwrap(primary.makeIndependentReader())
        let descendant = try XCTUnwrap(clone.makeIndependentReader())
        let extractor = FrameExtractor(reader: clone)

        primary.closeAllReaders()
        primary.closeAllReaders()
        let drained = expectation(description: "source drained before preview host disappears")
        let drain = Task {
            await primary.waitForFinalShutdown()
            drained.fulfill()
        }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(source.closeCount, 1)
        XCTAssertNil(primary.makeIndependentReader())
        XCTAssertNil(clone.makeIndependentReader())
        XCTAssertLessThan(read(descendant, count: 1).result, 0)
        await extractor.shutdown()
        await drain.value
    }

    func testPlaybackEndUnblocksPreviewReadWithoutClosingAnotherSession() async throws {
        let source = BlockingTransportByteSource()
        let primary = TransportIOReader(source: source)
        let clone = try XCTUnwrap(primary.makeIndependentReader())
        let otherSource = FakeTransportByteSource(payload)
        let other = TransportIOReader(source: otherSource)
        let readTask = Task.detached { read(clone, count: 1).result }
        await source.waitUntilReadStarts()

        primary.closeAllReaders()
        let result = await readTask.value
        XCTAssertEqual(result, -1)
        XCTAssertEqual(read(other, count: 1).data, Data([0]))
        XCTAssertEqual(otherSource.closeCount, 0)
        source.finishRead()
        await primary.waitForFinalShutdown()
        XCTAssertEqual(source.closeCount, 1)
        other.closeAllReaders()
        await other.waitForFinalShutdown()
    }

    func testCancelUnblocksReadWhileUnderlyingOperationDrains() async {
        for preferredReadSize in [1024 * 1024, 32 * 1024 * 1024] {
            let source = BlockingTransportByteSource(preferredReadSize: preferredReadSize)
            let reader = TransportIOReader(source: source)
            let readTask = Task.detached { read(reader, count: 1).result }
            await source.waitUntilReadStarts()

            reader.cancel()
            let cancelledResult = await readTask.value
            XCTAssertEqual(cancelledResult, -1)

            source.finishRead()
            XCTAssertEqual(read(reader, count: 1).data, Data([42]))

            reader.close()
            await reader.waitForFinalShutdown()
            XCTAssertEqual(source.closeCount, 1)
        }

    }

    func testSeekUnblocksPendingDemandWithoutReturningStaleBytes() async {
        let source = BlockingTransportByteSource(preferredReadSize: 32 * 1024 * 1024)
        let reader = TransportIOReader(source: source)
        let pending = Task.detached { read(reader, count: 1) }
        await source.waitUntilReadStarts()
        XCTAssertEqual(reader.seek(offset: 1, whence: SEEK_SET), 1)
        let result = await pending.value
        XCTAssertEqual(result.result, -1)
        XCTAssertTrue(result.data.isEmpty)
        XCTAssertEqual(reader.seek(offset: 0, whence: SEEK_CUR), 1)
        source.finishRead()
        reader.close()
        await reader.waitForFinalShutdown()
    }
}
#endif
