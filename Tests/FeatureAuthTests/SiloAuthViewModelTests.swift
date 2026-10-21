import CoreModels
import CoreNetworking
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ProviderSilo
import XCTest
@testable import FeatureAuthCore

@MainActor
final class SiloAuthViewModelTests: XCTestCase {
    func testDroppedPollRetainsCodeAndContinuesWithBackoffWithoutReportingRecoveredFailure() async throws {
        let http = SiloOnboardingHTTP(pollFailures: [1: .serverUnreachable])
        let diagnostics = SiloSetupDiagnostics()
        let buffer = SiloAuthDiagnosticBuffer()
        diagnostics.start { buffer.append($0) }
        let model = makeModel(http, diagnostics: diagnostics)
        defer { model.cancel() }
        model.start()
        try await waitForPoll(http)
        guard case let .pairing(code, _, _, expiry) = model.phase else {
            return XCTFail("A dropped poll must retain the active pairing")
        }
        XCTAssertEqual(code, "ABCD12")
        XCTAssertNotNil(model.verificationURL)
        XCTAssertGreaterThan(expiry, Date())
        try await wait(timeout: 6) { if case .profiles = model.phase { return true }; return false }
        let starts = await http.count("/api/v2/auth/device/start")
        let pollTimes = await http.pollTimes
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(pollTimes.count, 2)
        if pollTimes.count == 2 {
            XCTAssertGreaterThanOrEqual(pollTimes[1].timeIntervalSince(pollTimes[0]), 1.9)
        }
        XCTAssertTrue(buffer.values.isEmpty)
    }

    func testRepeatedNetworkFailuresStopAfterThreePollsAndReportTheFinalFailure() async throws {
        let http = SiloOnboardingHTTP(pollFailures: [1: .serverUnreachable, 2: .serverUnreachable, 3: .serverUnreachable])
        let diagnostics = SiloSetupDiagnostics()
        let buffer = SiloAuthDiagnosticBuffer()
        diagnostics.start { buffer.append($0) }
        let model = makeModel(http, diagnostics: diagnostics)
        defer { model.cancel() }
        model.start()
        try await wait(timeout: 12) { if case .error = model.phase { return true }; return false }
        let polls = await http.count("/api/v2/auth/device/poll")
        let starts = await http.count("/api/v2/auth/device/start")
        XCTAssertEqual(polls, 3)
        XCTAssertEqual(starts, 1)
        XCTAssertNil(model.verificationURL)
        XCTAssertEqual(buffer.values.count, 1)
        XCTAssertEqual(buffer.values.first?.stage, .poll)
        XCTAssertEqual(buffer.values.first?.reason, .network)
    }

    func testExpiryDuringPollBackoffDoesNotSendAnotherPoll() async throws {
        let http = SiloOnboardingHTTP(expiresIn: 2, pollFailures: [1: .serverUnreachable])
        let model = makeModel(http)
        defer { model.cancel() }
        model.start()
        try await wait { model.phase == .expired }
        let polls = await http.count("/api/v2/auth/device/poll")
        XCTAssertEqual(polls, 1)
        XCTAssertNil(model.verificationURL)
    }

