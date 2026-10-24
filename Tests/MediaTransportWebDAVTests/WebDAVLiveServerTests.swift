import Foundation
@testable import MediaTransportHTTP
@testable import MediaTransportWebDAV
import XCTest

/// Opt-in real-network coverage. Supply PLOZZ_WEBDAV_LIVE_CONFIG as JSON in
/// the test scheme's environment; never commit credentials or demo URLs.
final class WebDAVLiveServerTests: XCTestCase {
    private struct Target: Decodable {
        let name: String
        let url: URL
        let username: String
        let password: String
        let expectedStatus: Int?
        let digestOnly: Bool?

        var credential: WebDAVCredential {
            username.isEmpty ? .anonymous : .password(
                username: username, password: password,
                policy: digestOnly == true ? .digestOnly : .basicAllowed
            )
        }
    }

    private struct Configuration: Decodable {
        let local: Target
        let additionalOwnedTargets: [Target]?
        let files: [String]
        let size: Int64
        let prefix: Data
        let publicTargets: [Target]
    }

    private func configuration() throws -> Configuration {
        guard let json = ProcessInfo.processInfo.environment["PLOZZ_WEBDAV_LIVE_CONFIG"] else {
            throw XCTSkip("Live WebDAV servers were not configured")
        }
        return try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
    }

    private func rootAndKey(_ target: Target) throws -> (WebDAVRoot, TransportSessionKey) {
        let origin = try XCTUnwrap(TransportOrigin(url: target.url))
        let path = try XCTUnwrap(URLComponents(url: target.url, resolvingAgainstBaseURL: true)).percentEncodedPath
        let root = try XCTUnwrap(WebDAVRoot(origin: origin, rawPath: path))
        let key = try TransportSessionKey(
            accountID: "live-fixture", credentialRevision: UUID(), origin: origin,
            trustRevision: UUID(), role: .scanner
        )
        return (root, key)
    }

    func testOwnedServerEncodingRecursionAndValidatedMediaRanges() async throws {
        let config = try configuration()
        XCTAssertEqual(config.prefix.count, 1024)
        for target in [config.local] + (config.additionalOwnedTargets ?? []) {
            do {
                try await verifyOwnedServer(target, configuration: config)
            } catch {
                XCTFail("\(target.name): \(error)")
            }
        }
    }

    private func verifyOwnedServer(_ target: Target, configuration config: Configuration) async throws {
        let (root, key) = try rootAndKey(target)
        let registry = TransportSessionRegistry()
        let client = WebDAVClient(registry: registry)
        do {
            try await client.validateCollection(
                root: root, sessionKey: key, credential: target.credential, trustPolicy: .system
            )
            var pending = [root.path]
            var visited: Set<String> = []
            var files: [WebDAVEntry] = []
            while let path = pending.popLast() {
                guard visited.insert(path).inserted else {
                    XCTFail("\(target.name): directory repeated")
                    break
                }
                guard visited.count <= 16 else {
                    XCTFail("\(target.name): directory traversal exceeded its fixture bound")
                    break
                }
                let children = try await client.listChildren(
                    root: root, path: path, depth: .one,
                    sessionKey: key, credential: target.credential, trustPolicy: .system
                )
                for entry in children {
                    XCTAssertFalse(
                        WebDAVPathPolicy.isSelfEntry(resolvedPath: entry.resolvedPath, requestPath: path),
                        target.name
                    )
                    if entry.isCollection {
                        pending.append(entry.resolvedPath)
                    } else {
                        files.append(entry)
                    }
                }
            }
            XCTAssertEqual(visited.count, 5, "\(target.name): root plus four nested collections")
            XCTAssertEqual(
                Set(files.map(\.resolvedPath)),
                Set(config.files.map { root.path + $0 }),
                target.name
            )
            for entry in files {
                XCTAssertEqual(entry.contentLength, config.size, target.name)
                let url = try XCTUnwrap(root.origin.url(path: entry.resolvedPath))
                let representation = try await client.probeRange(
                    root: root, url: url, sessionKey: key,
                    credential: target.credential, trustPolicy: .system
                )
                XCTAssertEqual(representation.totalLength, config.size, target.name)
                for _ in 0..<2 {
                    let bytes = try await client.readRange(
                        url: representation.resourceURL, start: 0, end: 1023,
                        representation: representation, sessionKey: key,
                        credential: target.credential, trustPolicy: .system
                    )
                    XCTAssertEqual(bytes, config.prefix, target.name)
                }
            }
            print("WEBDAV_LIVE \(target.name): checked \(visited.count) collections, \(files.count) files, repeated exact-byte ranges")
            await registry.drainAll()
        } catch {
            await registry.drainAll()
            throw error
        }
    }

    func testConfiguredPublicServersReadOnly() async throws {
        let config = try configuration()
        for target in config.publicTargets {
            let (root, key) = try rootAndKey(target)
            let registry = TransportSessionRegistry()
            let client = WebDAVClient(registry: registry)
            do {
                try await client.validateCollection(
                    root: root, sessionKey: key, credential: target.credential, trustPolicy: .system
                )
                XCTAssertEqual(target.expectedStatus, 207, target.name)
                let entries = try await client.listChildren(
                    root: root, path: root.path, depth: .one,
                    sessionKey: key, credential: target.credential, trustPolicy: .system
                )
                XCTAssertFalse(entries.contains {
                    WebDAVPathPolicy.isSelfEntry(resolvedPath: $0.resolvedPath, requestPath: root.path)
                })
                print("WEBDAV_LIVE \(target.name): collection validated, \(entries.count) children")
                if let file = entries.first(where: { !$0.isCollection && ($0.contentLength ?? 0) >= 1024 }) {
                    let url = try XCTUnwrap(root.origin.url(path: file.resolvedPath))
                    let representation = try await client.probeRange(
                        root: root, url: url, sessionKey: key,
                        credential: target.credential, trustPolicy: .system
                    )
                    let bytes = try await client.readRange(
                        url: representation.resourceURL, start: 0, end: 1023,
                        representation: representation, sessionKey: key,
                        credential: target.credential, trustPolicy: .system
                    )
                    XCTAssertEqual(bytes.count, 1024)
                    print("WEBDAV_LIVE \(target.name): validated 206 range, 1024 bytes")
                } else {
                    print("WEBDAV_LIVE \(target.name): range not exercised; no suitable root file")
                }
            } catch {
                switch (target.expectedStatus, error as? TransportError) {
                case (401, .authenticationFailed):
                    print("WEBDAV_LIVE \(target.name): supplied credentials rejected, correctly surfaced")
                case (404, .protocolError(status: 404, detail: _)):
                    print("WEBDAV_LIVE \(target.name): missing endpoint correctly surfaced")
                default:
                    XCTFail("\(target.name): \(error)")
                }
            }
            await registry.drainAll()
        }
    }
}
