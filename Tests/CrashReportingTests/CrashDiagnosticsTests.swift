#if canImport(Sentry)
import CoreModels
import Foundation
import Sentry
import XCTest
@testable import CrashReporting

final class CrashDiagnosticsTests: XCTestCase {
    @MainActor
    func testEveryDiagnosticSendAppendsSourceSnapshotAfterConsentCheck() {
        var snapshots = 0
        XCTAssertFalse(CrashDiagnostics.send(
            logText: "activity", note: nil, isEnabled: false,
            sourceDiagnostics: { snapshots += 1; return "source evidence" },
            captureEvent: { _, _ in XCTFail("No consent"); return .empty },
            captureFeedback: { _ in XCTFail("No consent"); return .empty }
        ))
        XCTAssertEqual(snapshots, 0)
        XCTAssertTrue(CrashDiagnostics.send(
            logText: "activity", note: nil, isEnabled: true,
            sourceDiagnostics: { snapshots += 1; return "source evidence" },
            captureEvent: { _, attachment in
                XCTAssertEqual(
                    attachment.data,
                    Data("activity\n\n--- Persistent Live TV source diagnostics ---\nsource evidence".utf8)
                )
                return SentryId()
            },
            captureFeedback: { _ in SentryId() }
        ))
        XCTAssertEqual(snapshots, 1)
    }

    @MainActor
    func testSubmissionLinksAnonymousFeedbackToCapturedEventAndPreservesLog() {
        let capturedID = SentryId()
        var didCaptureEvent = false
        var didCaptureFeedback = false

        let sent = CrashDiagnostics.send(
            logText: "\nredacted recent activity\n",
            note: "  Sources disappeared\n",
            isEnabled: true,
            captureEvent: { event, attachment in
                didCaptureEvent = true
                XCTAssertEqual(event.level, .info)
                XCTAssertEqual(event.message?.formatted, "Sources disappeared")
                XCTAssertEqual(event.tags?["report.kind"], "user-diagnostics")
                XCTAssertEqual(attachment.filename, "plozz-recent-activity.log")
                XCTAssertEqual(attachment.contentType, "text/plain")
                XCTAssertEqual(attachment.data, Data("redacted recent activity".utf8))
                return capturedID
            },
            captureFeedback: { feedback in
                didCaptureFeedback = true
                XCTAssertTrue(didCaptureEvent)
                XCTAssertNil(feedback.type, "Feedback must enter the SDK through beforeSend.")
                XCTAssertEqual(feedback.tags?["report.kind"], "user-feedback")
                let payload = feedback.context?["feedback"] ?? [:]
                XCTAssertEqual(Set(payload.keys), ["message", "source", "associated_event_id"])
                XCTAssertEqual(payload["message"] as? String, "Sources disappeared")
                XCTAssertEqual(payload["source"] as? String, "custom")
                XCTAssertEqual(payload["associated_event_id"] as? String, capturedID.sentryIdString)
                return SentryId()
            }
        )

        XCTAssertTrue(sent)
        XCTAssertTrue(didCaptureEvent)
        XCTAssertTrue(didCaptureFeedback)
    }

    @MainActor
    func testInactiveReportingSubmitsNeitherEventNorFeedback() {
        XCTAssertFalse(CrashDiagnostics.send(
            logText: "recent activity", note: "note", isEnabled: false,
            captureEvent: { _, _ in
                XCTFail("Inactive reporting must not capture diagnostics.")
                return SentryId()
            },
            captureFeedback: { _ in
                XCTFail("Inactive reporting must not capture feedback.")
                return .empty
            }
        ))
    }

    @MainActor
    func testRejectedEventDoesNotReportSuccessOrSubmitUnlinkedFeedback() {
        var didCaptureEvent = false
        XCTAssertFalse(CrashDiagnostics.send(
            logText: "recent activity", note: "note", isEnabled: true,
            captureEvent: { _, _ in
                didCaptureEvent = true
                return .empty
            },
            captureFeedback: { _ in
                XCTFail("Rejected diagnostics must not create feedback.")
                return .empty
            }
        ))
        XCTAssertTrue(didCaptureEvent)
    }

    @MainActor
    func testRejectedFeedbackDoesNotReportSuccess() {
        var didCaptureFeedback = false
        XCTAssertFalse(CrashDiagnostics.send(
            logText: "recent activity", note: "note", isEnabled: true,
            captureEvent: { _, _ in SentryId() },
            captureFeedback: { _ in
                didCaptureFeedback = true
                return .empty
            }
        ))
        XCTAssertTrue(didCaptureFeedback)
    }

