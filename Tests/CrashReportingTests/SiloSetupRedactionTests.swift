#if canImport(Sentry)
import CoreModels
import Sentry
import XCTest
@testable import CrashReporting

final class SiloSetupRedactionTests: XCTestCase {
    func testSiloFailureReconstructsOnlyClosedFields() throws {
        let event = Event(level: .warning)
        event.tags = ["report.kind": "silo-setup", "host": "private.invalid"]
        event.message = SentryMessage(formatted: "secret")
        event.extra = ["token": "secret"]
        event.context = ["silo_setup": [
            "stage": "start", "reason": "server", "httpStatus": 502, "response": "html",
            "address": "private.invalid", "body": "secret"
        ]]
        let cleaned = try XCTUnwrap(CrashRedaction.scrub(event))
        XCTAssertEqual(cleaned.message?.formatted, "Silo setup failed")
        XCTAssertNil(cleaned.tags?["host"])
        XCTAssertNil(cleaned.extra)
        XCTAssertEqual(Set(cleaned.context?["silo_setup"]?.keys.map { $0 } ?? []),
                       ["stage", "reason", "httpStatus", "response"])
        XCTAssertEqual(cleaned.fingerprint, ["silo_setup", "start", "server", "502", "html"])
        cleaned.context?["silo_setup"]?["stage"] = "secret"
        XCTAssertNil(CrashRedaction.scrub(cleaned))
    }
}
#endif
