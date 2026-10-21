import CoreModels
import Foundation
import XCTest

final class PlaybackFailureDiagnosticTests: XCTestCase {
    func testLocalPlaybackEvidenceDoesNotEnableRemoteReporting() throws {
        let diagnostics = PlaybackFailureDiagnostics()
        let attempt = try XCTUnwrap(diagnostics.begin(
            layer: .liveEngine, content: .live, captureForPresentation: true
        ))
        let buffer = PlaybackFailureBuffer()
        diagnostics.start { buffer.append($0) }
        attempt.fail(stage: .load, reason: .network, domain: .url, code: -1001)
        XCTAssertTrue(buffer.values.isEmpty)
        XCTAssertEqual(attempt.diagnostic?.code, -1001)
        let report = LiveChannelFailureReport(failure: .engine(.serverUnreachable), diagnostic: attempt.diagnostic)
        XCTAssertTrue(String(localized: report.message).contains("did not respond in time"))
        XCTAssertFalse(PlaybackDiagnosticReport.playback(report).supportText.contains("http_status"))
    }

    func testSupportReportNeverExportsUnknownErrorDescriptions() {
        let privateDescription = "https://private.invalid/live/user/password?token=private-secret"
        let report = LiveChannelFailureReport(failure: .engine(.unknown(privateDescription)))
        XCTAssertEqual(PlaybackDiagnosticReport.playback(report).supportText,
                       "format=plozz-live-tv-2\noperation=playback\nfailure=unknown")
        XCTAssertFalse(String(localized: report.message).contains("private"))
    }

    func testTerminalDeliveryReportKeepsMatchingStatusAfterAnEarlierRecoverableFailure() throws {
        let attempt = try XCTUnwrap(PlaybackFailureDiagnostics().begin(
            layer: .iptvProxy, content: .live, captureForPresentation: true
        ))
        attempt.fail(stage: .response, reason: .notFound, httpStatus: 404)
        let refusal = attempt.fail(stage: .response, reason: .authentication, httpStatus: 403)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:12345/fixture"))
        let delivery = PlaybackDeliveryFailure.register(loopbackURL: url)
        defer { PlaybackDeliveryFailure.unregister(loopbackURL: url) }
        delivery.record(.unauthorized, diagnostic: refusal)
        XCTAssertEqual(delivery.diagnostic?.httpStatus, 403)
        XCTAssertEqual(attempt.diagnostic?.httpStatus, 404, "Remote diagnostics still record only the first failure.")
    }

    func testConsentRevocationDiscardsRetainedAttemptsEvenAfterReenabling() throws {
        let diagnostics = PlaybackFailureDiagnostics()
        let buffer = PlaybackFailureBuffer()
        XCTAssertNil(diagnostics.begin(layer: .iptvProxy, content: .live))
        diagnostics.start { buffer.append($0) }
        let stale = try XCTUnwrap(diagnostics.begin(layer: .iptvProxy, content: .live))
        diagnostics.stop()
        diagnostics.start { buffer.append($0) }
        stale.fail(stage: .response, reason: .authentication, httpStatus: 403)
        XCTAssertTrue(buffer.values.isEmpty)
        let current = try XCTUnwrap(diagnostics.begin(layer: .iptvProxy, content: .live))
        current.fail(stage: .response, reason: .authentication, httpStatus: 403)
        current.fail(stage: .body, reason: .network)
        XCTAssertEqual(buffer.values.count, 1)
        XCTAssertEqual(buffer.values.first?.httpStatus, 403)
    }

    func testCancellationAndUnboundedCodesCannotBecomeFailureReports() throws {
        let diagnostics = PlaybackFailureDiagnostics()
        let buffer = PlaybackFailureBuffer()
        diagnostics.start { buffer.append($0) }
        let attempt = try XCTUnwrap(diagnostics.begin(layer: .liveEngine, content: .live))
        attempt.fail(stage: .load, reason: .cancelled)
        XCTAssertTrue(buffer.values.isEmpty)
        attempt.fail(stage: .playback, engineFailure: .nativeItemFailed, domain: .avfoundation,
                     code: Int.max, httpStatus: Int.max)
        let diagnostic = try XCTUnwrap(buffer.values.first)
        XCTAssertNil(diagnostic.code)
        XCTAssertNil(diagnostic.httpStatus)
        XCTAssertTrue(diagnostic.isValid)
        XCTAssertEqual(diagnostic.engineFailure, .nativeItemFailed)
    }

