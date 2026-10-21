import AppRuntime
import CoreModels
import Foundation
import XCTest

@MainActor
final class ManagedHTTPAddressResolutionTests: XCTestCase {
    func testResolvedOriginUsesItsBasePathAndRejectsAnAddressEditDuringSuspension() async throws {
        for changeDuringResolution in [false, true] {
            let resolver = ManagedAuthenticatedHTTPResolver()
            let origin = HeldHTTPOrigin()
            let revision = CredentialRevision()
            var scope = "before"
            resolver.configure { _ in
                .init(provider: .jellyfin, accountID: "account", credentialRevision: revision,
                      baseURL: URL(string: "https://original.test/old")!, token: "credential",
                      originProvider: origin, connectionScopeKey: scope)
            }
            let locator = try AuthenticatedHTTPPlaybackLocator(
                provider: .jellyfin, accountID: "account", credentialRevision: revision,
                itemID: "movie", deliveryMode: .directFile,
                resource: AuthenticatedHTTPResource(pathBase: .configuredBaseURL, path: "Videos/movie/stream")
            )
            let task = Task { try await resolver.resolve(locator) }
            await origin.waitUntilResolving()
            if changeDuringResolution { scope = "after" }
            await origin.release()
            do {
                let result = try await task.value
                XCTAssertFalse(changeDuringResolution)
                XCTAssertEqual(result.host, "192.168.1.50")
                XCTAssertEqual(result.path, "/local/Videos/movie/stream")
            } catch {
                XCTAssertTrue(changeDuringResolution)
            }
        }
    }
}

private actor HeldHTTPOrigin: AuthenticatedHTTPOriginProviding {
    nonisolated let authenticatedHTTPOrigin = URL(string: "http://192.168.1.50/local")!
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func resolveAuthenticatedHTTPOrigin() async throws -> URL {
        await withCheckedContinuation {
            pending = $0
            observer?.resume()
            observer = nil
        }
        return authenticatedHTTPOrigin
    }
    func waitUntilResolving() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { pending?.resume(); pending = nil }
}
