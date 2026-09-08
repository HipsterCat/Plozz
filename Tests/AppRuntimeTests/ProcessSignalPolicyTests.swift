import Darwin
import CrashReporting
import XCTest
@testable import AppRuntime

final class ProcessSignalPolicyTests: XCTestCase {
    // Signal dispositions are process-wide. Keep changes inside the synchronous
    // test and restore the runner's original disposition even when assertions fail.
    private func withBrokenPipeProtection(_ body: () throws -> Void) throws {
        var previous = sigaction()
        guard sigaction(SIGPIPE, nil, &previous) == 0 else {
            XCTFail("Could not read SIGPIPE disposition")
            return
        }
        defer { XCTAssertEqual(sigaction(SIGPIPE, &previous, nil), 0) }

        // Start from the fatal default, even if the test runner already ignores it.
        var initial = sigaction()
        initial.__sigaction_u.__sa_handler = SIG_DFL
        sigemptyset(&initial.sa_mask)
        XCTAssertEqual(sigaction(SIGPIPE, &initial, nil), 0)
        XCTAssertTrue(ProcessSignalPolicy.ignoreBrokenPipe())
        guard isBrokenPipeIgnored() else { return }
        try body()
    }

    private func isBrokenPipeIgnored() -> Bool {
        var installed = sigaction()
        XCTAssertEqual(sigaction(SIGPIPE, nil, &installed), 0)
        // Darwin exposes the disposition as a C function pointer; compare its
        // representation before issuing a write that would otherwise kill XCTest.
        let ignored = unsafeBitCast(SIG_IGN, to: UInt.self)
        let actual = unsafeBitCast(installed.__sigaction_u.__sa_handler, to: UInt.self)
        guard actual == ignored else {
            XCTFail("SIGPIPE was not ignored")
            return false
        }
        return true
    }

    func testDisconnectedSocketWriteReturnsBrokenPipe() throws {
        try withBrokenPipeProtection {
            var sockets: [Int32] = [-1, -1]
            guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else {
                XCTFail("socketpair failed with errno \(errno)")
                return
            }
            defer { close(sockets[0]) }
            XCTAssertEqual(close(sockets[1]), 0)

            var byte: UInt8 = 1
            let result = send(sockets[0], &byte, 1, 0)
            let errorCode = errno
            XCTAssertEqual(result, -1)
            XCTAssertEqual(errorCode, EPIPE)
        }
    }

    func testDisconnectedPipeWriteReturnsBrokenPipe() throws {
        try withBrokenPipeProtection {
            var descriptors: [Int32] = [-1, -1]
            guard pipe(&descriptors) == 0 else {
                XCTFail("pipe failed with errno \(errno)")
                return
            }
            defer { close(descriptors[1]) }
            XCTAssertEqual(close(descriptors[0]), 0)

            var byte: UInt8 = 1
            let result = write(descriptors[1], &byte, 1)
            let errorCode = errno
            XCTAssertEqual(result, -1)
            XCTAssertEqual(errorCode, EPIPE)
        }
    }

    func testRepeatedInstallationLeavesOtherFatalSignalsUnchanged() throws {
        let signals = [SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP, SIGTERM]
        let previous = signals.map { signal in
            var action = sigaction()
            XCTAssertEqual(sigaction(signal, nil, &action), 0)
            return action
        }

        try withBrokenPipeProtection {
            XCTAssertTrue(ProcessSignalPolicy.ignoreBrokenPipe())
            for (signal, original) in zip(signals, previous) {
                var current = sigaction()
                XCTAssertEqual(sigaction(signal, nil, &current), 0)
                XCTAssertEqual(
                    unsafeBitCast(current.__sigaction_u.__sa_handler, to: UInt.self),
                    unsafeBitCast(original.__sigaction_u.__sa_handler, to: UInt.self),
                    "Changed handler for signal \(signal)"
                )
                XCTAssertEqual(current.sa_flags, original.sa_flags)
                XCTAssertEqual(current.sa_mask, original.sa_mask)
            }
        }
    }

    @MainActor
    func testProtectionSurvivesCrashReporterStartStopAndRestart() throws {
        try withBrokenPipeProtection {
            // Loopback-only DSN: this test must never upload to the real service.
            let reporter = SentryCrashReporter(dsn: "https://public@127.0.0.1:1/1")
            let context = CrashReportContext.make(
                bundleIdentifier: "com.thatcube.Plozz.tests",
                version: "1",
                build: "1",
                providers: [],
                environment: "test"
            )
            defer { reporter.stop() }

            for _ in 0..<2 {
                reporter.start(context: context)
                guard isBrokenPipeIgnored() else { return }
                XCTAssertEqual(raise(SIGPIPE), 0)

                reporter.stop()
                guard isBrokenPipeIgnored() else { return }
                XCTAssertEqual(raise(SIGPIPE), 0)
            }
        }
    }
}
