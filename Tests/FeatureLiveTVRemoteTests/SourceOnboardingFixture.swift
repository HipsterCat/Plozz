import CoreModels
import Foundation
import SwiftUI
@testable import FeatureLiveTV

struct SourceOnboardingFixture: View {
    private enum Destination: Hashable { case sources }
    @State private var path: [Destination] = []
    @State private var profiles = ProfilesModel(store: SourceSmokeProfiles())
    @State private var sources = SourceSmokeStore()
    private let usesTypedNavigation = ProcessInfo.processInfo.arguments.contains("--typed-sources")

    var body: some View {
        NavigationStack(path: $path) {
            if usesTypedNavigation {
                List {
                    NavigationLink("Sources", value: Destination.sources)
                        .accessibilityIdentifier("fixture-sources")
                }
                .navigationTitle("Source navigation fixture")
                .navigationDestination(for: Destination.self) { _ in
                    LiveTVSourcesView(store: sources)
                }
            } else {
                LiveTVPrototypeView(sourceStore: sources) { _ in
                    Text("Unexpected playback")
                        .accessibilityIdentifier("fixture-unexpected-playback")
                }
            }
        }
        .environment(profiles)
        .overlay(alignment: .bottom) {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                Text(verbatim: "Sources \(sources.sourceCount) writes \(sources.writeCount) requests \(SourceSmokeNetworkBlocker.requestCount)")
                    .font(.caption2)
                    .accessibilityIdentifier("fixture-source-metrics")
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct SourceSmokeProfiles: ProfilePersisting {
    private let profile = Profile(id: "source-smoke", name: "Source smoke")
    func loadProfiles() -> [Profile] { [profile] }
    func saveProfiles(_ profiles: [Profile]) {}
    func activeProfileID() -> String? { profile.id }
    func setActiveProfileID(_ id: String?) {}
    func lastUsedDates() -> [String: Date] { [:] }
    func markProfileUsed(_ profileID: String, at date: Date) {}
    func activeAccountIDs(forProfile profileID: String) -> [String]? { [] }
    func setActiveAccountIDs(_ ids: [String], forProfile profileID: String) {}
    func migrateLegacyIfNeeded(defaultName: String, defaultActiveAccountIDs: [String]) -> [Profile] { [profile] }
}

private final class SourceSmokeStore: LiveTVSourcesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var configuration = LiveTVSourcesConfiguration.empty
    private var writes = 0

    var sourceCount: Int { lock.withLock { configuration.playlists.count + configuration.servers.count } }
    var writeCount: Int { lock.withLock { writes } }
    func load() throws -> LiveTVSourcesConfiguration { lock.withLock { configuration } }
    func save(_ value: LiveTVSourcesConfiguration) throws {
        try value.validate()
        lock.withLock {
            configuration = value
            writes += 1
        }
    }
}

final class SourceSmokeNetworkBlocker: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var requests = 0
    static var requestCount: Int { lock.withLock { requests } }

    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.requests += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
    }

    override func stopLoading() {}
}
