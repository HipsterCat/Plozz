#if canImport(Sentry)
import CoreModels
import Sentry
import XCTest
@testable import CrashReporting

final class DeviceSetupRedactionTests: XCTestCase {
    func testAutomaticFailureContainsOnlyClosedDiagnosticFields() throws {
        let event = Event(level: .warning)
        event.tags = ["report.kind": "device-setup", "host": "private.invalid", "app.build": "58"]
        event.message = SentryMessage(formatted: "credential")
        event.fingerprint = ["private server"]
        event.extra = ["token": "credential"]
        event.context = ["device_setup": [
            "role": "receiver", "route": "receive", "stage": "handshake", "outcome": "failed",
            "reason": "framing", "elapsedMilliseconds": 123,
            "address": "private.invalid", "payload": "credential", "deviceName": "Private phone"
        ]]
        let cleaned = try XCTUnwrap(CrashRedaction.scrub(event))
        XCTAssertEqual(cleaned.message?.formatted, "Device setup failed")
        XCTAssertEqual(cleaned.fingerprint, ["device_setup", "receiver:receive:handshake:framing"])
        XCTAssertEqual(cleaned.tags?["app.build"], "58")
        XCTAssertNil(cleaned.tags?["host"])
        XCTAssertNil(cleaned.extra)
        XCTAssertEqual(Set(cleaned.context?["device_setup"]?.keys.map { $0 } ?? []),
                       ["role", "route", "stage", "outcome", "reason", "elapsedMilliseconds"])
        cleaned.context?["device_setup"]?["reason"] = "credential"
        XCTAssertNil(CrashRedaction.scrub(cleaned))
    }

    func testCancellationSuccessAndInvalidDurationsNeverBecomeFailureEvents() {
        for diagnostic in [
            DeviceSetupDiagnostic(role: .sender, route: .code, stage: .transfer, outcome: .succeeded),
            .init(role: .sender, route: .code, stage: .confirmation, outcome: .cancelled, reason: .rejected),
            .init(role: .receiver, route: .receive, stage: .connection, outcome: .cancelled, reason: .cancelled)
        ] {
            XCTAssertNil(SentryCrashReporter.deviceSetupEvent(diagnostic))
        }
        let event = Event(level: .warning)
        event.tags = ["report.kind": "device-setup"]
        for invalid in [-1, 86_400_001] {
            event.context = ["device_setup": [
                "role": "sender", "route": "qr", "stage": "connection", "outcome": "failed",
                "reason": "connection", "elapsedMilliseconds": invalid
            ]]
            XCTAssertNil(CrashRedaction.scrub(event))
        }
    }
}
#endif
