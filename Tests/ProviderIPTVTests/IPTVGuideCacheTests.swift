import CoreModels
import Foundation
import XCTest
@testable import ProviderIPTV

final class IPTVGuideCacheTests: XCTestCase {
    private let guide = URL(string: "https://cdn.test/guide.xml")!

    override func tearDown() {
        IPTVFixture.state.reset()
        super.tearDown()
    }

    private func client() throws -> IPTVClient {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let client = try IPTVClient(
            credential: IPTVCredential(
                mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test/list.m3u")),
                headers: ["X-Playlist-Key": "playlist-only"], guideURL: guide,
                guideHeaders: ["X-Guide-Key": "guide-only"]
            ),
            directory: root, configuration: IPTVFixture.configuration()
        )
        addTeardownBlock { await client.cancel() }
        return client
    }

    func testLargeGuideIsReusedAndHeldBytesSurviveCacheCancellation() async throws {
        let body = Data(repeating: 0x61, count: 17 * 1_024 * 1_024)
        IPTVFixture.state.handler = { _ in (200, ["Cache-Control": "max-age=60"], body) }
        let client = try client()
        let first = try await client.guideData(from: guide)
        let second = try await client.guideData(from: guide)
        XCTAssertEqual(first, body)
        XCTAssertEqual(second, body)
        XCTAssertEqual(IPTVFixture.state.requests.count, 1)
        XCTAssertEqual(IPTVFixture.state.requests[0].value(forHTTPHeaderField: "X-Guide-Key"), "guide-only")
        XCTAssertNil(IPTVFixture.state.requests[0].value(forHTTPHeaderField: "X-Playlist-Key"))
        let retained = await client.cachedGuideByteCount
        XCTAssertEqual(retained, body.count)
        await client.cancel()
        let cleared = await client.cachedGuideByteCount
        XCTAssertEqual(cleared, 0)
        XCTAssertEqual(second, body)
    }

    func testLargeGuideRespectsNoStoreNoCacheAndZeroMaxAge() async throws {
        let body = Data(repeating: 0x62, count: 17 * 1_024 * 1_024)
        for directive in ["no-store", "no-cache", "max-age=0"] {
            IPTVFixture.state.reset()
            IPTVFixture.state.handler = { _ in (200, ["Cache-Control": directive], body) }
            let client = try client()
            for _ in 0..<2 {
                let value = try await client.guideData(from: guide)
                XCTAssertEqual(value, body)
            }
            let retained = await client.cachedGuideByteCount
            XCTAssertEqual(retained, 0)
            XCTAssertEqual(IPTVFixture.state.requests.count, 2)
            await client.cancel()
        }
    }

    func testExpiredCacheReleasesBackingWithoutAnotherRequest() async throws {
        IPTVFixture.state.handler = { _ in (200, ["Cache-Control": "max-age=0.05"], Data("<tv/>".utf8)) }
        let client = try client()
        _ = try await client.guideData(from: guide)
        let deadline = ContinuousClock.now + .seconds(2)
        while await client.cachedGuideByteCount != 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let retained = await client.cachedGuideByteCount
        XCTAssertEqual(retained, 0)
        XCTAssertEqual(IPTVFixture.state.requests.count, 1)
        _ = try await client.guideData(from: guide)
        XCTAssertEqual(IPTVFixture.state.requests.count, 2)
    }

    func testOldExpiryDoesNotClearReplacementAndClientsNeverShareCachedGuides() async throws {
        IPTVFixture.state.handler = { request in
            (200, ["Cache-Control": request.url?.lastPathComponent == "guide.xml" ? "max-age=0.05" : "max-age=60"],
             Data("<tv/>".utf8))
        }
        let first = try client()
        let second = try client()
        _ = try await first.guideData(from: guide)
        let replacement = guide.deletingLastPathComponent().appendingPathComponent("replacement.xml")
        _ = try await first.guideData(from: replacement)
        _ = try await second.guideData(from: replacement)
        try await Task.sleep(for: .milliseconds(100))
        _ = try await first.guideData(from: replacement)
        let retained = await first.cachedGuideByteCount
        XCTAssertEqual(retained, 5)
        XCTAssertEqual(IPTVFixture.state.requests.count, 3)
    }
}
