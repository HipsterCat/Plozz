import CoreModels
import CoreNetworking
import Foundation
@testable import ProviderIPTV
import XCTest

final class IPTVSetupDiagnosticsTests: XCTestCase {
    override func tearDown() {
        IPTVFixture.state.reset()
        super.tearDown()
    }

    func testHTTPAndLoginPageFailuresRetainStatusWithoutAdditionalRequests() async throws {
        for status in [200, 401, 403, 404, 429, 503] {
            IPTVFixture.state.reset()
            IPTVFixture.state.handler = { _ in
                (status, ["Content-Type": "text/html"], Data("<html>Private login</html>".utf8))
            }
            let buffer = ProviderSetupBuffer()
            let diagnostics = IPTVSetupDiagnostics()
            diagnostics.start { buffer.append($0) }
            let attempt = try XCTUnwrap(diagnostics.begin(source: .playlistURL, authentication: .bearer, entry: .addAccount))
            let credential = try IPTVCredential(
                mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test/list?token=private")),
                headers: ["Authorization": "Bearer private"]
            )
            await IPTVSetupDiagnostics.$current.withValue(attempt) {
                do {
                    _ = try await IPTVProvider.signIn(
                        credential: credential, name: "Private account", deviceID: "Private device",
                        cacheDirectory: temporaryDirectory(), configuration: IPTVFixture.configuration()
                    )
                    XCTFail("Must reject the HTTP error or login page")
                } catch {
                    attempt.finish((error as? IPTVError)?.setupFailure ?? .sanitized(error))
                }
            }
            let failure = try XCTUnwrap(buffer.values.last)
            XCTAssertEqual(failure.stage, .playlist)
            XCTAssertEqual(failure.outcome, .failed)
            XCTAssertEqual(failure.httpStatus, status)
            XCTAssertEqual(failure.response, .html)
            XCTAssertEqual(failure.requestCount, 1)
            XCTAssertEqual(IPTVFixture.state.requests.count, 1)
            XCTAssertLessThanOrEqual(buffer.values.count, 4)
        }
    }

    func testNetworkFailureKeepsNumericCodeWithoutAnErrorDescription() async throws {
        IPTVFixture.state.handler = { _ in throw URLError(.timedOut, userInfo: [
            NSURLErrorFailingURLErrorKey: URL(string: "https://private.test/secret")!,
            NSLocalizedDescriptionKey: "Private hostname"
        ]) }
        let buffer = ProviderSetupBuffer()
        let diagnostics = IPTVSetupDiagnostics()
        diagnostics.start { buffer.append($0) }
        let attempt = try XCTUnwrap(diagnostics.begin(source: .xtream, authentication: .xtream, entry: .addAccount))
        let credential = try IPTVCredential(
            mode: .xtream, address: XCTUnwrap(URL(string: "https://provider.test")),
            username: "private", password: "private"
        )
        await IPTVSetupDiagnostics.$current.withValue(attempt) {
            do {
                _ = try await IPTVProvider.signIn(
                    credential: credential, name: "Private", deviceID: "Private",
                    cacheDirectory: temporaryDirectory(), configuration: IPTVFixture.configuration()
                )
                XCTFail("Timed-out authentication must fail")
            } catch { attempt.finish(.sanitized(error)) }
        }
        XCTAssertEqual(buffer.values.last?.failure, .init(.timeout, networkCode: -1001))
        XCTAssertNil(buffer.values.last?.httpStatus)
        XCTAssertEqual(IPTVFixture.state.requests.count, 1)
    }

