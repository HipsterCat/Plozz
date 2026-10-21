import CoreModels
import Foundation
import XCTest
@testable import ProviderIPTV

final class IPTVAutomaticGuideTests: XCTestCase {
    override func tearDown() {
        IPTVFixture.state.reset()
        super.tearDown()
    }

    private func savedClient(guides: [URL] = []) throws -> (IPTVClient, IPTVCredential, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let credential = try IPTVCredential.decode(IPTVCredential(
            mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test/list")),
            guideURL: guides.first, additionalGuideURLs: Array(guides.dropFirst()),
            discoversPlaylistGuides: false
        ).encoded())
        do {
            let saved = try IPTVCatalog(
                url: root.appendingPathComponent(credential.identity.uuidString + ".sqlite"), key: credential.catalogKey
            )
            try saved.insert(IPTVRecord(
                item: .init(id: "live:saved", title: "Saved channel", kind: .video, libraryID: "live"),
                streamURL: URL(string: "https://provider.test/live/1.ts"), isLive: true
            ))
            try saved.setState("playlist-v4", String(Date().timeIntervalSince1970))
        }
        let client = try IPTVClient(credential: credential, directory: root, configuration: IPTVFixture.configuration())
        addTeardownBlock { await client.cancel() }
        return (client, credential, root)
    }

    func testOldOptOutRefreshesOnceWithoutBlockingOrDuplicatingSavedChannels() async throws {
        for includesGuide in [true, false] {
            IPTVFixture.state.reset()
            let (client, credential, root) = try savedClient()
            let guide = try XCTUnwrap(URL(string: "https://cdn.test/guide.xml"))
            let entered = expectation(description: "One automatic guide discovery refresh")
            let gate = DispatchSemaphore(value: 0)
            defer { gate.signal() }
            IPTVFixture.state.handler = { _ in
                entered.fulfill()
                guard gate.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
                let header = includesGuide ? "#EXTM3U x-tvg-url=\"\(guide.absoluteString)\"" : "#EXTM3U"
                return (200, [:], Data("\(header)\n#EXTINF:-1,Updated channel\nhttps://provider.test/live/1.ts\n".utf8))
            }
            let channels = try await client.liveChannels()
            XCTAssertEqual(channels.map(\.id), ["live:saved"])
            await fulfillment(of: [entered], timeout: 3)
            let delivery = try await client.delivery("live:saved")
            XCTAssertEqual(delivery.url.path, "/live/1.ts")
            gate.signal()
            let deadline = ContinuousClock.now + .seconds(5)
            var updated: [ServerLiveTVChannel] = []
            while ContinuousClock.now < deadline {
                updated = try await client.liveChannels()
                if updated.first?.name == "Updated channel" { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(updated.map(\.name), ["Updated channel"])
            let found = try await client.guideURLs()
            XCTAssertEqual(found, includesGuide ? [guide] : [])
            XCTAssertEqual(IPTVFixture.state.requests.count, 1)
            await client.cancel()

            let restored = try IPTVClient(
                credential: credential, directory: root, configuration: IPTVFixture.configuration()
            )
            addTeardownBlock { await restored.cancel() }
            for _ in 0..<3 {
                let found = try await restored.guideURLs()
                XCTAssertEqual(found, includesGuide ? [guide] : [])
            }
            XCTAssertEqual(IPTVFixture.state.requests.count, 1, "No-guide playlists must not refresh indefinitely.")
            await restored.cancel()
        }
    }

    func testExistingCustomGuidesKeepTheirOrderAndDoNotTriggerDiscoveryRefresh() async throws {
        let guides = [
            try XCTUnwrap(URL(string: "https://cdn.test/custom.xml")),
            try XCTUnwrap(URL(string: "https://cdn.test/extra.xml"))
        ]
        let (client, credential, _) = try savedClient(guides: guides)
        let channels = try await client.liveChannels()
        let found = try await client.guideURLs()
        XCTAssertEqual(channels.map(\.id), ["live:saved"])
        XCTAssertEqual(found, guides)
        XCTAssertEqual(credential.explicitGuideURLs, guides)
        XCTAssertTrue(IPTVFixture.state.requests.isEmpty)

        IPTVFixture.state.handler = { _ in
            (200, [:], Data("""
            #EXTM3U x-tvg-url="https://cdn.test/automatic.xml"
            #EXTINF:-1,Updated channel
            https://provider.test/live/1.ts

            """.utf8))
        }
        try await client.ensureCatalog("live", force: true)
        let afterRefresh = try await client.guideURLs()
        XCTAssertEqual(afterRefresh, guides)
        XCTAssertEqual(IPTVFixture.state.requests.count, 1)
    }

    func testFailedAutomaticDiscoveryPreservesPlaybackAndRefreshBackoff() async throws {
        let (client, _, _) = try savedClient()
        let entered = expectation(description: "Automatic refresh begins")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        IPTVFixture.state.handler = { _ in
            entered.fulfill()
            guard gate.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
            return (503, [:], Data())
        }
        _ = try await client.liveChannels()
        await fulfillment(of: [entered], timeout: 3)
        let waiter = Task { try await client.ensureCatalog("live", force: true) }
        let deadline = ContinuousClock.now + .seconds(3)
        while await client.pendingCatalogRequestCount != 1, ContinuousClock.now < deadline {
            await Task.yield()
        }
        let waiting = await client.pendingCatalogRequestCount
        XCTAssertEqual(waiting, 1)
        gate.signal()
        do {
            try await waiter.value
            XCTFail("Failed discovery must remain an explicit refresh error.")
        } catch { XCTAssertEqual(error as? IPTVError, .httpStatus(503)) }
        for _ in 0..<3 {
            let channels = try await client.liveChannels()
            XCTAssertEqual(channels.map(\.id), ["live:saved"])
        }
        XCTAssertEqual(IPTVFixture.state.requests.count, 1)
    }
}
