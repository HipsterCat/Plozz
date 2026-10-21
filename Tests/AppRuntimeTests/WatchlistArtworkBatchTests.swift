import CoreModels
import Foundation
import XCTest
@testable import AppRuntime

@MainActor
final class WatchlistArtworkBatchTests: XCTestCase {
    func testBatchMatchesIndependentRehydrationAcrossAccountsSizesAndProvenance() async throws {
        for kind in [ProviderKind.plex, .jellyfin, .emby] {
            let host = try await UniversalWatchlistHostDouble(providerKind: kind)
            var secondAccount = try XCTUnwrap(host.accountsProviders.accounts.first)
            secondAccount.id = "second"
            secondAccount.userID = "second-user"
            try host.accountsProviders.accountStore.add(secondAccount, token: "SECOND-TOKEN")
            host.accountsProviders.accountStore.setActiveAccountIDs(["acct", "second"])
            host.accountsProviders.reloadAccounts()
            let provider = try XCTUnwrap(host.accountsProviders.provider(forAccountID: "acct"))
            let url = SyncURLSanitizer.sanitize(try XCTUnwrap(
                provider.imageURL(itemID: "shared", kind: .primary, maxWidth: 500)
            ))
            var first = MediaItem(
                id: "first", title: "First", kind: .movie,
                people: [MediaPerson(id: "person", name: "Person", imageURL: url)],
                posterURL: url, backdropURL: url, heroBackdropURL: url,
                artworkSelections: [.init(placement: .homeHero, references: [.remote(url)])],
                locallyValidatedPlayableSource: true, sourceAccountID: "acct"
            ).taggingArtworkSource("acct")
            var second = first
            second.id = "second"
            second.sourceAccountID = "second"
            second = second.taggingArtworkSource("second")
            var unowned = first
            unowned.locallyValidatedPlayableSource = false
            var ambiguous = first
            ambiguous.artworkSourceAccountIDsByURL = [:]
            let fixtures = [first, second, unowned, ambiguous, first, second]
            let expected = fixtures.flatMap { host.rehydratedPersistedArtwork([$0]) }

            let result = host.rehydratedPersistedArtwork(fixtures)

            XCTAssertEqual(result, expected, kind.rawValue)
            XCTAssertTrue(result[0].posterURL?.absoluteString.contains("CURRENT-TOKEN") == true)
            XCTAssertTrue(result[1].posterURL?.absoluteString.contains("SECOND-TOKEN") == true)
            XCTAssertNotEqual(result[0].posterURL, result[0].heroBackdropURL)
            for item in result {
                for key in item.artworkSourceAccountIDsByURL.keys {
                    XCTAssertFalse(SyncURLSanitizer.containsCredential(try XCTUnwrap(URL(string: key))))
                }
            }

            first.people = []
            XCTAssertTrue(host.rehydratedPersistedArtwork([first])[0].people.isEmpty)
        }
    }

    func testLaterBatchUsesChangedDiscoverCredentialsAndPreservesDuplicateCredits() async throws {
        let host = try await UniversalWatchlistHostDouble()
        let url = URL(string: "https://discover.provider.plex.tv/library/metadata/person/thumb/1")!
        let item = MediaItem(
            id: "title", title: "Title", kind: .movie,
            people: [
                .init(id: "one", name: "One", imageURL: url),
                .init(id: "two", name: "Two", imageURL: url)
            ],
            posterURL: url, sourceAccountID: "acct"
        ).taggingArtworkSource("acct")
        host.plexDiscoverTokens.setToken("FIRST-DISCOVER", for: "acct")
        let first = host.rehydratedPersistedArtwork([item, item])
        host.plexDiscoverTokens.setToken("SECOND-DISCOVER", for: "acct")

        let second = host.rehydratedPersistedArtwork([item, item])

        XCTAssertTrue(first[0].posterURL?.absoluteString.contains("FIRST-DISCOVER") == true)
        XCTAssertTrue(second[0].posterURL?.absoluteString.contains("SECOND-DISCOVER") == true)
        XCTAssertEqual(second[0].people.map(\.id), ["one", "two"])
        XCTAssertEqual(second[0].people[0].imageURL, second[0].people[1].imageURL)
        XCTAssertEqual(second[0].artworkSourceAccountID(for: try XCTUnwrap(second[0].posterURL)), "acct")
    }
}
