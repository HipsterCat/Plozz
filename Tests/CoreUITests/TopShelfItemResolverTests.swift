import CoreModels
import Foundation
import TopShelfKit
import XCTest

final class TopShelfItemResolverTests: XCTestCase {
    func testBothActionsResolveOnlyTheirExplicitAccountWithCollidingIDs() async throws {
        let calls = Calls()
        let accounts = [
            account("plex", kind: .plex) { id in
                await calls.append("plex")
                return MediaItem(id: id, title: "Plex title", kind: .movie)
            },
            account("jellyfin", kind: .jellyfin) { id in
                await calls.append("jellyfin")
                return MediaItem(id: id, title: "Jellyfin title", kind: .movie)
            }
        ]
        for action in [TopShelf.ItemReference.Action.play, .details] {
            let item = try await TopShelfItemResolver.resolve(
                .init(id: "1", accountID: "jellyfin", action: action), accounts: accounts
            )
            XCTAssertEqual(item.title, "Jellyfin title")
            XCTAssertEqual(item.sourceAccountID, "jellyfin")
        }
        let observed = await calls.values
        XCTAssertEqual(observed, ["jellyfin", "jellyfin"])
    }

    func testMissingOrFailingExplicitAccountNeverFallsBack() async {
        let accounts = [
            account("plex", kind: .plex) { _ in throw AppError.notFound },
            account("jellyfin", kind: .jellyfin) { id in
                XCTFail("Do not resolve a scoped ID on another server")
                return MediaItem(id: id, title: "Wrong title", kind: .movie)
            }
        ]
        for (owner, expected) in [("missing", AppError.unauthorized), ("plex", AppError.notFound)] {
            do {
                _ = try await TopShelfItemResolver.resolve(
                    .init(id: "1", accountID: owner, action: .details), accounts: accounts
                )
                XCTFail("Expected a source failure")
            } catch {
                XCTAssertEqual(error as? AppError, expected)
            }
        }
    }

    func testLegacyUnscopedLinksStillSearchActiveAccounts() async throws {
        let accounts = [
            account("plex", kind: .plex) { _ in throw AppError.notFound },
            account("jellyfin", kind: .jellyfin) { id in MediaItem(id: id, title: "Found", kind: .movie) }
        ]
        let item = try await TopShelfItemResolver.resolve(.init(id: "1"), accounts: accounts)
        XCTAssertEqual(item.sourceAccountID, "jellyfin")
    }

    func testCancelledProviderCompletionCannotReturnAnItem() async {
        let gate = Gate()
        let accounts = [account("plex", kind: .plex) { _ in await gate.fetch() }]
        let task = Task {
            try await TopShelfItemResolver.resolve(.init(id: "1", accountID: "plex"), accounts: accounts)
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.resume()
        do {
            _ = try await task.value
            XCTFail("Cancelled scope must not open a title")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testMismatchedProviderItemIsRejected() async {
        let accounts = [account("plex", kind: .plex) { _ in MediaItem(id: "wrong", title: "Wrong", kind: .movie) }]
        do {
            _ = try await TopShelfItemResolver.resolve(.init(id: "1", accountID: "plex"), accounts: accounts)
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidResponse)
        }
    }

    private func account(
        _ id: String, kind: ProviderKind,
        fetch: @escaping @Sendable (String) async throws -> MediaItem
    ) -> ResolvedAccount {
        let server = MediaServer(id: id, name: "Fixture", baseURL: URL(string: "https://fixture.test")!, provider: kind)
        let account = Account(id: id, server: server, userID: "user", userName: "Fixture", deviceID: "test")
        let session = UserSession(server: server, userID: "user", userName: "Fixture", deviceID: "test", accessToken: "fixture")
        return ResolvedAccount(account: account, provider: Provider(kind: kind, session: session, fetch: fetch))
    }

    private actor Calls {
        var values: [String] = []
        func append(_ value: String) { values.append(value) }
    }

    private actor Gate {
        var continuation: CheckedContinuation<MediaItem, Never>?
        var waiter: CheckedContinuation<Void, Never>?

        func fetch() async -> MediaItem {
            await withCheckedContinuation {
                continuation = $0
                waiter?.resume()
                waiter = nil
            }
        }

        func waitUntilEntered() async {
            if continuation != nil { return }
            await withCheckedContinuation { waiter = $0 }
        }

        func resume() {
            continuation?.resume(returning: MediaItem(id: "1", title: "Old scope", kind: .movie))
            continuation = nil
        }
    }

    private struct Provider: MediaProvider {
        let kind: ProviderKind
        let session: UserSession
        let fetch: @Sendable (String) async throws -> MediaItem
        func libraries() async throws -> [MediaLibrary] { [] }
        func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
        func latest(limit: Int) async throws -> [MediaItem] { [] }
        func item(id: String) async throws -> MediaItem { try await fetch(id) }
        func children(of itemID: String) async throws -> [MediaItem] { [] }
        func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage { throw AppError.notFound }
        func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
        func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
        func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
        func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
    }
}