    func testExtensionlessDownloadURLImportsMetadataPlaylistWithoutFetchingItsStreams() async throws {
        let driveAddress = try XCTUnwrap(URL(string: "https://drive.google.com/uc?export=download&id=fixture&confirm=true"))
        XCTAssertEqual(try IPTVCredential(mode: .playlist, address: driveAddress).address, driveAddress)
        let address = try XCTUnwrap(URL(string: "https://provider.test/uc?export=download&id=fixture&confirm=true"))
        let data = Data("""
        #EXTM3U
        #EXT-X-SESSION-DATA:DATA-ID="com.xui.1_5_5r2"
        #EXTINF:-1,News
        https://provider.test/one.ts
        #EXTINF:-1,Local
        https://provider.test/two.m3u8
        """.utf8)
        IPTVFixture.state.handler = { request in
            XCTAssertEqual(request.url, address)
            return (200, ["Content-Type": "application/octet-stream"], data)
        }
        let root = temporaryDirectory()
        let buffer = ProviderSetupBuffer()
        let diagnostics = IPTVSetupDiagnostics()
        diagnostics.start { buffer.append($0) }
        let attempt = try XCTUnwrap(diagnostics.begin(source: .playlistURL, authentication: .none, entry: .addAccount))
        let credential = try IPTVCredential(mode: .playlist, address: address)
        let session = try await IPTVSetupDiagnostics.$current.withValue(attempt) {
            try await IPTVProvider.signIn(
                credential: credential, name: "Fixture", deviceID: "fixture",
                cacheDirectory: root, configuration: IPTVFixture.configuration()
            )
        }
        attempt.finish()
        let provider = try IPTVProvider(
            context: .init(session: session, accountID: "account", credentialRevision: .init(),
                           localMediaContext: .init(accountID: "account", profileID: "fixture", profileNamespace: nil)),
            cacheDirectory: root, configuration: IPTVFixture.configuration()
        )
        addTeardownBlock { await provider.teardown() }
        let channels = try await provider.liveTVChannels()
        XCTAssertEqual(Set(channels.map(\.name)), ["News", "Local"])
        XCTAssertEqual(buffer.values.last?.outcome, .succeeded)
        XCTAssertEqual(buffer.values.last?.httpStatus, 200)
        XCTAssertEqual(buffer.values.last?.entries, 2)
        XCTAssertEqual(buffer.values.last?.playlistBytes, data.count)
        XCTAssertEqual(buffer.values.last?.requestCount, 1)
        XCTAssertEqual(IPTVFixture.state.requests.count, 1)
    }

    func testFileImportReportsCountsWithNoPerEntryMarkersAndNoNetworkRequests() async throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("private-name.m3u")
        var data = Data(("#EXTM3U\n#EXT-X-SESSION-DATA:DATA-ID=\"com.xui.1_5_5r2\"\n" + (0..<10_000).map {
            "#EXTINF:-1,Private \($0)\nhttps://provider.test/live/\($0).ts\n"
        }.joined()).utf8)
        let reportedByteCount = 6_185_484
        while data.count < reportedByteCount {
            let count = min(4_096, reportedByteCount - data.count)
            data.append(Data(("#" + String(repeating: "x", count: count - 2) + "\n").utf8))
        }
        XCTAssertEqual(data.count, reportedByteCount)
        try data.write(to: file)
        let buffer = ProviderSetupBuffer()
        let diagnostics = IPTVSetupDiagnostics()
        diagnostics.start { buffer.append($0) }
        let attempt = try XCTUnwrap(diagnostics.begin(source: .playlistFile, authentication: .none, entry: .addAccount))
        let credential = try IPTVCredential(mode: .file, address: XCTUnwrap(URL(string: "https://imported-playlist.invalid")))
        _ = try await IPTVSetupDiagnostics.$current.withValue(attempt) {
            try await IPTVProvider.importFile(
                file, credential: credential, name: "Private", deviceID: "Private",
                cacheDirectory: root.appendingPathComponent("catalog")
            )
        }
        attempt.finish()
        XCTAssertEqual(buffer.values.last?.outcome, .succeeded)
        XCTAssertEqual(buffer.values.last?.entries, 10_000)
        XCTAssertEqual(buffer.values.last?.playlistBytes, data.count)
        XCTAssertEqual(buffer.values.last?.requestCount, 0)
        XCTAssertTrue(IPTVFixture.state.requests.isEmpty)
        XCTAssertEqual(buffer.values.count, 6)
    }

    private func temporaryDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        }
        return root
    }
}

private final class ProviderSetupBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [IPTVSetupDiagnostic] = []
    var values: [IPTVSetupDiagnostic] { lock.withLock { storage } }
    func append(_ value: IPTVSetupDiagnostic) { lock.withLock { storage.append(value) } }
}