    @MainActor
    func testBlankNotesAndLogsHaveNonemptyFallbacksOnBothReports() {
        for note: String? in [nil, "", " \n\t "] {
            var didCaptureFeedback = false
            XCTAssertTrue(CrashDiagnostics.send(
                logText: " \n\t ", note: note, isEnabled: true,
                captureEvent: { event, attachment in
                    XCTAssertEqual(event.message?.formatted, "User diagnostics report")
                    XCTAssertEqual(attachment.data, Data("(recent activity log was empty)".utf8))
                    return SentryId()
                },
                captureFeedback: { feedback in
                    didCaptureFeedback = true
                    XCTAssertEqual(feedback.context?["feedback"]?["message"] as? String, "User diagnostics report")
                    return SentryId()
                }
            ))
            XCTAssertTrue(didCaptureFeedback)
        }
    }

    func testBeforeSendRetainsFeedbackAssociationButRemovesIdentityAndArbitraryFields() throws {
        let associatedID = SentryId()
        let feedback = SentryFeedback(
            message: "Sources disappeared", name: "Private name", email: "private@example.test",
            source: .custom, associatedEventId: associatedID
        )
        let event = Event(level: .info)
        event.tags = ["report.kind": "user-feedback"]
        event.user = User(userId: "private-user")
        event.serverName = "private-server"
        event.extra = ["private": "extra"]
        event.context = [
            "feedback": feedback.serialize().merging(["unexpected": "private"]) { _, new in new },
            "private": ["url": "https://private.test"]
        ]

        let clean = try XCTUnwrap(SentryCrashReporter.prepareEvent(event, diagnostics: PerformanceDiagnostics()))
        let payload = try XCTUnwrap(clean.context?["feedback"])
        XCTAssertEqual(clean.type, "feedback")
        XCTAssertEqual(Set(payload.keys), ["message", "source", "associated_event_id"])
        XCTAssertEqual(payload["message"] as? String, "Sources disappeared")
        XCTAssertEqual(payload["source"] as? String, "custom")
        XCTAssertEqual(payload["associated_event_id"] as? String, associatedID.sentryIdString)
        XCTAssertNil(clean.user)
        XCTAssertNil(clean.serverName)
        XCTAssertNil(clean.extra)
        XCTAssertNil(clean.context?["private"])
    }

    @MainActor
    func testSDKCaptureRunsPrivacyHookBeforeFeedbackClassification() throws {
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("plozz-feedback-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: cache) }
        let options = Options()
        options.dsn = "https://test@127.0.0.1:1/1"
        options.cacheDirectoryPath = cache.path
        options.sendClientReports = false
        options.attachStacktrace = false
        var didPrepareFeedback = false
        options.beforeSend = { event in
            if event.tags?["report.kind"] == "user-feedback" {
                didPrepareFeedback = true
                XCTAssertNil(event.type)
                let clean = SentryCrashReporter.prepareEvent(event, diagnostics: PerformanceDiagnostics())
                XCTAssertEqual(clean?.type, "feedback")
                XCTAssertEqual(clean?.context?["feedback"]?["message"] as? String, "Sources disappeared")
                XCTAssertNil(clean?.user)
                XCTAssertNil(clean?.context?["os"])
                XCTAssertNil(clean?.context?["culture"])
            }
            return nil // Exercise SDK preparation without enqueuing or uploading an event.
        }
        let client = try XCTUnwrap(SentryClient(options: options))
        defer { client.close() }
        XCTAssertFalse(CrashDiagnostics.send(
            logText: "recent activity", note: "Sources disappeared", isEnabled: true,
            captureEvent: { _, _ in SentryId() },
            captureFeedback: { client.capture(event: $0) }
        ))
        XCTAssertTrue(didPrepareFeedback)
    }

    func testMalformedFeedbackIsRejectedInsteadOfSendingAnEmptyFeedbackEvent() {
        let valid = SentryFeedback(
            message: "Sources disappeared", name: nil, email: nil,
            source: .custom, associatedEventId: SentryId()
        ).serialize()
        for (key, value): (String, Any?) in [
            ("message", nil), ("message", " \n\t "), ("message", 42),
            ("source", nil), ("source", "widget"),
            ("associated_event_id", nil), ("associated_event_id", "private"),
            ("associated_event_id", SentryId.empty.sentryIdString)
        ] {
            var payload = valid
            payload[key] = value
            let event = Event(level: .info)
            event.type = "feedback"
            event.context = ["feedback": payload]
            XCTAssertNil(CrashRedaction.scrub(event), key)
        }
        let missingContext = Event(level: .info)
        missingContext.type = "feedback"
        XCTAssertNil(CrashRedaction.scrub(missingContext))
    }

    func testNonFeedbackEventsCannotRetainFeedbackContext() throws {
        let event = Event(level: .info)
        event.context = ["feedback": SentryFeedback(
            message: "Sources disappeared", name: nil, email: nil,
            source: .custom, associatedEventId: SentryId()
        ).serialize()]
        XCTAssertNil(try XCTUnwrap(CrashRedaction.scrub(event)).context?["feedback"])
    }
}
#endif
