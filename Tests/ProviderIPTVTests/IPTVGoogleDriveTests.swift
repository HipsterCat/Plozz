import CoreModels
import CoreNetworking
import FeatureLiveTVCore
import Foundation
@testable import ProviderIPTV
import XCTest

final class IPTVGoogleDriveTests: XCTestCase {
    override func tearDown() {
        IPTVFixture.state.reset()
        super.tearDown()
    }

    func testDriveShareImportAuthenticationAndRefreshUseDownloadWithoutForwardingHeaders() async throws {
        let address = try XCTUnwrap(URL(string: "https://drive.google.com/file/d/fixture_ID/view?usp=sharing"))
        let download = try XCTUnwrap(URL(string: "https://drive.usercontent.google.com/download?id=fixture_ID&export=download"))
        let data = Data("""
        #EXTM3U
        #EXT-X-CREDENTIALS:ignored
        #EXT-X-SESSION-DATA:DATA-ID="fixture"
        #EXTINF:-1,News
        https://media.test/news.ts
        """.utf8)
        IPTVFixture.state.handler = { request in
            XCTAssertEqual(request.url, download)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Account"))
            return (200, ["Content-Type": "application/octet-stream"], data)
        }
        let root = temporaryDirectory()
        let credential = try IPTVCredential(
            mode: .playlist, address: address,
            headers: ["Authorization": "Bearer fixture", "Cookie": "session=fixture", "X-Account": "fixture"]
        )
        let session = try await IPTVProvider.signIn(
            credential: credential, name: "Drive", deviceID: "fixture",
            cacheDirectory: root, configuration: IPTVFixture.configuration()
        )
        XCTAssertEqual(credential.address, address)
        let client = try IPTVClient(credential: credential, directory: root, configuration: IPTVFixture.configuration())
        try await client.authenticate()
        try await client.ensureCatalog("live", force: true)
        let provider = try makeProvider(session: session, root: root, configuration: IPTVFixture.configuration())
        let channels = try await provider.liveTVChannels()
        await provider.teardown()
        await client.cancel()
        XCTAssertEqual(channels.map(\.name), ["News"])
        XCTAssertEqual(IPTVFixture.state.requests.count, 3)
    }

    func testDriveHTMLAndAccessFailuresAreNotRetriedOrImported() async throws {
        let address = try XCTUnwrap(URL(string: "https://drive.google.com/open?id=fixture"))
        for status in [200, 403, 404, 429] {
            IPTVFixture.state.reset()
            IPTVFixture.state.handler = { _ in
                (status, ["Content-Type": "text/html"], Data("""
                <!doctype html><html>Sign in, download quota, or scan confirmation required.
                <a href="https://drive.usercontent.google.com/download?id=fixture&confirm=t">Download</a></html>
                """.utf8))
            }
            do {
                _ = try await IPTVProvider.signIn(
                    credential: IPTVCredential(mode: .playlist, address: address), name: "Drive",
                    deviceID: "fixture", cacheDirectory: temporaryDirectory(),
                    configuration: IPTVFixture.configuration()
                )
                XCTFail("HTML and HTTP refusals must not create a playlist account.")
            } catch {
                XCTAssertEqual(IPTVFixture.state.requests.count, 1)
            }
        }
    }

    func testOptInCapturedDriveFilesAndLiveURLsImportTheSameChannels() async throws {
        let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/iptv-drive-corpus")
        let manifest = corpus.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw XCTSkip("Opt in with .build/iptv-drive-corpus/manifest.json; fetches playlists only, never streams.")
        }
        struct Sample: Decodable {
            let name: String
            let url: URL
            let file: String
        }
        let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: manifest))
        XCTAssertFalse(samples.isEmpty)
        for sample in samples {
            let file = corpus.appendingPathComponent(sample.file)
            let parsed = try M3UPlaylistParser().parse(Data(contentsOf: file))
            XCTAssertFalse(parsed.channels.isEmpty, sample.name)
            let expectedNames = Set(parsed.channels.map(\.name))
            let root = temporaryDirectory()
            let fileCredential = try IPTVCredential(
                mode: .file, address: XCTUnwrap(URL(string: "https://imported-playlist.invalid"))
            )
            let fileSession = try await IPTVProvider.importFile(
                file, credential: fileCredential, name: "Drive", deviceID: "fixture", cacheDirectory: root
            )
            let fileProvider = try makeProvider(session: fileSession, root: root)
            let fileChannels = try await fileProvider.liveTVChannels()
            await fileProvider.teardown()
            XCTAssertEqual(Set(fileChannels.map(\.name)), expectedNames, sample.name)

            let credential = try IPTVCredential(mode: .playlist, address: sample.url)
            let session = try await IPTVProvider.signIn(
                credential: credential, name: "Drive", deviceID: "fixture", cacheDirectory: root
            )
            let provider = try makeProvider(session: session, root: root)
            let channels = try await provider.liveTVChannels()
            await provider.teardown()
            XCTAssertEqual(Set(channels.map(\.name)), expectedNames, sample.name)
            XCTAssertEqual(channels.count, fileChannels.count, sample.name)

            let standalone = try await LiveTVSourceLoader().loadPlaylist(from: sample.url)
            XCTAssertEqual(Set(standalone.channels.map(\.name)), expectedNames, sample.name)
            XCTAssertEqual(standalone.entryCount, parsed.entryCount, sample.name)
            print("IPTV_DRIVE sample=\(sample.name) entries=\(parsed.entryCount) file=\(fileChannels.count) account=\(channels.count) standalone=\(standalone.channels.count)")
        }
    }

    private func makeProvider(
        session: UserSession, root: URL, configuration: URLSessionConfiguration? = nil
    ) throws -> IPTVProvider {
        try IPTVProvider(
            context: .init(session: session, accountID: "drive", credentialRevision: .init(),
                           localMediaContext: .init(accountID: "drive", profileID: "fixture", profileNamespace: nil)),
            cacheDirectory: root, configuration: configuration
        )
    }

    private func temporaryDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        }
        return root
    }
}
