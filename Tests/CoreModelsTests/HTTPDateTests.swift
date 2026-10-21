import CoreModels
import Foundation
import XCTest

final class HTTPDateTests: XCTestCase {
    func testRetryAfterAcceptsSecondsAndAllHTTPDateFormats() throws {
        let date = try XCTUnwrap(HTTPDate.parse("Sun, 06 Nov 1994 08:49:37 GMT"))
        XCTAssertEqual(HTTPDate.retryAfter("0", now: date), 0)
        XCTAssertEqual(HTTPDate.retryAfter(" 17 ", now: date), 17)
        for value in ["Sun, 06 Nov 1994 08:49:37 GMT", "Sunday, 06-Nov-94 08:49:37 GMT", "Sun Nov  6 08:49:37 1994"] {
            XCTAssertEqual(HTTPDate.retryAfter(value, now: date.addingTimeInterval(-60)), 60)
            XCTAssertEqual(HTTPDate.retryAfter(value, now: date.addingTimeInterval(60)), 0)
        }
    }

    func testMalformedAndUnrepresentableRetryAfterDoesNotBecomeAnImmediateRetry() {
        for value in [nil, "", " ", "-1", "+1", "1.5", "nan", "inf", "1e3", "tomorrow", String(repeating: "9", count: 400)] {
            XCTAssertNil(HTTPDate.retryAfter(value), value ?? "absent")
        }
    }
}
