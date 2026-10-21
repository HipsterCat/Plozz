import CoreModels
import CoreNetworking
import CoreTrackerAuth
import XCTest
@testable import TestSupportNetworking
@testable import WetrakrService

final class WetrakrWatchlistBatchTests: XCTestCase {
    func testTwentyTwoChangesUseOneWriteAndDuplicateBindingsAreCoalesced() async throws {
        let http = RecordingHTTPClient()
        stubBaseline(http)
        http.stub(pathSuffix: "/sync/tracking", json: #"{"added":{"planning":{"movies":11,"shows":11}}}"#)
        let destination = makeDestination(http)
        XCTAssertEqual(destination.writePolicyVersion, 1)
        var bindings: [WatchlistDestinationBinding] = []
        for index in 1...22 {
            bindings.append(try await binding(index, kind: index <= 11 ? .movie : .series, destination: destination))
        }
        bindings.append(bindings[0])
        let outcomes = try await destination.apply(
            .present, to: bindings, idempotencyKey: "batch",
            expectedReconciliationScope: destination.reconciliationScope
        )
        for outcome in outcomes { try outcome.get() }
        XCTAssertEqual(outcomes.count, 23)
        let writes = http.sent.filter { $0.path == "/sync/tracking" }
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual((writes.first?.json?["movies"] as? [Any])?.count, 11)
        XCTAssertEqual((writes.first?.json?["shows"] as? [Any])?.count, 11)
        XCTAssertEqual(http.sent.count, 3, "One activity read, one baseline page, one bulk write")
    }

    func testUnchangedRemoteListNeedsNoWritesEvenAfterRelaunch() async throws {
        let http = RecordingHTTPClient()
        stubBaseline(http, entries: #"[{"id":42,"type":"movie","ids":{"tmdb":1}}]"#)
        for _ in 0..<2 {
            let destination = makeDestination(http)
            let present = try await binding(1, destination: destination)
            let absent = try await binding(2, destination: destination)
            try await destination.apply(.present, to: present)
            try await destination.apply(.absent, to: absent)
        }
        XCTAssertFalse(http.sent.contains { $0.path == "/sync/tracking" || $0.path == "/sync/tracking/remove" })
        XCTAssertEqual(http.sent.count, 4)
    }

    func testPartialFailureAcknowledgesOnlyIdentifiedResults() throws {
        let result = try decode(#"{"added":{"planning":{"movies":1}},"existing":{"planning":{"shows":1}},"notFound":{"movies":[{"ids":{"tmdb":2}}]},"errored":{"movies":[{"ids":{"tmdb":3},"error":"Status rejected"}]}}"#)
        let outcomes = try result.planningOutcomes(
            movies: [item(1), item(2), item(3)], shows: [item(4)], removing: false
        )
        try outcomes[0].get()
        XCTAssertThrowsError(try outcomes[1].get()) { XCTAssertEqual($0 as? WatchlistDestinationError, .unsupportedIdentity) }
        XCTAssertThrowsError(try outcomes[2].get()) { XCTAssertEqual($0 as? WatchlistDestinationError, .permanent) }
        try outcomes[3].get()
    }

    func testMissingAmbiguousOrContradictoryBatchEvidenceFailsClosed() throws {
        for body in [
            "{}",
            #"{"added":{"watched":{"movies":2}}}"#,
            #"{"added":{"planning":{"movies":1}}}"#,
            #"{"added":{"planning":{"movies":-1}}}"#,
            #"{"added":{"planning":{"movies":2}},"notFound":{"movies":[{"ids":{"tmdb":2}}]}}"#,
            #"{"added":{"planning":{"movies":1}},"errored":{"movies":[{"error":"Status rejected"}]}}"#,
            #"{"added":{"planning":{"movies":1}},"notFound":{"movies":[{"ids":{"tmdb":99}}]}}"#,
            #"{"added":{"planning":{"movies":2}},"notFound":{"episodes":[{"id":1}]}}"#
        ] {
            XCTAssertThrowsError(try decode(body).planningOutcomes(
                movies: [item(1), item(2)], shows: [], removing: false
            ))
        }
    }

    func testRemovalDistinguishesAlreadyAbsentFromUnresolved() throws {
        let result = try decode(#"{"removed":{"planning":{"movies":1}},"errored":{"movies":[{"ids":{"tmdb":2},"error":"Nothing to remove"}]},"notFound":{"movies":[{"ids":{"tmdb":3}}]}}"#)
        let outcomes = try result.planningOutcomes(
            movies: [item(1), item(2), item(3)], shows: [], removing: true
        )
        try outcomes[0].get()
        try outcomes[1].get()
        XCTAssertThrowsError(try outcomes[2].get())
    }

    func testRetryKeySurvivesDestinationRecreationAndTracksExactPayload() async throws {
        let http = RecordingHTTPClient()
        stubBaseline(http)
        http.stub(pathSuffix: "/sync/tracking", json: "{}", status: 503)
        var keys: [String] = []
        for ids in [[1, 2], [2, 1], [1]] {
            let destination = makeDestination(http)
            var bindings: [WatchlistDestinationBinding] = []
            for id in ids { bindings.append(try await binding(id, destination: destination)) }
            do {
                _ = try await destination.apply(
                    .present, to: bindings, idempotencyKey: "persisted-batch",
                    expectedReconciliationScope: destination.reconciliationScope
                )
                XCTFail("Expected transport failure")
            } catch {}
            keys.append(try XCTUnwrap(http.sent.last?.headers["Idempotency-Key"]))
        }
        XCTAssertEqual(keys[0], keys[1])
        XCTAssertNotEqual(keys[1], keys[2])
        let bodies = http.sent.filter { $0.path == "/sync/tracking" }.map(\.body)
        XCTAssertEqual(bodies[0], bodies[1])
        XCTAssertNotEqual(bodies[1], bodies[2])
    }

    func testAcceptedWriteWithLostResponseIsNotRewrittenWhenBaselineConfirmsIt() async throws {
        let http = RecordingHTTPClient()
        stubBaseline(http)
        http.stub(pathSuffix: "/sync/tracking/planning/all", json: #"[{"id":42,"type":"movie","ids":{"tmdb":1}}]"#,
                  headers: ["X-Pagination-Page-Count": "1"])
        http.stub(pathSuffix: "/sync/tracking", json: "{}", status: 503)
        let destination = makeDestination(http)
        let value = try await binding(1, destination: destination)
        do {
            try await destination.apply(.present, to: value)
            XCTFail("Expected transport failure")
        } catch {}
        try await destination.apply(.present, to: value)
        XCTAssertEqual(http.sent.filter { $0.path == "/sync/tracking" }.count, 1)
    }

    func testWrongScopeOrOversizedBatchNeverContactsService() async throws {
        let http = RecordingHTTPClient()
        let destination = makeDestination(http)
        let value = try await binding(1, destination: destination)
        for (bindings, scope) in [([value], "other-account"),
                                  (Array(repeating: value, count: 51), destination.reconciliationScope)] {
            do {
                _ = try await destination.apply(
                    .present, to: bindings, idempotencyKey: "batch", expectedReconciliationScope: scope
                )
                XCTFail("Expected refusal")
            } catch {}
        }
        XCTAssertTrue(http.sent.isEmpty)
    }

    func testMissingRemoteIDsCannotSilentlyAcknowledgeRemoval() async throws {
        let http = RecordingHTTPClient()
        stubBaseline(http, entries: #"[{"id":42,"type":"movie","ids":{"imdb":"tt123"}}]"#)
        http.stub(pathSuffix: "/sync/tracking/remove", json: #"{"removed":{"planning":{"movies":1}}}"#)
        let destination = makeDestination(http)
        let value = try await binding(1, destination: destination)
        try await destination.apply(.absent, to: value)
        XCTAssertEqual(http.sent.filter { $0.path == "/sync/tracking/remove" }.count, 1)
    }

    func testSignOutDuringBaselinePreventsBatchWrite() async throws {
        let http = RecordingHTTPClient()
        stubBaseline(http)
        let tokens = InMemoryTrackerTokenStore(tokens: .init(
            accessToken: "access", refreshToken: "refresh", expiresAt: .distantFuture,
            accountIdentity: "viewer-one"
        ))
        let destination = WetrakrWatchlistDestination(
            client: .init(
                config: .init(clientID: "test-client"),
                http: BaselineCallbackHTTP(http: http, callback: { try tokens.clear() }), gate: .init()
            ),
            tokenStore: tokens, coordinator: .init(), generation: .init()
        )
        let value = try await binding(1, destination: destination)
        do {
            _ = try await destination.apply(
                .present, to: [value], idempotencyKey: "batch",
                expectedReconciliationScope: destination.reconciliationScope
            )
            XCTFail("Expected scope rejection")
        } catch {
            XCTAssertEqual(error as? WatchlistDestinationError, .authenticationRequired)
        }
        XCTAssertFalse(http.sent.contains { $0.path == "/sync/tracking" })
    }

    private func makeDestination(_ http: RecordingHTTPClient) -> WetrakrWatchlistDestination {
        WetrakrWatchlistDestination(
            client: .init(config: .init(clientID: "test-client"), http: http, gate: .init()),
            tokenStore: InMemoryTrackerTokenStore(tokens: .init(
                accessToken: "access", refreshToken: "refresh", expiresAt: .distantFuture,
                accountIdentity: "viewer-one"
            )),
            coordinator: .init(), generation: .init()
        )
    }

    private struct BaselineCallbackHTTP: HTTPClient {
        let http: RecordingHTTPClient
        let callback: @Sendable () throws -> Void
        func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
            let result = try await http.sendRaw(endpoint, baseURL: baseURL)
            if endpoint.path == "/sync/tracking/planning/all" { try callback() }
            return result
        }
    }

    private func stubBaseline(_ http: RecordingHTTPClient, entries: String = "[]") {
        http.stub(pathSuffix: "/sync/last_activities",
                  json: #"{"journal_visible_until":"2026-10-01T00:00:01Z"}"#)
        http.stub(pathSuffix: "/sync/tracking/planning/all", json: entries,
                  headers: ["X-Pagination-Page-Count": "1"])
    }

    private func binding(
        _ id: Int, kind: MediaItemKind = .movie, destination: WetrakrWatchlistDestination
    ) async throws -> WatchlistDestinationBinding {
        let target = try XCTUnwrap(WatchlistMutationTarget(
            aliasID: .init(), kind: kind,
            externalIDs: [WatchlistExternalID(namespace: .tmdb, value: String(id))!]
        ))
        let value = try await destination.resolve(target)
        return try XCTUnwrap(value)
    }

    private func item(_ id: Int) -> WetrakrTrackingBody.Item {
        .init(ids: .init(tmdb: id), status: "planning")
    }

    private func decode(_ body: String) throws -> WetrakrTrackingResult {
        try JSONDecoder().decode(WetrakrTrackingResult.self, from: Data(body.utf8))
    }
}