    func testUnknownContentTypesAndDomainsNeverRetainFreeFormValues() {
        XCTAssertEqual(PlaybackFailureDiagnostic.Format(mimeType: "video/MP2T; private=secret"), .transportStream)
        XCTAssertEqual(PlaybackFailureDiagnostic.Format(mimeType: "text/html"), .html)
        XCTAssertEqual(PlaybackFailureDiagnostic.Format(mimeType: "https://private.test"), .other)
        XCTAssertEqual(PlaybackFailureDiagnostic.Domain("https://private.test"), .other)
    }

    func testNativeChainAndCopiedReportKeepCausesWithoutPrivateUserInfo() throws {
        let privateText = "https://private.test/live/user/password?token=secret"
        let underlying = NSError(domain: "CoreMediaErrorDomain", code: -12939, userInfo: [
            NSLocalizedDescriptionKey: privateText, NSURLErrorFailingURLErrorKey: privateText
        ])
        let error = NSError(domain: "AVFoundationErrorDomain", code: -11850, userInfo: [
            NSUnderlyingErrorKey: underlying, NSLocalizedFailureReasonErrorKey: privateText
        ])
        let evidence = PlaybackFailureEvidence(
            route: .nativeHLS, firstFrameReady: false, nativeCapture: .captured,
            nativeErrors: PlaybackFailureEvidence.ErrorCode.chain(error)
        )
        let attempt = try XCTUnwrap(PlaybackFailureDiagnostics().begin(
            layer: .liveEngine, content: .live, captureForPresentation: true
        ))
        attempt.fail(stage: .playback, engineFailure: .nativeItemFailed, domain: .avfoundation,
                     code: -11850, evidence: evidence)
        let report = PlaybackDiagnosticReport.playback(.init(
            failure: .engine(.invalidResponse), diagnostic: attempt.diagnostic
        )).supportText
        XCTAssertTrue(report.contains("native_error_0=avfoundation:-11850"))
        XCTAssertTrue(report.contains("native_error_1=coremedia:-12939"))
        XCTAssertTrue(report.contains("route=nativeHLS"))
        XCTAssertFalse(report.contains("private"))
        let keys = report.split(separator: "\n").map { $0.split(separator: "=")[0] }
        XCTAssertEqual(Set(keys).count, keys.count, "Protocol and media format must not share a key.")
        let data = try JSONEncoder().encode(XCTUnwrap(attempt.diagnostic))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret"))
    }