    func testCancellationDuringPollBackoffCannotRestartPairing() async throws {
        let http = SiloOnboardingHTTP(pollFailures: [1: .serverUnreachable])
        let model = makeModel(http)
        defer { model.cancel() }
        model.start()
        try await waitForPoll(http)
        model.cancel()
        try await Task.sleep(for: .seconds(3))
        let polls = await http.count("/api/v2/auth/device/poll")
        let starts = await http.count("/api/v2/auth/device/start")
        XCTAssertEqual(polls, 1)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.verificationURL)
    }

    func testConsumedOrDeniedApprovalAfterADroppedResponseRemainsTerminal() async throws {
        for status in ["consumed", "denied"] {
            let http = SiloOnboardingHTTP(pollStatus: status, pollFailures: [1: .serverUnreachable])
            let model = makeModel(http)
            defer { model.cancel() }
            model.start()
            try await wait(timeout: 6) {
                if case .error = model.phase { return true }
                return model.phase == .expired
            }
            if status == "consumed" { XCTAssertEqual(model.phase, .expired) }
            let polls = await http.count("/api/v2/auth/device/poll")
            let starts = await http.count("/api/v2/auth/device/start")
            let profiles = await http.count("/api/v2/profiles")
            XCTAssertEqual(polls, 2)
            XCTAssertEqual(starts, 1)
            XCTAssertEqual(profiles, 0)
            XCTAssertNil(model.verificationURL)
        }
    }

    func testRejectedAndMalformedPollsAreNotRetried() async throws {
        for error in [AppError.unauthorized, .notFound, .decoding, .rateLimited(retryAfter: nil)] {
            let http = SiloOnboardingHTTP(pollFailures: [1: error])
            let model = makeModel(http)
            defer { model.cancel() }
            model.start()
            try await wait { if case .error = model.phase { return true }; return false }
            let polls = await http.count("/api/v2/auth/device/poll")
            XCTAssertEqual(polls, 1)
        }
    }

    func testFirstPairingFailureCanRecoverInPlaceLikeReopeningSavedServer() async throws {
        let http = SiloOnboardingHTTP(failFirstStart: true)
        let diagnostics = SiloSetupDiagnostics()
        let buffer = SiloAuthDiagnosticBuffer()
        diagnostics.start { buffer.append($0) }
        let url = URL(string: "https://silo.test")!
        let model = SiloAuthViewModel(
            server: .init(id: "silo", name: "Silo", baseURL: url, provider: .silo), deviceID: "test",
            service: .init(baseURL: url, http: http), diagnostics: diagnostics,
            onAuthenticated: { _ in XCTFail("Unexpected sign-in") }
        )
        defer { model.cancel() }
        model.start()
        try await wait { if case .error = model.phase { return true }; return false }
        XCTAssertEqual(buffer.values.first?.stage, .start)
        XCTAssertEqual(buffer.values.first?.httpStatus, 502)
        XCTAssertEqual(buffer.values.first?.response, .html)
        model.retry()
        try await wait { if case .profiles = model.phase { return true }; return false }
        let starts = await http.count("/api/v2/auth/device/start")
        XCTAssertEqual(starts, 2)
    }

    func testCanceledPairingOffersANewCodeInsteadOfUnexpectedResponse() async throws {
        let http = SiloOnboardingHTTP(pollStatus: "canceled")
        let model = makeModel(http)
        defer { model.cancel() }
        model.start()
        try await wait { model.phase == .expired }
        model.retry()
        try await wait { if case .pairing = model.phase { return true }; return false }
    }

    func testPendingResponseExtendsDeadlineAndAllowsApproval() async throws {
        let http = SiloOnboardingHTTP(expiresIn: 2, extendsExpiry: true)
        let model = makeModel(http)
        defer { model.cancel() }
        model.start()
        try await wait { if case .profiles = model.phase { return true }; return false }
        let polls = await http.count("/api/v2/auth/device/poll")
        XCTAssertEqual(polls, 2)
    }

    func testEmptyLegacyMatchPhraseDoesNotRejectValidSignIn() async throws {
        let http = SiloOnboardingHTTP(emptyMatch: true)
        let model = makeModel(http)
        defer { model.cancel() }
        model.start()
        try await wait { if case .profiles = model.phase { return true }; return false }
    }

    func testConfiguredPublicAliasUsesSelectedServerWithoutForwardingForeignQuery() throws {
        let challenge = try JSONDecoder().decode(SiloDeviceChallenge.self, from: Data("""
            {"device_code":"device-secret","user_code":"4821-7730","match_code":"",
             "verification_uri":"https://public.invalid/silo/activate",
             "verification_uri_complete":"https://public.invalid/silo/activate?code=48217730&token=do-not-forward",
             "expires_in":900,"interval":5}
            """.utf8))
        let base = URL(string: "http://192.168.1.2:8090/base")!
        let (manual, approval) = try SiloAuthViewModel.approvalURLs(challenge, baseURL: base)
        XCTAssertEqual(manual.absoluteString, "http://192.168.1.2:8090/base/activate")
        XCTAssertEqual(approval.host, base.host)
        XCTAssertEqual(approval.path, "/base/activate")
        XCTAssertEqual(URLComponents(url: approval, resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "code", value: "4821-7730")])
    }

    func testApprovalLinksRejectEmbeddedCredentialsInEitherURL() throws {
        let base = URL(string: "https://silo.test")!
        for host in ["silo.test", "public.invalid"] {
            for credentialInManual in [true, false] {
                let manual = "https://\(credentialInManual ? "user:password@" : "")\(host)/activate"
                let complete = "https://\(credentialInManual ? "" : "user:password@")\(host)/activate?code=48217730"
                let challenge = try JSONDecoder().decode(SiloDeviceChallenge.self, from: Data("""
                    {"device_code":"device-secret","user_code":"4821-7730","match_code":"",
                     "verification_uri":"\(manual)","verification_uri_complete":"\(complete)",
                     "expires_in":900,"interval":5}
                    """.utf8))
                XCTAssertThrowsError(try SiloAuthViewModel.approvalURLs(challenge, baseURL: base)) { error in
                    XCTAssertEqual((error as? SiloSetupFailure)?.diagnostic.reason, .addressMismatch)
                }
            }
        }
    }

    func testSignInPreservesTheSelectedServerNameInsteadOfSavingItsHost() async throws {
        for (selectedName, expectedName) in [("Silo", "Silo"), ("Living Room Movies", "Living Room Movies"), ("silo.test", "Silo")] {
            let http = SiloOnboardingHTTP()
            let url = URL(string: "https://silo.test")!
            let server = MediaServer(id: url.absoluteString, name: selectedName, baseURL: url, provider: .silo)
            var received: UserSession?
            let model = SiloAuthViewModel(
                server: server, deviceID: "test",
                service: SiloAuthentication(baseURL: url, http: http),
                onAuthenticated: { received = $0 }
            )
            defer { model.cancel() }
            model.start()
            try await wait { if case .profiles = model.phase { return true }; return false }
            guard case let .profiles(profiles) = model.phase,
                  let open = profiles.first(where: { !$0.has_pin }) else { return XCTFail("Missing open profile") }
            model.select(open)
            try await wait { received != nil }
            XCTAssertEqual(received?.server.name, expectedName)
            XCTAssertEqual(received?.server.baseURL, url)
            XCTAssertNotEqual(received?.server.id, url.absoluteString, "The authenticated installation id still owns identity.")
        }
    }

    func testPINBackKeepsApprovalAndAllowsAnotherProfile() async throws {
        let http = SiloOnboardingHTTP()
        var received: [UserSession] = []
        let model = makeModel(http) { received.append($0) }
        defer { model.cancel() }
        model.start()
        try await wait { if case .profiles = model.phase { return true }; return false }
        guard case let .profiles(profiles) = model.phase else { return XCTFail("Missing profiles") }
        model.select(profiles[0])
        model.pin = "wrong"
        model.submitPIN(profiles[0])
        XCTAssertEqual(model.pin, "")
        try await wait { model.pinError != nil }
        XCTAssertEqual(model.phase, .pin(profiles[0]))
        model.chooseAnotherProfile()
        XCTAssertEqual(model.phase, .profiles(profiles))
        XCTAssertNil(model.pinError)
        XCTAssertEqual(model.pin, "")
        model.select(profiles[1])
        try await wait { received.count == 1 }
        XCTAssertEqual(received.first?.userID, "owner:open")
        let starts = await http.count("/api/v2/auth/device/start")
        XCTAssertEqual(starts, 1, "Going back from PIN must not require approving another code")
    }

    func testLockedProfileRequiresProofAndDuplicateSubmissionDoesNotSignInTwice() async throws {
        let http = SiloOnboardingHTTP()
        var received: [UserSession] = []
        let model = makeModel(http) { received.append($0) }
        defer { model.cancel() }
        model.start()
        try await wait { if case .profiles = model.phase { return true }; return false }
        guard case let .profiles(profiles) = model.phase else { return XCTFail("Missing profiles") }
        model.select(profiles[0])
        model.submitPIN(profiles[0])
        XCTAssertEqual(model.phase, .pin(profiles[0]), "Empty input must stay on the PIN field")
        model.pin = "1234"
        model.submitPIN(profiles[0])
        model.submitPIN(profiles[0])
        try await wait { received.count == 1 }
        let credential = try SiloCredential.decode(XCTUnwrap(received.first).accessToken)
        XCTAssertEqual(credential.profileID, "locked")
        XCTAssertEqual(credential.profileToken, "profile-proof")
        XCTAssertEqual(model.pin, "")
        let verificationCount = await http.count("/api/v2/profiles/locked/verify-pin")
        XCTAssertEqual(verificationCount, 1)
        let headers = await http.lastHeaders("/api/v2/playback/capabilities")
        XCTAssertEqual(headers?["X-Profile-Id"], "locked")
        XCTAssertEqual(headers?["X-Profile-Token"], "profile-proof")
    }

    func testProfileRetryReusesApprovalInsteadOfStartingOver() async throws {
        let http = SiloOnboardingHTTP(failFirstProfiles: true)
        let model = makeModel(http)
        defer { model.cancel() }
        model.start()
        try await wait { if case .error = model.phase { return true }; return false }
        model.retry()
        model.retry()
        try await wait { if case .profiles = model.phase { return true }; return false }
        let starts = await http.count("/api/v2/auth/device/start")
        let polls = await http.count("/api/v2/auth/device/poll")
        let profiles = await http.count("/api/v2/profiles")
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(polls, 1)
        XCTAssertEqual(profiles, 2)
    }

    func testCancellationRejectsLateSuccessfulSession() async throws {
        let http = SiloOnboardingHTTP(holdFinish: true)
        var received: [UserSession] = []
        let model = makeModel(http) { received.append($0) }
        model.start()
        try await wait { if case .profiles = model.phase { return true }; return false }
        guard case let .profiles(profiles) = model.phase else { return XCTFail("Missing profiles") }
        model.select(profiles[1])
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await !http.isFinishHeld, ContinuousClock.now < deadline { await Task.yield() }
        let held = await http.isFinishHeld
        XCTAssertTrue(held)
        model.cancel()
        await http.releaseFinish()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.verificationURL)
        XCTAssertTrue(received.isEmpty)
        model.select(profiles[1])
        XCTAssertEqual(model.phase, .idle, "A stale profile button cannot restart a cancelled login")
    }

    func testExpiredCodeStopsAtDeadlineAndCanBeRenewed() async throws {
        let http = SiloOnboardingHTTP(expiresIn: 1, interval: 30)
        let model = makeModel(http)
        defer { model.cancel() }
        model.start()
        try await wait { model.phase == .expired }
        XCTAssertNil(model.verificationURL)
        let polls = await http.count("/api/v2/auth/device/poll")
        XCTAssertEqual(polls, 0, "Do not wait for a long polling interval after code expiration")
        model.retry()
        try await wait { if case .pairing = model.phase { return true }; return false }
        let starts = await http.count("/api/v2/auth/device/start")
        XCTAssertEqual(starts, 2)
    }

    func testDeniedApprovalNeverAdvancesAndRetryRequestsNewCode() async throws {
        let http = SiloOnboardingHTTP(pollStatus: "denied")
        let model = makeModel(http)
        defer { model.cancel() }
        model.start()
        try await wait { if case .error = model.phase { return true }; return false }
        let profiles = await http.count("/api/v2/profiles")
        XCTAssertEqual(profiles, 0)
        model.retry()
        try await wait { if case .pairing = model.phase { return true }; return false }
        let starts = await http.count("/api/v2/auth/device/start")
        XCTAssertEqual(starts, 2)
    }

    func testBothApprovalLinksMustBelongToSelectedServer() async throws {
        for foreignManual in [true, false] {
            let http = SiloOnboardingHTTP(foreignManual: foreignManual, foreignApproval: !foreignManual)
            let model = makeModel(http)
            model.start()
            try await wait { if case .error = model.phase { return true }; return false }
            XCTAssertNil(model.verificationURL)
            let polls = await http.count("/api/v2/auth/device/poll")
            XCTAssertEqual(polls, 0)
            model.cancel()
        }
    }

    func testManualLinkIsSeparateFromPrefilledApprovalLink() async throws {
        let http = SiloOnboardingHTTP()
        let model = makeModel(http)
        defer { model.cancel() }
        model.start()
        try await wait { if case .pairing = model.phase { return true }; return false }
        guard case let .pairing(code, match, url, _) = model.phase else { return XCTFail("Missing pairing") }
        XCTAssertEqual(code, "ABCD12")
        XCTAssertEqual(match, "57")
        XCTAssertEqual(model.verificationURL?.absoluteString, "https://silo.test/pair")
        XCTAssertEqual(url.absoluteString, "https://silo.test/pair?code=ABCD12")
    }

    func testCancellingAddressVerificationRevokesOnlyItsNewLogin() async throws {
        let http = SiloOnboardingHTTP()
        let model = makeModel(http, verificationOnly: true)
        model.start()
        try await wait { if case .profiles = model.phase { return true }; return false }
        model.cancel()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await http.count("/api/v2/auth/logout") == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let headers = await http.lastHeaders("/api/v2/auth/logout")
        XCTAssertEqual(headers?["Authorization"], "Bearer test-access")
        model.cancel()
        let count = await http.count("/api/v2/auth/logout")
        XCTAssertEqual(count, 1)
    }

    private func makeModel(_ http: SiloOnboardingHTTP, verificationOnly: Bool = false,
                           diagnostics: SiloSetupDiagnostics = SiloSetupDiagnostics(),
                           completed: @escaping (UserSession) -> Void = { _ in XCTFail("Unexpected sign-in") }) -> SiloAuthViewModel {
        let url = URL(string: "https://silo.test")!
        return SiloAuthViewModel(
            server: MediaServer(id: "silo", name: "Silo", baseURL: url, provider: .silo),
            deviceID: "fixture", service: SiloAuthentication(baseURL: url, http: http),
            diagnostics: diagnostics,
            verificationOnly: verificationOnly,
            onAuthenticated: completed
        )
    }

    private func waitForPoll(_ http: SiloOnboardingHTTP) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while await http.count("/api/v2/auth/device/poll") == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let polls = await http.count("/api/v2/auth/device/poll")
        XCTAssertGreaterThan(polls, 0)
    }

    private func wait(timeout: TimeInterval = 4, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Onboarding did not reach the expected phase")
    }
}

