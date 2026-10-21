import CoreModels
import Foundation
import XCTest

final class PlaybackDiagnosticReportTests: XCTestCase {
    func testNonVideoResponsesExplainOnlyObservedContentWithoutGuessingAuthorization() throws {
        for (format, expected) in [
            (PlaybackFailureDiagnostic.Format.html, "web page"),
            (.json, "data document"), (.xml, "data document"), (.empty, "empty video")
        ] {
            let attempt = try XCTUnwrap(PlaybackFailureDiagnostics().begin(
                layer: .iptvProxy, content: .live, captureForPresentation: true
            ))
            let diagnostic = attempt.fail(stage: .body, reason: .invalidResponse, httpStatus: 200, format: format)
            let report = LiveChannelFailureReport(failure: .engine(.invalidResponse), diagnostic: diagnostic)
            let message = String(localized: report.message)
            XCTAssertTrue(message.contains(expected))
            XCTAssertFalse(message.contains("sign in"))
            XCTAssertFalse(message.contains("expired"))
            XCTAssertTrue(PlaybackDiagnosticReport.playback(report).supportText.contains("stream_format=\(format.rawValue)"))
            let unauthorized = LiveChannelFailureReport(failure: .engine(.unauthorized), diagnostic: diagnostic)
            XCTAssertEqual(unauthorized.message, LiveChannelPlaybackFailure.engineMessage(.unauthorized))
            let decoded = try JSONDecoder().decode(
                PlaybackFailureDiagnostic.self, from: JSONEncoder().encode(XCTUnwrap(diagnostic))
            )
            XCTAssertEqual(decoded.format, format)
        }
    }

    func testRecognizedConnectionLimitIsNotReplacedByGenericServerErrorCopy() throws {
        let attempt = try XCTUnwrap(PlaybackFailureDiagnostics().begin(
            layer: .iptvProxy, content: .live, captureForPresentation: true
        ))
        let diagnostic = attempt.fail(stage: .response, httpStatus: 503)
        let report = LiveChannelFailureReport(failure: .engine(.conflict), diagnostic: diagnostic)
        XCTAssertEqual(report.message, LiveChannelPlaybackFailure.engineMessage(.conflict))
        XCTAssertTrue(PlaybackDiagnosticReport.playback(report).supportText.contains("failure=tunerUnavailable"))
        XCTAssertTrue(PlaybackDiagnosticReport.playback(report).supportText.contains("http_status=503"))
        let ordinary = LiveChannelFailureReport(failure: .engine(.invalidResponse), diagnostic: diagnostic)
        XCTAssertNotEqual(ordinary.message, report.message)
    }

    func testOnDemandReportPreservesFactsWithoutInventingSessionExpiry() {
        let report = PlaybackDiagnosticReport.onDemand(
            error: .playback(.init(kind: .unavailable, httpStatus: 410, engineFailure: .sourceRefused)),
            provider: .silo, engine: .plozzigen, stage: .opening
        )
        XCTAssertEqual(report.supportText, """
        format=plozz-playback-1
        operation=playback
        content=onDemand
        provider=silo
        engine=plozzigen
        stage=opening
        failure=HTTP 410
        reason=unavailable
        engine_failure=sourceRefused
        http_status=410
        """)
        XCTAssertFalse(report.supportText.contains("expired"))
        XCTAssertFalse(String(localized: report.message!).contains("expired"))
    }

    func testPreparationReportHasNoEngineAndKeepsProviderRejection() {
        let report = PlaybackDiagnosticReport.onDemand(
            error: .serverRefusal("Plozz requires a seekable stream.", reason: .nonSeekable),
            provider: .silo, engine: nil, stage: .preparation
        )
        XCTAssertTrue(report.supportText.contains("failure=nonSeekable"))
        XCTAssertTrue(report.supportText.contains("stage=preparation"))
        XCTAssertFalse(report.supportText.contains("engine="))
    }

    func testCapturedErrorChainExcludesPrivateTextAndKeepsEveryNumericCause() {
        let secret = "https://private.invalid/path?token=secret"
        let inner = NSError(domain: "CoreMediaErrorDomain", code: -12939,
                            userInfo: [NSLocalizedDescriptionKey: secret])
        let outer = NSError(domain: "AVFoundationErrorDomain", code: -11850,
                            userInfo: [NSUnderlyingErrorKey: inner, NSLocalizedDescriptionKey: secret])
        let report = PlaybackDiagnosticReport.onDemand(
            error: .playback(.init(
                kind: .unknown, engineFailure: .nativeItemFailed,
                underlyingErrors: PlaybackFailureEvidence.ErrorCode.chain(outer)
            )),
            provider: .plex, engine: .native, stage: .playback,
            negotiatedCodec: .h264, retryCodec: .hevc
        )
        XCTAssertTrue(report.supportText.contains("underlying_error_0=avfoundation:-11850"))
        XCTAssertTrue(report.supportText.contains("underlying_error_1=coremedia:-12939"))
        XCTAssertTrue(report.supportText.contains("negotiated_codec=h264"))
        XCTAssertTrue(report.supportText.contains("retried_codec=hevc"))
        XCTAssertFalse(report.supportText.contains("private"))
        XCTAssertFalse(report.supportText.contains("secret"))
    }

    func testAdviceDoesNotReplaceKnownCauseOrInventOne() {
        for error in [
            StreamingQualityError.negotiationFailed, .authenticationRequired, .permissionDenied,
            .sourceUnavailable, .startupTimedOut,
            .playback(.init(kind: .readinessTimedOut)),
            .playback(.init(kind: .audioOutputFailed)),
            .playback(.init(kind: .rateLimited)),
            .playback(.init(kind: .accessRestricted)),
            .playback(.init(kind: .hdrConversionUnconfirmed)),
            .playback(.init(kind: .network, domain: .url, code: -1206))
        ] {
            let message = String(localized: error.userMessage)
            for speculation in ["Check ", "Try ", "subscription", "tone mapping", "your device’s date", "other playback sessions"] {
                XCTAssertFalse(message.contains(speculation), message)
            }
        }
        XCTAssertNotEqual(StreamingPlaybackFailure(kind: .unavailable, httpStatus: 404).userMessage,
                          StreamingPlaybackFailure(kind: .unavailable, httpStatus: 410).userMessage)
        XCTAssertEqual(StreamingPlaybackFailure(kind: .unknown, engineFailure: .audioTrackSwitchFailed).userMessage,
                       PlaybackFailureDiagnostic.EngineFailure.audioTrackSwitchFailed.message)
    }
}
