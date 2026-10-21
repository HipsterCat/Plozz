import CoreModels
import Foundation
import XCTest

final class SiloSetupDiagnosticTests: XCTestCase {
    func testConsentRevocationDedupeAndBounds() throws {
        let diagnostics = SiloSetupDiagnostics()
        let buffer = SiloDiagnosticBuffer()
        XCTAssertNil(diagnostics.begin())
        diagnostics.start { buffer.append($0) }
        let attempt = try XCTUnwrap(diagnostics.begin())
        let failure = SiloSetupDiagnostic(stage: .start, reason: .server, httpStatus: 502, response: .html)
        attempt(failure)
        attempt(failure)
        XCTAssertEqual(buffer.values, [failure])
        diagnostics.stop()
        attempt(.init(stage: .poll, reason: .network))
        diagnostics.start { buffer.append($0) }
        attempt(.init(stage: .profiles, reason: .network))
        XCTAssertEqual(buffer.values, [failure], "Old attempts cannot regain permission after opt-in")
        let current = try XCTUnwrap(diagnostics.begin())
        for status in 400...420 { current(.init(stage: .start, reason: .server, httpStatus: status)) }
        XCTAssertEqual(buffer.values.count, 11)
        XCTAssertNil(SiloSetupDiagnostic(stage: .start, reason: .server, httpStatus: Int.max).httpStatus)
    }
}

private final class SiloDiagnosticBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SiloSetupDiagnostic] = []
    var values: [SiloSetupDiagnostic] { lock.withLock { storage } }
    func append(_ value: SiloSetupDiagnostic) { lock.withLock { storage.append(value) } }
}