private actor SiloOnboardingHTTP: HTTPClient {
    let failFirstProfiles: Bool
    let holdFinish: Bool
    let expiresIn: Int
    let interval: Int
    let pollStatus: String
    let foreignManual: Bool
    let foreignApproval: Bool
    let failFirstStart: Bool
    let extendsExpiry: Bool
    let emptyMatch: Bool
    let pollFailures: [Int: AppError]
    private(set) var pollTimes: [Date] = []
    private var requests: [Endpoint] = []
    private var finish: CheckedContinuation<Void, Never>?
    var isFinishHeld: Bool { finish != nil }

    init(failFirstProfiles: Bool = false, holdFinish: Bool = false, expiresIn: Int = 600,
         interval: Int = 1, pollStatus: String = "approved",
         foreignManual: Bool = false, foreignApproval: Bool = false,
         failFirstStart: Bool = false, extendsExpiry: Bool = false, emptyMatch: Bool = false,
         pollFailures: [Int: AppError] = [:]) {
        self.failFirstProfiles = failFirstProfiles
        self.holdFinish = holdFinish
        self.expiresIn = expiresIn
        self.interval = interval
        self.pollStatus = pollStatus
        self.foreignManual = foreignManual
        self.foreignApproval = foreignApproval
        self.failFirstStart = failFirstStart
        self.extendsExpiry = extendsExpiry
        self.emptyMatch = emptyMatch
        self.pollFailures = pollFailures
    }

    func count(_ path: String) -> Int { requests.filter { $0.path == path }.count }
    func lastHeaders(_ path: String) -> [String: String]? { requests.last { $0.path == path }?.headers }
    func releaseFinish() { finish?.resume(); finish = nil }

    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests.append(endpoint)
        let body: String
        switch endpoint.path {
        case "/api/v2/auth/logout": body = "{}"
        case "/api/v2/system/info": body = #"{"api_major":2}"#
        case "/api/v2/auth/device/capability":
            body = #"{"state":"available","protocol_versions":[2],"allowed":true}"#
        case "/api/v2/auth/device/start":
            if failFirstStart, count(endpoint.path) == 1 {
                return (Data("<html>private proxy response</html>".utf8),
                        HTTPURLResponse(url: baseURL, statusCode: 502, httpVersion: nil,
                                        headerFields: ["Content-Type": "text/html"])!)
            }
            body = """
            {"device_code":"device-secret","user_code":"ABCD12","match_code":"\(emptyMatch ? "" : "57")",
             "verification_uri":"https://\(foreignManual ? "other" : "silo").test/pair",
             "verification_uri_complete":"https://\(foreignApproval ? "other" : "silo").test/pair?code=ABCD12",
             "expires_in":\(expiresIn),"interval":\(interval)}
            """
        case "/api/v2/auth/device/poll":
            pollTimes.append(Date())
            if let failure = pollFailures[count(endpoint.path)] { throw failure }
            if extendsExpiry, count(endpoint.path) == 1 {
                let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(20))
                return (Data("""
                    {"status":"pending","poll_after":1,"temporary":false,"expires_at":"\(expiry)"}
                    """.utf8), HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            body = """
            {"status":"\(pollStatus)","poll_after":1,"temporary":false,
             "tokens":{"access_token":"test-access","refresh_token":"test-refresh",
             "expires_in":3600,"user":{"id":"owner","username":"Owner"}}}
            """
        case "/api/v2/profiles":
            if failFirstProfiles, count(endpoint.path) == 1 { throw AppError.serverUnreachable }
            body = """
            {"items":[{"id":"locked","name":"Protected","has_pin":true,"is_child":false},
                      {"id":"open","name":"Guest","has_pin":false,"is_child":false}]}
            """
        case "/api/v2/profiles/locked/verify-pin":
            let object = try JSONSerialization.jsonObject(with: XCTUnwrap(endpoint.body)) as? [String: String]
            body = object?["pin"] == "1234"
                ? #"{"valid":true,"profile_token":"profile-proof"}"# : #"{"valid":false}"#
        case "/api/v2/playback/capabilities":
            if holdFinish { await withCheckedContinuation { finish = $0 } }
            body = """
            {"installation_id":"server","protocol_versions":[3],"features":[],"deliveries":[],
             "state":"available","allowed":true}
            """
        default: throw AppError.notFound
        }

        return (Data(body.utf8), HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private final class SiloAuthDiagnosticBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SiloSetupDiagnostic] = []
    var values: [SiloSetupDiagnostic] { lock.withLock { storage } }
    func append(_ value: SiloSetupDiagnostic) { lock.withLock { storage.append(value) } }
}
