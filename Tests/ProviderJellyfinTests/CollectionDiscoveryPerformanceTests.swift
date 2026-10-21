import CoreModels
import CoreNetworking
import Foundation
import XCTest
@testable import ProviderJellyfin
@testable import TestSupportPerformance

final class CollectionDiscoveryPerformanceTests: XCTestCase {
    @MainActor
    func testPerformanceCollectionDiscovery() async throws {
        try PerformanceProbe.requireEnabled()
        try await PerformanceProbe.measure(self, scenario: "collection-discovery") {
            let http = CollectionDiscoveryHTTP()
            let provider = JellyfinProvider(session: UserSession(
                server: MediaServer(id: "fixture", name: "Fixture", baseURL: URL(string: "https://fixture.invalid")!, provider: .jellyfin),
                userID: "user", userName: "User", deviceID: "fixture", accessToken: "fixture"
            ), http: http)
            let progress = DiscoveryProgressClock()
            let result = try await provider.collections(in: "library", page: PageRequest(limit: 500)) {
                await progress.record($0.items)
            }
            await progress.record(result.items)
            XCTAssertEqual(result.items.map(\.id), (0..<356).map { "collection-\($0)" })
            XCTAssertEqual(result.totalCount, 356)
            let firstItems = await progress.elapsed
            XCTAssertGreaterThan(firstItems, 0)
            let requests = await http.requests
            let libraryRequests = await http.libraryRequests
            let memberRequests = await http.memberRequests
            XCTAssertEqual(requests, 1)
            XCTAssertEqual(libraryRequests, 0)
            XCTAssertEqual(memberRequests, 0)
            let cached = try await provider.collections(in: "library", page: PageRequest(startIndex: 100, limit: 50))
            XCTAssertEqual(cached.items.map(\.id), (100..<150).map { "collection-\($0)" })
            let afterCache = await http.requests
            XCTAssertEqual(afterCache, requests)
            return [
                "collections": result.totalCount, "requests": requests,
                "libraryRequests": libraryRequests, "memberRequests": memberRequests,
                "firstItemsNanoseconds": firstItems
            ]
        }
    }
}

private actor DiscoveryProgressClock {
    let start = DispatchTime.now().uptimeNanoseconds
    private(set) var elapsed = 0
    func record(_ items: [MediaItem]) {
        if elapsed == 0, !items.isEmpty { elapsed = Int(DispatchTime.now().uptimeNanoseconds - start) }
    }
}

private actor CollectionDiscoveryHTTP: HTTPClient {
    private let library: [[String: String]?] = (0..<10_000).map {
        $0 == 5650 ? nil : ["Id": "movie-\($0)", "Type": "Movie"]
    }
    private let candidates = (0..<356).map {
        ["Id": "collection-\($0)", "Name": "Collection \($0)", "Type": "BoxSet"]
    }
    private(set) var requests = 0
    private(set) var libraryRequests = 0
    private(set) var memberRequests = 0

    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests += 1
        let query = Dictionary(uniqueKeysWithValues: endpoint.queryItems.map { ($0.name, $0.value ?? "") })
        let start = Int(query["StartIndex"] ?? "0") ?? 0
        let limit = Int(query["Limit"] ?? "200") ?? 200
        let rows: [[String: String]?]
        if query["IncludeItemTypes"] == "BoxSet" {
            rows = candidates.map(Optional.some)
        } else if query["ParentId"] == "library" {
            libraryRequests += 1
            rows = library
        } else if let parent = query["ParentId"],
                  let index = Int(parent.replacingOccurrences(of: "collection-", with: "")) {
            memberRequests += 1
            if (1...24).contains(index) { rows = [["Id": "movie-\(index)", "Type": "Movie"]] }
            else if index == 25 {
                rows = (0..<25).map { $0 == 4 ? nil : ["Id": "foreign-\($0)", "Type": "Movie"] }
            } else { rows = [] }
        } else { throw AppError.notFound }
        try await Task.sleep(for: .milliseconds(5))
        let body: [String: Any] = [
            "Items": rows.dropFirst(start).prefix(limit).compactMap { $0 }, "TotalRecordCount": rows.count
        ]
        return (try JSONSerialization.data(withJSONObject: body),
                HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
