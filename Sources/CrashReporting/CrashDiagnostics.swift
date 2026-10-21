import Foundation
import CoreModels
#if canImport(Sentry)
import Sentry
#endif

/// On-demand upload of the user's recent (already-redacted) log buffer to the
/// crash-reporting backend, so the developer can read the full log on a real
/// computer instead of squinting at a TV or trying to scan an impossibly dense
/// QR code.
///
/// This deliberately piggybacks on the existing opt-in Sentry pipe: it only does
/// anything when crash reporting is both **configured** (a DSN was baked into the
/// build) *and* **enabled** (the user turned it on in Help & Diagnostics, so the
/// SDK is actually running). Otherwise it sends nothing and returns `false`, and
/// the caller should tell the user to turn crash reporting on first.
public enum CrashDiagnostics {
    /// Send a diagnostic event with its log attachment and linked anonymous feedback.
    /// Returns `true` for SDK handoff, not confirmation of server delivery;
    /// `false` when reporting is inactive or either event was rejected.
    @MainActor
    @discardableResult
    public static func send(logText: String, note: String? = nil) -> Bool {
        #if canImport(Sentry)
        return send(
            logText: logText,
            note: note,
            isEnabled: SentrySDK.isEnabled,
            sourceDiagnostics: { LiveTVSourceDiagnostics.captureReport() },
            captureEvent: { event, attachment in
                SentrySDK.capture(event: event) { scope in
                    scope.addAttachment(attachment)
                }
            },
            captureFeedback: { SentrySDK.capture(event: $0) }
        )
        #else
        return false
        #endif
    }

    #if canImport(Sentry)
    @MainActor
    static func send(
        logText: String,
        note: String?,
        isEnabled: Bool,
        sourceDiagnostics: @MainActor () -> String = { "" },
        captureEvent: (Event, Attachment) -> SentryId,
        captureFeedback: (Event) -> SentryId
    ) -> Bool {
        guard isEnabled else { return false }

        let trimmed = logText.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = trimmed.isEmpty ? "(recent activity log was empty)" : trimmed
        let sourceJournal = sourceDiagnostics()
        if !sourceJournal.isEmpty {
            body += "\n\n--- Persistent Live TV source diagnostics ---\n" + sourceJournal
        }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message = trimmedNote.isEmpty ? "User diagnostics report" : trimmedNote
        let attachment = Attachment(
            data: Data(body.utf8),
            filename: "plozz-recent-activity.log",
            contentType: "text/plain"
        )

        let event = Event(level: .info)
        event.message = SentryMessage(formatted: message)
        event.tags = ["report.kind": "user-diagnostics"]
        let eventID = captureEvent(event, attachment)
        guard eventID != .empty else { return false }

        let feedback = SentryFeedback(
            message: message,
            name: nil,
            email: nil,
            source: .custom,
            associatedEventId: eventID
        )
        // Sentry's feedback convenience API bypasses beforeSend. Keep this a
        // normal event until our privacy hook scrubs it and sets the feedback type.
        let feedbackEvent = Event(level: .info)
        feedbackEvent.tags = ["report.kind": "user-feedback"]
        feedbackEvent.context = ["feedback": feedback.serialize()]
        return captureFeedback(feedbackEvent) != .empty
    }
    #endif

    /// Whether a diagnostics report can actually be sent right now (the SDK is
    /// live). UIs can use this to enable/disable a "Send to developer" button,
    /// though gating on the crash-reporting consent flag is usually clearer.
    @MainActor
    public static var isAvailable: Bool {
        #if canImport(Sentry)
        return SentrySDK.isEnabled
        #else
        return false
        #endif
    }
}
