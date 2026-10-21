import Foundation
import Network

/// A real loopback-only HTTP listener for exercising URLSession, not URLProtocol.
actor LoopbackHTTPServer {
    struct Request: Sendable {
        let method: String
        let target: String
        let headers: [String: String]
        let body: Data
    }

    struct Response: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var delay: Duration = .zero
        var disconnect = false

        static func json(_ value: String, status: Int = 200) -> Self {
            .init(status: status, headers: ["Content-Type": "application/json"], body: Data(value.utf8))
        }
    }

    private let listener: NWListener
    private let respond: @Sendable (Request) async -> Response
    private var startup: CheckedContinuation<URL, Error>?
    private var startupTimeout: Task<Void, Never>?
    private var connections: [UUID: (NWConnection, Task<Void, Never>)] = [:]
    private var stopped = false
    private(set) var requests: [Request] = []

    init(respond: @escaping @Sendable (Request) async -> Response) throws {
        self.respond = respond
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            startup = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { await self?.stateChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task {
                    guard let self else { connection.cancel(); return }
                    await self.accept(connection)
                }
            }
            startupTimeout = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(3))
                    await self?.failStartup(URLError(.timedOut))
                } catch is CancellationError {
                } catch {
                    await self?.failStartup(error)
                }
            }
            listener.start(queue: DispatchQueue(label: "LoopbackHTTPServer"))
        }
    }

    private func stateChanged(_ state: NWListener.State) {
        guard let startup else { return }
        switch state {
        case .ready:
            guard let port = listener.port,
                  let url = URL(string: "http://127.0.0.1:\(port.rawValue)") else {
                failStartup(URLError(.cannotConnectToHost))
                return
            }
            self.startup = nil
            startupTimeout?.cancel()
            startup.resume(returning: url)
        case .failed(let error): failStartup(error)
        case .cancelled: failStartup(CancellationError())
        default: break
        }
    }

    private func failStartup(_ error: Error) {
        let pending = startup
        startup = nil
        startupTimeout?.cancel()
        pending?.resume(throwing: error)
        stop()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        let pending = startup
        startup = nil
        pending?.resume(throwing: CancellationError())
        startupTimeout?.cancel()
        listener.newConnectionHandler = nil
        listener.stateUpdateHandler = nil
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
            defer {
                connections[id] = nil
                connection.cancel()
            }
            do {
                let request = try await readRequest(connection)
                requests.append(request)
                let response = await respond(request)
                if response.delay != .zero { try await Task.sleep(for: response.delay) }
                try Task.checkCancellation()
                guard !response.disconnect else { return }
                var headers = response.headers
                headers["Content-Length"] = String(response.body.count)
                headers["Connection"] = "close"
                let head = "HTTP/1.1 \(response.status) Fixture\r\n"
                    + headers.map { "\($0): \($1)\r\n" }.joined() + "\r\n"
                let bytes = Data(head.utf8) + (request.method == "HEAD" ? Data() : response.body)
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    connection.send(content: bytes, completion: .contentProcessed { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    })
                }
            } catch {
                if !Task.isCancelled { print("Loopback fixture connection ended: \(type(of: error))") }
            }
        }
        connections[id] = (connection, task)
    }

    private func readRequest(_ connection: NWConnection) async throws -> Request {
        let separator = Data("\r\n\r\n".utf8)
        var bytes = Data()
        while bytes.range(of: separator) == nil {
            guard bytes.count < 65_536 else { throw URLError(.dataLengthExceedsMaximum) }
            bytes += try await receive(connection)
        }
        guard let boundary = bytes.range(of: separator) else { throw URLError(.badServerResponse) }
        let lines = String(decoding: bytes[..<boundary.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count == 3 else { throw URLError(.badServerResponse) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { throw URLError(.badServerResponse) }
            headers[String(parts[0]).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        let count = headers["content-length"].flatMap(Int.init) ?? 0
        guard (0...1_048_576).contains(count) else { throw URLError(.dataLengthExceedsMaximum) }
        var body = Data(bytes[boundary.upperBound...])
        while body.count < count { body += try await receive(connection) }
        return Request(method: String(first[0]), target: String(first[1]), headers: headers,
                       body: Data(body.prefix(count)))
    }

    private func receive(_ connection: NWConnection) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: URLError(.networkConnectionLost)) }
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }
}