    func testDeliveryTrailIsBoundedRetainsFirstFailureAndDoesNotPoisonPlayback() throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:12345/fixture"))
        let state = PlaybackDeliveryFailure.register(loopbackURL: url)
        defer { PlaybackDeliveryFailure.unregister(loopbackURL: url) }
        for sequence in 1...20 {
            var request = PlaybackDeliveryEvidence.Request(
                sequence: sequence, resource: sequence == 1 ? .root : .child,
                method: .get, startedMilliseconds: sequence
            )
            request.status = sequence == 2 ? 404 : 200
            request.outcome = sequence == 2 ? .upstreamFailure : .complete
            request.format = sequence == 1 ? .hls : .transportStream
            state.recordRequest(request)
        }
        XCTAssertEqual(state.evidence.recent.map(\.sequence), Array(13...20))
        XCTAssertEqual(state.evidence.root?.format, .hls)
        XCTAssertEqual(state.evidence.firstFailure?.status, 404)
        XCTAssertNil(state.error, "Evidence of a recovered request is not a terminal playback verdict.")
        XCTAssertNil(state.diagnostic)
        XCTAssertTrue(state.evidence.isValid)
        PlaybackDeliveryFailure.unregister(loopbackURL: url)
        XCTAssertEqual(state.evidence.firstFailure?.sequence, 2)
        let replacement = PlaybackDeliveryFailure.register(loopbackURL: url)
        XCTAssertTrue(replacement.evidence.recent.isEmpty, "A replacement playback owns fresh evidence.")
    }

    func testLegacyDiagnosticsDecodeWithoutEvidenceAndNativeChainsAreBounded() throws {
        var error = NSError(domain: "CoreMediaErrorDomain", code: -1)
        for _ in 0..<20 {
            error = NSError(domain: "AVFoundationErrorDomain", code: -11850, userInfo: [NSUnderlyingErrorKey: error])
        }
        XCTAssertEqual(PlaybackFailureEvidence.ErrorCode.chain(error).count, 8)
        let legacy = Data("""
        {"layer":"liveEngine","content":"live","stage":"playback","reason":"other",
         "engineFailure":"nativeItemFailed","domain":"avfoundation","code":-11850,
         "format":"unknown","elapsedMilliseconds":947}
        """.utf8)
        let diagnostic = try JSONDecoder().decode(PlaybackFailureDiagnostic.self, from: legacy)
        XCTAssertNil(diagnostic.evidence)
        XCTAssertTrue(diagnostic.isValid)
    }

    func testCompletedRootEvidenceSurvivesIncompleteRefreshes() throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:12345/refresh-fixture"))
        let state = PlaybackDeliveryFailure.register(loopbackURL: url)
        defer { PlaybackDeliveryFailure.unregister(loopbackURL: url) }
        var completed = PlaybackDeliveryEvidence.Request(
            sequence: 1, resource: .root, method: .get, startedMilliseconds: 0
        )
        completed.status = 200
        completed.outcome = .complete
        completed.format = .hls
        completed.playlist = .init(
            hasHeader: true, isMaster: false, targetDurationMilliseconds: 6_000,
            maximumSegmentMilliseconds: 6_000, mediaSequence: 100, segments: 1,
            hasEndList: false, hasByteRanges: false, hasMap: false, hasEncryption: false
        )
        state.recordRequest(completed)

        var refresh = PlaybackDeliveryEvidence.Request(
            sequence: 2, resource: .root, method: .get, startedMilliseconds: 1
        )
        for outcome in [PlaybackDeliveryEvidence.Outcome.pending, .receiving, .consumerClosed, .upstreamFailure] {
            refresh.outcome = outcome
            state.recordRequest(refresh)
            XCTAssertEqual(state.evidence.root, completed)
            XCTAssertEqual(state.evidence.recent.last, refresh)
        }
        XCTAssertEqual(state.evidence.firstFailure, refresh)

        refresh.outcome = .complete
        refresh.format = .hls
        refresh.playlist = completed.playlist
        refresh.playlist?.mediaSequence = 101
        state.recordRequest(refresh)
        XCTAssertEqual(state.evidence.root, refresh)
        state.recordRequest(completed)
        XCTAssertEqual(state.evidence.root, refresh, "Older completions must not replace the newer response.")
    }

    func testRootHeadEvidenceUpdatesUntilAGetProvidesThePlaybackFacts() throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:12345/head-fixture"))
        let state = PlaybackDeliveryFailure.register(loopbackURL: url)
        defer { PlaybackDeliveryFailure.unregister(loopbackURL: url) }
        var head = PlaybackDeliveryEvidence.Request(
            sequence: 1, resource: .root, method: .head, startedMilliseconds: 0
        )
        state.recordRequest(head)
        head.status = 200
        head.outcome = .complete
        state.recordRequest(head)
        XCTAssertEqual(state.evidence.root?.status, 200)
        XCTAssertEqual(state.evidence.root?.outcome, .complete)

        var get = PlaybackDeliveryEvidence.Request(
            sequence: 2, resource: .root, method: .get, startedMilliseconds: 1
        )
        get.format = .hls
        state.recordRequest(get)
        head.sequence = 3
        state.recordRequest(head)
        XCTAssertEqual(state.evidence.root?.method, .get)
        XCTAssertEqual(state.evidence.root?.format, .hls)
    }
}

private final class PlaybackFailureBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [PlaybackFailureDiagnostic] = []
    var values: [PlaybackFailureDiagnostic] { lock.withLock { storage } }
    func append(_ value: PlaybackFailureDiagnostic) { lock.withLock { storage.append(value) } }
}
