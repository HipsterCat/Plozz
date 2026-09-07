#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor LiveTVSourceLoader {
    private static let playlistLimit = LiveTVPlaylistParser.maximumBytes
    private static let guideLimit = LiveTVXMLTVParser.maximumCompressedBytes
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1_024 * 1_024,
            diskCapacity: 0
        )
        session = URLSession(configuration: configuration)
    }

    public func loadPlaylist(from url: URL) async throws -> LiveTVPlaylistImport {
        let data = try await download(
            from: url,
            maximumBytes: Self.playlistLimit,
            tooLargeError: .responseTooLarge
        )
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try LiveTVPlaylistParser(baseURL: url).parse(data)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public func loadGuide(
        from url: URL,
        channels: [LiveTVPrototypeChannel],
        now: Date
    ) async throws -> LiveTVGuideImport {
        let data = try await download(
            from: url,
            maximumBytes: Self.guideLimit,
            tooLargeError: .guideTooLarge
        )
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            let parser = LiveTVXMLTVParser()
            if data.starts(with: [0x1f, 0x8b]) {
                return try parser.parse(gzipData: data, channels: channels, now: now)
            }
            return try parser.parseXML(data: data, channels: channels, now: now)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func download(
        from url: URL,
        maximumBytes: Int,
        tooLargeError: LiveTVSourceImportError
    ) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              url.user == nil,
              url.password == nil
        else {
            throw LiveTVSourceImportError.invalidResponse
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            request.setValue("gzip, identity", forHTTPHeaderField: "Accept-Encoding")
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode)
            else {
                throw LiveTVSourceImportError.invalidResponse
            }
            if response.expectedContentLength > Int64(maximumBytes) {
                throw tooLargeError
            }
            var data = Data()
            data.reserveCapacity(
                min(maximumBytes, max(0, Int(response.expectedContentLength)))
            )
            for try await byte in bytes {
                if Task.isCancelled {
                    throw LiveTVSourceImportError.cancelled
                }
                guard data.count < maximumBytes else {
                    throw tooLargeError
                }
                data.append(byte)
            }
            return data
        } catch is CancellationError {
            throw LiveTVSourceImportError.cancelled
        } catch let error as LiveTVSourceImportError {
            throw error
        } catch {
            throw LiveTVSourceImportError.downloadFailed
        }
    }
}
#endif
