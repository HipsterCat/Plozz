import CoreModels
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Opt-in, task-scoped evidence; the provider's thrown errors and fallback behavior stay unchanged.
public enum HTTPResponseDiagnostics {
    public struct CapturedResult<Value: Sendable>: Sendable {
        public let result: Result<Value, Error>
        public let responses: [ResponseDecodingDiagnostic]
        public let paging: [LibraryPagingDiagnostic]
        public let transport: [ResponseTransportDiagnostic]
        public let http: [ResponseStatusDiagnostic]

        public var isCancelled: Bool {
            guard case .failure(let error) = result else { return false }
            let underlying = LibrarySourceFailure.underlying(error)
            return underlying is CancellationError || (underlying as? AppError) == .cancelled
        }
    }

    @TaskLocal private static var recorder: Recorder?
    @TaskLocal public static var route: ResponseDecodingDiagnostic.Route = .other

    public static func capture<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async -> CapturedResult<Value> {
        let recorder = Recorder()
        return await $recorder.withValue(recorder) {
            do {
                return CapturedResult(result: .success(try await operation()), responses: [], paging: [], transport: [], http: [])
            } catch {
                let evidence = recorder.snapshot()
                return CapturedResult(
                    result: .failure(error), responses: evidence.responses, paging: evidence.paging,
                    transport: evidence.transport, http: evidence.http
                )
            }
        }
    }

    public static func recordPagingFailure(_ diagnostic: LibraryPagingDiagnostic) {
        recorder?.append(diagnostic)
    }

    public static func recordHTTPFailure(status: Int) {
        guard !(200...299).contains(status) else { return }
        recorder?.append(ResponseStatusDiagnostic(route: route, httpStatus: status))
    }

    public static func recordTransportFailure(_ error: URLError) {
        guard error.code != .cancelled else { return }
        recorder?.append(ResponseTransportDiagnostic(route: route, urlErrorCode: error.errorCode))
    }

    public static func recordDecodeFailure(
        _ error: Error, data: Data, response: HTTPURLResponse
    ) {
        guard let recorder else { return }
        let payload: ResponseDecodingDiagnostic.Payload
        if data.isEmpty { payload = .empty }
        else if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            payload = json is [Any] ? .array : json is [String: Any] ? .object : .scalar
        } else { payload = .nonJSON }
        recorder.append(ResponseDecodingDiagnostic(
            route: route, httpStatus: response.statusCode, bytes: data.count,
            payload: payload, error: error
        ))
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [ResponseDecodingDiagnostic] = []
        private var paging: [LibraryPagingDiagnostic] = []
        private var transport: [ResponseTransportDiagnostic] = []
        private var http: [ResponseStatusDiagnostic] = []

        func append(_ response: ResponseDecodingDiagnostic) {
            lock.lock()
            defer { lock.unlock() }
            responses.append(response)
            if responses.count > 4 { responses.removeFirst() }
        }

        func append(_ diagnostic: LibraryPagingDiagnostic) {
            lock.lock()
            defer { lock.unlock() }
            paging.append(diagnostic)
            if paging.count > 4 { paging.removeFirst() }
        }

        func append(_ diagnostic: ResponseTransportDiagnostic) {
            lock.lock()
            defer { lock.unlock() }
            transport.append(diagnostic)
            if transport.count > 4 { transport.removeFirst() }
        }

        func snapshot() -> (
            responses: [ResponseDecodingDiagnostic], paging: [LibraryPagingDiagnostic],
            transport: [ResponseTransportDiagnostic], http: [ResponseStatusDiagnostic]
        ) {
            lock.lock()
            defer { lock.unlock() }
            return (responses, paging, transport, http)
        }

        func append(_ diagnostic: ResponseStatusDiagnostic) {
            lock.lock()
            defer { lock.unlock() }
            http.append(diagnostic)
            if http.count > 4 { http.removeFirst() }
        }
    }
}
