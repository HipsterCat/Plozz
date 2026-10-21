import CoreModels
import CoreNetworking
import Foundation
import XCTest
@testable import ProviderPlex

final class PlexAlternateAddressTests: XCTestCase {
    func testRetiredSweepCannotStartAnAuthenticatedProbeToARemovedAlias() async throws {
        let original = URL(string: "http://192.168.1.50:32400")!
        let removed = URL(string: "https://remote.test")!
        let http = HeldPlexAddressHTTP(primary: original)
        addTeardownBlock { await http.release() }
        let server = MediaServer(id: UUID().uuidString, name: "Home", baseURL: original, provider: .plex,
                                 alternateConnectionURLs: [removed])
        let provider = PlexProvider(session: UserSession(server: server, userID: "viewer", userName: "Viewer",
            deviceID: "device", accessToken: "credential"), http: http, probe: http)
        let request = Task { try await provider.resolveAuthenticatedHTTPOrigin() }
        await http.waitUntilHeld()
        provider.updateServerAddresses([])
        await http.release()
        let selected = try await request.value
        XCTAssertEqual(selected, original)
        let requests = await http.requests
        XCTAssertFalse(requests.contains(removed), "Retired sweeps must not send the saved token to removed aliases")
    }

    func testAddressEditKeepsLatestDiscoveredRouteWhenPlexDiscoveryIsOffline() async throws {
        let id = UUID().uuidString
        defer {
            UserDefaults.standard.removeObject(forKey: "plex.reachable.\(id)")
            UserDefaults.standard.removeObject(forKey: "plex.artwork-origins.\(id)")
        }
        let original = URL(string: "https://old.test")!
        let removed = URL(string: "https://obsolete.test")!
        let learned = URL(string: "https://learned.test")!
        let http = DiscoveredPlexAddressHTTP(learned: learned)
        let server = MediaServer(id: id, name: "Home", baseURL: original, provider: .plex,
                                 alternateConnectionURLs: [removed])
        let provider = PlexProvider(session: UserSession(server: server, userID: "viewer", userName: "Viewer",
            deviceID: "device", accessToken: "credential"), http: http,
            connectionRefresh: { await http.discover() }, probe: http)
        let before = try await provider.resolveAuthenticatedHTTPOrigin()
        XCTAssertEqual(before, learned)
        provider.updateServerAddresses([])
        let after = try await provider.resolveAuthenticatedHTTPOrigin()
        XCTAssertEqual(after, learned)
        let discoveries = await http.discoveries
        XCTAssertEqual(discoveries, 1, "An already learned reachable route must not depend on another discovery call")
    }

    func testPlaybackLocatorDropsOnlyTheMatchingProxyPrefixAndKeepsEncodedPathBytes() throws {
        let root = URL(string: "https://plex.test")!
        let proxy = URL(string: "https://plex.test/proxy%20path")!
        let server = MediaServer(id: UUID().uuidString, name: "Home", baseURL: root, provider: .plex,
                                 alternateConnectionURLs: [proxy])
        let provider = PlexProvider(session: UserSession(server: server, userID: "viewer", userName: "Viewer",
                                                         deviceID: "device", accessToken: "credential"))
        for base in [root, proxy] {
            let url = URL(string: base.absoluteString + "/library/parts/movie%20name%2Bpart/file.mp4?X-Plex-Token=old&quality=1")!
            let locator = try provider.authenticatedPlaybackLocator(itemID: "movie", mediaSourceID: nil,
                url: url, deliveryMode: .directFile, purpose: .originalFile, playSessionID: nil, formatHint: "mp4")
            XCTAssertEqual(locator.resource.pathBase, .configuredBaseURL)
            XCTAssertEqual(locator.resource.path, "library/parts/movie%20name%2Bpart/file.mp4")
            XCTAssertEqual(locator.resource.queryItems.map(\.name), ["quality"])
        }
    }

    private actor HeldPlexAddressHTTP: HTTPClient {
        let primary: URL
        var requests: [URL] = []
        private var held: CheckedContinuation<Void, Never>?
        private var observer: CheckedContinuation<Void, Never>?
        init(primary: URL) { self.primary = primary }
        func waitUntilHeld() async {
            if held != nil { return }
            await withCheckedContinuation { observer = $0 }
        }
        func release() { held?.resume(); held = nil }
        func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
            requests.append(baseURL)
            if baseURL == primary {
                await withCheckedContinuation {
                    held = $0
                    observer?.resume()
                    observer = nil
                }
            }
            throw AppError.serverUnreachable
        }
    }

    private actor DiscoveredPlexAddressHTTP: HTTPClient {
        let learned: URL
        var discoveries = 0
        init(learned: URL) { self.learned = learned }
        func discover() -> [URL] {
            discoveries += 1
            return discoveries == 1 ? [learned] : []
        }
        func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
            guard baseURL == learned else { throw AppError.serverUnreachable }
            return (Data(), HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testDiscoveryRefreshRetainsApprovedManualAddress() async throws {
        let id = UUID().uuidString
        defer {
            UserDefaults.standard.removeObject(forKey: "plex.reachable.\(id)")
            UserDefaults.standard.removeObject(forKey: "plex.artwork-origins.\(id)")
        }
        let original = URL(string: "https://offline.test")!
        let manual = URL(string: "http://192.168.1.50:32400")!
        let server = MediaServer(id: id, name: "Home", baseURL: original, provider: .plex,
                                 connectionURLs: [original], alternateConnectionURLs: [manual])
        let http = PlexAddressHTTP(manual: manual)
        let provider = PlexProvider(session: UserSession(server: server, userID: "owner", userName: "Viewer",
                                                         deviceID: "device", accessToken: "credential"),
                                    http: http, connectionRefresh: { [] }, probe: http)
        let selected = try await provider.resolveAuthenticatedHTTPOrigin()
        XCTAssertEqual(selected, manual)
        let probes = await http.requests
        XCTAssertEqual(probes.filter { $0.0 == manual }.count, 2)
        XCTAssertTrue(probes.allSatisfy { $0.1.redirectPolicy == .sameOrigin })
    }
}

private actor PlexAddressHTTP: HTTPClient {
    let manual: URL
    var requests: [(URL, Endpoint)] = []
    init(manual: URL) { self.manual = manual }
    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests.append((baseURL, endpoint))
        guard baseURL == manual, requests.filter({ $0.0 == manual }).count > 1 else {
            throw AppError.serverUnreachable
        }
        return (Data(), HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
