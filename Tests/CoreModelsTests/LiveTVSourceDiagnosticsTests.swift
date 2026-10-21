import Foundation
import XCTest
@testable import CoreModels

final class LiveTVSourceDiagnosticsTests: XCTestCase {
    func testReleaseEvidenceSurvivesRestartWithoutDebugTelemetryOrSecrets() throws {
        let url = try journalURL()
        let recorder = LiveTVSourceDiagnostics(url: url)
        let previous = HandoffDiagnostics.isEnabled
        HandoffDiagnostics.setEnabled(false)
        defer { HandoffDiagnostics.setEnabled(previous) }
        let configuration = LiveTVSourcesConfiguration(
            playlists: [.init(
                id: "private-source-id", name: "Private playlist title",
                playlistURL: try XCTUnwrap(URL(string: "https://private.test/list?token=secret"))
            )],
            servers: [.init(id: "private-server-id", name: "Private server", accountID: "private-account")]
        )
        recorder.configuration(configuration, namespace: "private-profile")
        recorder.record(
            .enrollmentDecision, identities: [.account: "private-account", .profile: "private-profile"],
            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                           userInfo: [NSLocalizedDescriptionKey: "private error https://private.test?token=secret"])
        )
        let first = recorder.report()
        let reopened = LiveTVSourceDiagnostics(url: url)
        let second = reopened.report()
        for text in [first, second] {
            for secret in ["private-source", "Private playlist", "private.test", "secret", "private-profile",
                           "private-account", "Private server", "private error"] {
                XCTAssertFalse(text.contains(secret), secret)
            }
            let journal = try decode(text)
            XCTAssertEqual(journal.entries.count, 2)
            XCTAssertEqual(journal.entries.last?.payload.reason, .timeout)
            XCTAssertEqual(journal.entries.last?.payload.errorCode, NSURLErrorTimedOut)
            XCTAssertEqual(
                journal.entries.first?.payload.sources.last?.account,
                journal.entries.last?.payload.identities[.account]
            )
        }
        XCTAssertEqual(try decode(first).entries.first?.launch, try decode(second).entries.first?.launch)
    }

    func testDeduplicationPreservesMissingFailureRecoveryAndRepeatedLoss() throws {
        let recorder = LiveTVSourceDiagnostics(url: try journalURL())
        for _ in 0..<20 {
            recorder.record(.sourceMissing, identities: [.namespace: "default"], deduplicate: true)
        }
        recorder.configuration(.empty, namespace: nil, event: .sourceSave)
        recorder.record(.sourceMissing, identities: [.namespace: "default"], deduplicate: true)
        recorder.configuration(.empty, namespace: nil)
        recorder.record(.sourceReadFailed, identities: [.namespace: "default"], reason: .storage, deduplicate: true)
        recorder.configuration(.empty, namespace: nil)
        XCTAssertEqual(try decode(recorder.report()).entries.map(\.payload.event), [
            .sourceMissing, .sourceSave, .sourceMissing, .sourceRead, .sourceReadFailed, .sourceRead
        ])
    }

    func testEntryAndByteLimitsExposeDiscardedEvidenceAndKeepNewestState() throws {
        let url = try journalURL()
        let recorder = LiveTVSourceDiagnostics(url: url)
        let configuration = LiveTVSourcesConfiguration(servers: (0..<70).map {
            .init(id: "source-\($0)", name: "Private \($0)", accountID: "account-\($0)")
        })
        for _ in 0..<600 { recorder.configuration(configuration, namespace: nil, event: .sourceSave) }
        recorder.record(.reportRequested)
        let journal = try decode(recorder.report())
        XCTAssertLessThanOrEqual(try Data(contentsOf: url).count, LiveTVSourceDiagnostics.maximumBytes)
        XCTAssertLessThanOrEqual(journal.entries.count, LiveTVSourceDiagnostics.maximumEntries)
        XCTAssertGreaterThan(journal.discarded, 0)
        XCTAssertEqual(journal.entries.last?.payload.event, .reportRequested)
        let snapshot = try XCTUnwrap(journal.entries.first { $0.payload.event == .sourceSave })
        XCTAssertEqual(snapshot.payload.counts[.servers], 70)
        XCTAssertEqual(snapshot.payload.counts[.omittedSources], 6)
        XCTAssertEqual(snapshot.payload.sources.count, 64)
    }

    func testExpiredEvidenceIsNotExportedAfterRestart() throws {
        let url = try journalURL()
        let then = Date(timeIntervalSince1970: 1_000_000)
        let recorder = LiveTVSourceDiagnostics(url: url, clock: { then })
        recorder.record(.sourceMissing)
        _ = recorder.report()
        let now = then.addingTimeInterval(LiveTVSourceDiagnostics.retention + 1)
        let reopened = LiveTVSourceDiagnostics(url: url, clock: { now })
        let journal = try decode(reopened.report())
        XCTAssertTrue(journal.entries.isEmpty)
        XCTAssertEqual(journal.discarded, 1)
    }

    func testExportIsBoundedEvenWhenNoStorageLocationIsAvailable() throws {
        let recorder = LiveTVSourceDiagnostics(url: nil)
        let configuration = LiveTVSourcesConfiguration(servers: (0..<64).map {
            .init(id: "source-\($0)", name: "Private \($0)", accountID: "account-\($0)")
        })
        for _ in 0..<100 { recorder.configuration(configuration, namespace: nil, event: .sourceSave) }
        let report = recorder.report()
        XCTAssertTrue(report.hasPrefix("storage=locationUnavailable"))
        let json = try XCTUnwrap(report.split(separator: "\n", maxSplits: 1).last)
        XCTAssertLessThanOrEqual(json.utf8.count, LiveTVSourceDiagnostics.maximumBytes)
        XCTAssertGreaterThan(try decode(report).discarded, 0)
    }

    func testOversizedOrUntrustedJournalIsRejectedRatherThanExported() throws {
        let url = try journalURL()
        try Data(repeating: 65, count: LiveTVSourceDiagnostics.maximumBytes + 1).write(to: url)
        let oversized = LiveTVSourceDiagnostics(url: url).report()
        XCTAssertTrue(oversized.hasPrefix("storage=oversized"))
        XCTAssertTrue(try decode(oversized).entries.isEmpty)

        let payload = LiveTVSourceDiagnostics.Payload(
            event: .sourceRead, identities: [.account: "private unsafe identity"], counts: [:],
            flags: [:], reason: nil, stage: nil, errorCode: nil, sources: []
        )
        let entry = LiveTVSourceDiagnostics.Entry(
            timestamp: Date(), launch: UUID(), sequence: 1, build: "57", payload: payload
        )
        try JSONEncoder().encode(LiveTVSourceDiagnostics.Journal(entries: [entry])).write(to: url)
        let invalid = LiveTVSourceDiagnostics(url: url).report()
        XCTAssertTrue(invalid.hasPrefix("storage=invalidJournal"))
        XCTAssertFalse(invalid.contains("private unsafe identity"))
        XCTAssertTrue(try decode(invalid).entries.isEmpty)
    }

    func testCorruptAndUnwritableStorageAreExplicitWithoutLeakingFileContents() throws {
        let url = try journalURL()
        try Data("private corrupted data".utf8).write(to: url)
        let recorder = LiveTVSourceDiagnostics(url: url)
        recorder.record(.reportRequested)
        let text = recorder.report()
        XCTAssertTrue(text.hasPrefix("storage=readFailed"))
        XCTAssertFalse(text.contains("private corrupted data"))
        XCTAssertEqual(try decode(text).entries.count, 1)

        let blocked = url.appendingPathComponent("not-a-directory.json")
        let unavailable = LiveTVSourceDiagnostics(url: blocked)
        unavailable.record(.sourceMissing)
        let failure = unavailable.report()
        XCTAssertTrue(failure.hasPrefix("storage=writeFailed"))
        XCTAssertEqual(try decode(failure).entries.first?.payload.event, .sourceMissing)
    }

    private func journalURL() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("source-diagnostics-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("journal.json")
    }

    private func decode(_ text: String) throws -> LiveTVSourceDiagnostics.Journal {
        let data = Data(try XCTUnwrap(text.split(separator: "\n", maxSplits: 1).last).utf8)
        return try JSONDecoder().decode(LiveTVSourceDiagnostics.Journal.self, from: data)
    }
}
