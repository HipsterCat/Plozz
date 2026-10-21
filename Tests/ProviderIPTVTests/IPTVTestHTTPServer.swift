import Foundation
import Network

actor IPTVTestHTTPServer {
    struct Response: Sendable {
        var data = Data()
        var file: URL?
        var status = 200
        var headers: [String: String] = [:]
        var cutoff: Int?
        var headerDelay: Duration = .zero
        var delay: Duration = .zero
        var range: Range<Int>?
        var chunkSize = 65_536
    }

    private let listener: NWListener
    private let respond: @Sendable (String) -> Response
    private let beforeBodyChunk: (@Sendable () async throws -> Void)?
    private var connections: [UUID: (NWConnection, Task<Void, Never>)] = [:]
    private var stopped = false
    private(set) var requestCount = 0
    private(set) var activeRequestCount = 0
    private(set) var peakActiveRequestCount = 0
    private(set) var bodyBytesSent = 0

    init(
        beforeBodyChunk: (@Sendable () async throws -> Void)? = nil,
        respond: @escaping @Sendable (String) -> Response
    ) throws {
        self.respond = respond
        self.beforeBodyChunk = beforeBodyChunk
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        let listener = listener
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    if let port = listener.port { continuation.resume(returning: port.rawValue) }
                    else { continuation.resume(throwing: URLError(.cannotConnectToHost)) }
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task {
                    guard let self else { connection.cancel(); return }
                    await self.accept(connection)
                }
            }
            listener.start(queue: DispatchQueue(label: "IPTVTestHTTPServer"))
        }
        return URL(string: "http://127.0.0.1:\(port)/")!
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        listener.newConnectionHandler = nil
        listener.cancel()
        for (connection, task) in connections.values {
            task.cancel()
            connection.cancel()
        }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped else { connection.cancel(); return }
        let id = UUID()
        connection.start(queue: DispatchQueue.global())
        let task = Task {
            await serve(connection, id: id)
            connections.removeValue(forKey: id)
            connection.cancel()
        }
        connections[id] = (connection, task)
    }

    private func cancelConnection(_ id: UUID) {
        connections[id]?.1.cancel()
        connections[id]?.0.cancel()
    }

    private func serve(_ connection: NWConnection, id: UUID) async {
        do {
            var request = Data()
            while true {
                let part: Data = try await withCheckedThrowingContinuation { continuation in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: data ?? Data()) }
                    }
                }
                guard !part.isEmpty, request.count < 32_768 else { throw URLError(.badServerResponse) }
                request.append(part)
                guard let separator = request.range(of: Data("\r\n\r\n".utf8)) else { continue }
                let head = String(decoding: request[..<separator.lowerBound], as: UTF8.self)
                let lengthField = head.components(separatedBy: "\r\n").first {
                    $0.lowercased().hasPrefix("content-length:")
                }
                let bodyLength: Int
                if let lengthField {
                    guard let length = Int(lengthField.dropFirst("content-length:".count)
                        .trimmingCharacters(in: .whitespaces)), length >= 0 else {
                        throw URLError(.badServerResponse)
                    }
                    bodyLength = length
                } else {
                    bodyLength = 0
                }
                guard bodyLength <= 32_768 - separator.upperBound else {
                    throw URLError(.badServerResponse)
                }
                // PROPFIND's XML can arrive after its headers; it is not a disconnect.
                if request.count >= separator.upperBound + bodyLength { break }
            }
            requestCount += 1
            activeRequestCount += 1
            peakActiveRequestCount = max(peakActiveRequestCount, activeRequestCount)
            defer { activeRequestCount -= 1 }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, _, _ in
                Task { await self?.cancelConnection(id) }
            }
            let text = String(decoding: request, as: UTF8.self)
            let response = respond(text)
            if response.headerDelay != .zero { try await Task.sleep(for: response.headerDelay) }
            let file = try response.file.map { try FileHandle(forReadingFrom: $0) }
            defer {
                do { try file?.close() }
                catch { print("IPTV test fixture file close failed") }
            }
            let count: Int
            if let url = response.file {
                count = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            } else { count = response.data.count }
            let range = response.range ?? 0..<count
            guard range.lowerBound >= 0, range.upperBound <= count else { throw URLError(.badServerResponse) }
            var fields = response.headers
            fields["Content-Length"] = String(range.count)
            fields["Connection"] = "close"
            let head = "HTTP/1.1 \(response.status) Fixture\r\n"
                + fields.map { "\($0): \($1)\r\n" }.joined() + "\r\n"
            try await send(Data(head.utf8), on: connection)
            if text.hasPrefix("HEAD ") { return }
            if let file { try file.seek(toOffset: UInt64(range.lowerBound)) }
            let limit = min(range.upperBound, range.lowerBound + (response.cutoff ?? range.count))
            var offset = range.lowerBound
            while offset < limit {
                try Task.checkCancellation()
                try await beforeBodyChunk?()
                if response.delay != .zero { try await Task.sleep(for: response.delay) }
                guard response.chunkSize > 0 else { throw URLError(.badServerResponse) }
                let end = min(limit, offset + response.chunkSize)
                let chunk: Data
                if let file { chunk = try file.read(upToCount: end - offset) ?? Data() }
                else { chunk = response.data.subdata(in: offset..<end) }
                guard !chunk.isEmpty else { throw URLError(.cannotDecodeContentData) }
                try await send(chunk, on: connection)
                offset += chunk.count
                bodyBytesSent += chunk.count
            }
        } catch {
            // URLSession deliberately closes authentication probes and cancelled test requests.
            print("IPTV test fixture transfer ended: \(type(of: error))")
        }
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }
}
