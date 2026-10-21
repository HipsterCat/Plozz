import CoreModels
import Foundation
import XCTest
@testable import ProviderSilo

extension SiloProviderTests {
    func testPersonalCollectionsIncludeUnpublishedAndSharedCardsWithoutArtwork() async throws {
        let raw = try credential().encoded()
        let http = SiloHTTPStub(["/api/v2/collections": """
        {"items":[
          {"id":"same","name":"Private comedy","include_in_server_collections":false,"is_shared":false},
          {"id":"shared","name":"Family night","creator_profile_id":"other","poster_url":""}
        ],"groups":[]}
        """])
        let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)
        XCTAssertTrue(provider.capabilities.contains(.personalCollections))
        let first = try await provider.personalCollections(page: .init(limit: 1))
        let second = try await provider.personalCollections(page: .init(startIndex: 1, limit: 1))
        XCTAssertEqual(first.totalCount, 2)
        XCTAssertEqual(second.startIndex, 1)
        XCTAssertEqual(first.items.first?.title, "Private comedy")
        XCTAssertEqual(second.items.first?.title, "Family night")
        XCTAssertNil(first.items.first?.libraryID)
        XCTAssertNil(first.items.first?.posterURL)
        XCTAssertEqual(first.items.first?.sourceAccountID, "account1")
        let personalID = try XCTUnwrap(first.items.first?.id)
        XCTAssertNotEqual(personalID, SiloProvider.collectionID(libraryID: "movies", id: "same"))
        let item = try await provider.item(id: personalID)
        XCTAssertEqual(item.id, personalID)
        let requests = await http.requests
        XCTAssertTrue(requests.allSatisfy { $0.path == "/api/v2/collections" })
        XCTAssertTrue(requests.allSatisfy { $0.headers["X-Profile-Id"] == "profile1" })
    }

    func testPersonalMembersUseUserCollectionWithoutLibraryOrSortOverride() async throws {
        let raw = try credential().encoded()
        let http = SiloHTTPStub(["/api/v2/catalog": """
        {"items":[{"content_id":"movie:1","type":"movie","title":"Movie"},
                  {"content_id":"series:2","type":"series","title":"Show"}],
         "total":2,"total_exact":true,"window_cursor":"window"}
        """])
        let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)
        let id = SiloProvider.personalCollectionID("personal:with/separators")
        let members = try await provider.children(of: id)
        XCTAssertEqual(members.map(\.id), ["movie:1", "series:2"])
        XCTAssertTrue(members.allSatisfy { $0.libraryID == nil })
        _ = try await provider.collectionMembers(of: id, page: .init(startIndex: 12, limit: 10))
        let requests = await http.requests
        let last = try XCTUnwrap(requests.last)
        XCTAssertTrue(last.queryItems.contains(URLQueryItem(name: "source", value: "user_collection")))
        XCTAssertTrue(last.queryItems.contains(URLQueryItem(name: "collection_id", value: "personal:with/separators")))
        XCTAssertTrue(last.queryItems.contains(URLQueryItem(name: "seek", value: "12")))
        XCTAssertTrue(last.queryItems.contains(URLQueryItem(name: "limit", value: "10")))
        XCTAssertFalse(last.queryItems.contains { $0.name == "library_id" || $0.name == "sort" })
    }

    func testLibraryCollectionsKeepTheirExistingIdentityAndMemberScope() async throws {
        let raw = try credential().encoded()
        let http = SiloHTTPStub([
            "/api/v2/library/movies/collections": """
            {"library_id":"movies","collections":[{"id":"same","title":"Curated","poster_url":""}]}
            """,
            "/api/v2/catalog": """
            {"items":[{"content_id":"movie:1","type":"movie","title":"Movie"}],
             "total":1,"total_exact":true,"window_cursor":"window"}
            """
        ])
        let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)
        let page = try await provider.collections(in: "movies", page: .init())
        let id = try XCTUnwrap(page.items.first?.id)
        XCTAssertEqual(id, SiloProvider.collectionID(libraryID: "movies", id: "same"))
        let detail = try await provider.item(id: id)
        XCTAssertEqual(detail.libraryID, "movies")
        let members = try await provider.collectionMembers(of: id, page: .init())
        XCTAssertEqual(members.items.first?.libraryID, "movies")
        let requests = await http.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertTrue(request.queryItems.contains(URLQueryItem(name: "source", value: "library_collection")))
        XCTAssertTrue(request.queryItems.contains(URLQueryItem(name: "library_id", value: "movies")))
    }

    func testPersonalCollectionFailuresAreNotEmptySuccessAndRespectRevocation() async throws {
        let raw = try credential().encoded()
        let store = SiloCredentialStub(raw)
        let http = SiloHTTPStub([:])
        let provider = try SiloProvider(context: context(raw), credentials: store, http: http)
        do {
            _ = try await provider.personalCollections(page: .init())
            XCTFail("Missing/unsupported collection endpoint must remain an error")
        } catch {
            XCTAssertEqual(error as? AppError, .notFound)
        }
        store.remove()
        do {
            _ = try await provider.personalCollections(page: .init())
            XCTFail("Revoked credentials must not read another viewer's collections")
        } catch {
            XCTAssertEqual(error as? AppError, .unauthorized)
        }
        let requests = await http.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testMalformedPersonalCollectionsAndIdentitiesAreRejected() async throws {
        let raw = try credential().encoded()
        let http = SiloHTTPStub(["/api/v2/collections": """
        {"items":[{"id":"duplicate","name":"First"},{"id":"duplicate","name":"Second"}]}
        """])
        let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)
        do {
            _ = try await provider.personalCollections(page: .init())
            XCTFail("Repeated identities must not become picker rows")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidResponse)
        }
        for value in ["silo-user-collection:", "silo-user-collection:invalid", "silo-user-collection:YQ==:extra"] {
            XCTAssertNil(SiloProvider.collectionIdentity(value))
        }
    }
}
