import CoreModels
import Foundation
import XCTest
@testable import ProviderIPTV

final class IPTVPlaybackRecoveryTests: XCTestCase {
    override func tearDown() {
        IPTVFixture.state.reset()
        super.tearDown()
    }

    func testCooldownSuppressesRequestsUntilTheDeadlineWithoutExtendingIt() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        for status in [429, 509] {
            IPTVFixture.state.reset()
            let clock = ProxyClock()
            IPTVFixture.state.handler = { _ in
                IPTVFixture.state.requests.count == 1
                    ? (status, ["Retry-After": "10"], Data())
                    : (200, [:], Data("recovered".utf8))
            }
            let proxy = try IPTVPlaybackProxy(
                origin: XCTUnwrap(URL(string: "https://provider.test/live.ts")),
                headers: [:], configuration: IPTVFixture.configuration(), uptime: { clock.now }
            )
            addTeardownBlock { await proxy.stop() }
            let url = try await proxy.start()
            _ = try await session.data(from: url)
            clock.set(109.1)
            for _ in 0..<4 {
                let (_, response) = try await session.data(from: url)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, status)
                XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After"), "1")
            }
            XCTAssertEqual(IPTVFixture.state.requests.count, 1)
            clock.set(110)
            let (data, response) = try await session.data(from: url)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(data, Data("recovered".utf8))
            XCTAssertEqual(IPTVFixture.state.requests.count, 2)
            XCTAssertNil(PlaybackDeliveryFailure.state(for: url)?.error)
            await proxy.stop()
        }
    }

    func testExpiredHTTPDateAllowsRecoveryAndMalformedDelayStillSuppressesFallback() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        for header in ["Sun, 06 Nov 1994 08:49:37 GMT", "invalid", "-1", "nan"] {
            IPTVFixture.state.reset()
            IPTVFixture.state.handler = { _ in
                IPTVFixture.state.requests.count == 1
                    ? (429, ["Retry-After": header], Data())
                    : (200, [:], Data(repeating: 0x47, count: 188))
            }
            let proxy = try IPTVPlaybackProxy(
                origin: XCTUnwrap(URL(string: "https://provider.test/live.ts")),
                headers: [:], configuration: IPTVFixture.configuration()
            )
            addTeardownBlock { await proxy.stop() }
            let url = try await proxy.start()
            _ = try await session.data(from: url)
            let (_, response) = try await session.data(from: url)
            let expired = header.hasPrefix("Sun,")
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, expired ? 200 : 429)
            XCTAssertEqual(IPTVFixture.state.requests.count, expired ? 2 : 1)
            await proxy.stop()
        }
    }

    func testConcurrentHLSRefusalsCannotShortenAnExistingCooldown() async throws {
        let entered = expectation(description: "Both HLS requests reached the origin before either refusal")
        entered.expectedFulfillmentCount = 2
        let server = try IPTVTestHTTPServer { request in
            if request.contains(".m3u8 ") {
                return .init(data: Data("""
                #EXTM3U
                #EXT-X-TARGETDURATION:2
                #EXTINF:2,
                first.ts
                #EXTINF:2,
                second.ts

                """.utf8), headers: ["Content-Type": "application/vnd.apple.mpegurl"])
            }
            entered.fulfill()
            let first = request.contains("/first.ts ")
            return .init(
                status: 429, headers: ["Retry-After": first ? "10" : "1"],
                headerDelay: first ? .milliseconds(250) : .milliseconds(500)
            )
        }
        addTeardownBlock { await server.stop() }
        let clock = ProxyClock()
        let origin = try await server.start().appendingPathComponent("live.m3u8")
        let proxy = try IPTVPlaybackProxy(origin: origin, headers: [:], uptime: { clock.now })
        addTeardownBlock { await proxy.stop() }
        let url = try await proxy.start()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (manifest, _) = try await session.data(from: url)
        let children = String(decoding: manifest, as: UTF8.self).components(separatedBy: .newlines)
            .filter { $0.hasPrefix("http://") }.compactMap(URL.init(string:))
        XCTAssertEqual(children.count, 2)
        guard children.count == 2 else { return }
        async let first = session.data(from: children[0])
        async let second = session.data(from: children[1])
        await fulfillment(of: [entered], timeout: 2)
        let responses = try await [first.1, second.1]
        XCTAssertTrue(responses.allSatisfy { ($0 as? HTTPURLResponse)?.statusCode == 429 })
        clock.set(102)
        let (_, throttled) = try await session.data(from: url)
        XCTAssertEqual((throttled as? HTTPURLResponse)?.statusCode, 429)
        XCTAssertEqual((throttled as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After"), "8")
        let requestsDuringCooldown = await server.requestCount
        XCTAssertEqual(requestsDuringCooldown, 3)
        clock.set(110)
        let (_, recovered) = try await session.data(from: url)
        XCTAssertEqual((recovered as? HTTPURLResponse)?.statusCode, 200)
    }

    func testRecoveryRetainsANewAuthorizationRefusalInsteadOfTheOldThrottle() async throws {
        IPTVFixture.state.handler = { _ in
            IPTVFixture.state.requests.count == 1 ? (429, ["Retry-After": "0"], Data()) : (401, [:], Data())
        }
        let proxy = try IPTVPlaybackProxy(
            origin: XCTUnwrap(URL(string: "https://provider.test/live.ts")),
            headers: [:], configuration: IPTVFixture.configuration()
        )
        addTeardownBlock { await proxy.stop() }
        let url = try await proxy.start()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        for _ in 0..<3 { _ = try await session.data(from: url) }
        XCTAssertEqual(IPTVFixture.state.requests.count, 2)
        XCTAssertEqual(PlaybackDeliveryFailure.state(for: url)?.error, .unauthorized)
        XCTAssertEqual(PlaybackDeliveryFailure.state(for: url)?.diagnostic?.httpStatus, 401)
    }

    func testRepeatedRefusalStartsANewCooldownWithoutAutomaticRequests() async throws {
        let clock = ProxyClock()
        IPTVFixture.state.handler = { _ in
            switch IPTVFixture.state.requests.count {
            case 1: (429, ["Retry-After": "10"], Data())
            case 2: (429, ["Retry-After": "5"], Data())
            default: (200, [:], Data(repeating: 0x47, count: 188))
            }
        }
        let proxy = try IPTVPlaybackProxy(
            origin: XCTUnwrap(URL(string: "https://provider.test/live.ts")),
            headers: [:], configuration: IPTVFixture.configuration(), uptime: { clock.now }
        )
        addTeardownBlock { await proxy.stop() }
        let url = try await proxy.start()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        _ = try await session.data(from: url)
        clock.set(110)
        _ = try await session.data(from: url)
        clock.set(114)
        let (_, coolingDown) = try await session.data(from: url)
        XCTAssertEqual((coolingDown as? HTTPURLResponse)?.statusCode, 429)
        XCTAssertEqual(IPTVFixture.state.requests.count, 2)
        clock.set(115)
        let (_, recovered) = try await session.data(from: url)
        XCTAssertEqual((recovered as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(IPTVFixture.state.requests.count, 3)
    }

    func testOrdinaryMalformedOversizedAndNonJSON503BodiesDoNotClaimCapacityExhaustion() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let capacity = #"{"error":"maximum connection limits"}"#
        for (mime, body) in [
            ("application/json", #"{"error":"Channel is stopping, retry shortly"}"#),
            ("application/json", "maximum connection limits"),
            ("application/json", #"{"detail":"maximum connection limits"}"#),
            ("application/json", capacity + String(repeating: " ", count: 4_096)),
            ("text/html", capacity)
        ] {
            IPTVFixture.state.reset()
            IPTVFixture.state.handler = { _ in (503, ["Content-Type": mime], Data(body.utf8)) }
            let proxy = try IPTVPlaybackProxy(
                origin: XCTUnwrap(URL(string: "https://provider.test/live.ts")),
                headers: [:], configuration: IPTVFixture.configuration()
            )
            addTeardownBlock { await proxy.stop() }
            let url = try await proxy.start()
            for _ in 0..<2 {
                let (body, response) = try await session.data(from: url)
                XCTAssertTrue(body.isEmpty)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 503)
            }
            XCTAssertNil(PlaybackDeliveryFailure.state(for: url)?.error)
            XCTAssertEqual(IPTVFixture.state.requests.count, 2, "An ordinary 503 must not become a terminal refusal.")
            await proxy.stop()
        }
    }

    func testOptionalRefusalInspectionHasATimeBoundAndStopCancelsIt() async throws {
        for stopEarly in [false, true] {
            let chunks = RefusalBodyChunks()
            let server = try IPTVTestHTTPServer(beforeBodyChunk: {
                if await chunks.next() == 2 { try await Task.sleep(for: .seconds(6)) }
            }) { _ in
                .init(
                    data: Data(#"{"error":"maximum connection limits"}"#.utf8),
                    status: 503, headers: ["Content-Type": "application/json"], chunkSize: 8
                )
            }
            addTeardownBlock { await server.stop() }
            let origin = try await server.start().appendingPathComponent("live.ts")
            let proxy = try IPTVPlaybackProxy(origin: origin, headers: [:])
            addTeardownBlock { await proxy.stop() }
            let url = try await proxy.start()
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let began = ContinuousClock.now
            let request = Task { try await session.data(from: url) }
            defer { request.cancel() }
            let deadline = ContinuousClock.now + .seconds(3)
            while await server.requestCount == 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let requests = await server.requestCount
            XCTAssertEqual(requests, 1)
            if stopEarly {
                await proxy.stop()
                do {
                    _ = try await request.value
                    XCTFail("Stopped inspection must not deliver success.")
                } catch {
                    XCTAssertTrue(error is URLError || error is CancellationError)
                }
            } else {
                let (body, response) = try await request.value
                XCTAssertTrue(body.isEmpty)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 503)
                XCTAssertNil(PlaybackDeliveryFailure.state(for: url)?.error)
                await proxy.stop()
            }
            XCTAssertLessThan(began.duration(to: .now), .seconds(3))
            await server.stop()
        }
    }
}

private actor RefusalBodyChunks {
    private var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}

private final class ProxyClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 100
    var now: TimeInterval { lock.withLock { value } }
    func set(_ value: TimeInterval) { lock.withLock { self.value = value } }
}
