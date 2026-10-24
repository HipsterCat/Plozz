import CoreModels
import Foundation

/// Failure-only evidence for the version gate, carried by the existing recent-activity sender.
public enum PlaybackPreparationDiagnostics {
    public enum Operation: String, Sendable {
        case versions, alternateVersions, detailVersions, episodeVersions
    }

    public static func capture<Value: Sendable>(
        provider: ProviderKind, operation: Operation,
        _ work: @Sendable () async throws -> Value
    ) async throws -> Value {
        let started = ProcessInfo.processInfo.systemUptime
        let captured = await HTTPResponseDiagnostics.capture(work)
        if case .failure(let error) = captured.result, !captured.isCancelled, !Task.isCancelled {
            let text = supportText(
                provider: provider, operation: operation, error: error, captured: captured,
                elapsedMilliseconds: Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            )
            PlozzLog.playback.error(text)
            HandoffDiagnostics.emit(text)
        }
        return try captured.result.get()
    }

    public static func identityFailure(
        provider: ProviderKind, operation: Operation,
        expectedID: String, expectedKind: MediaItemKind, expectedAccountID: String?, resolved: MediaItem
    ) {
        let reason: ResponseValidationDiagnostic.Reason
        if resolved.id != expectedID { reason = .itemIDMismatch }
        else if resolved.kind != expectedKind { reason = .itemKindMismatch }
        else if let accountID = resolved.sourceAccountID, accountID != expectedAccountID { reason = .accountMismatch }
        else { return }
        // Compare identifiers locally; never include them in the diagnostic.
        PlozzLog.playback.error(
            "format=plozz-preparation-1 provider=\(provider.rawValue) operation=\(operation.rawValue) "
                + "validation=\(reason.rawValue)"
        )
    }

    // l10n:content — bounded, closed-vocabulary support fields, not user-facing copy
    static func supportText<Value: Sendable>(
        provider: ProviderKind, operation: Operation, error: Error,
        captured: HTTPResponseDiagnostics.CapturedResult<Value>, elapsedMilliseconds: Int
    ) -> String {
        let code: String
        if let app = error as? AppError { code = HandoffDiagnostics.errorCode(app) }
        else if let streaming = error as? StreamingQualityError { code = streaming.diagnosticCode ?? "unspecified" }
        else { code = "unknown" }
        var fields = [
            "format=plozz-preparation-1", "attempt=\(UUID().uuidString)",
            "provider=\(provider.rawValue)", "operation=\(operation.rawValue)",
            "error=\(code)", "elapsed_ms=\(max(0, elapsedMilliseconds))"
        ]
        for (index, request) in captured.requests.enumerated() {
            let key = "request_\(index)"
            fields += [
                "\(key).route=\(request.route.rawValue)", "\(key).method=\(request.method)",
                "\(key).elapsed_ms=\(request.elapsedMilliseconds)", "\(key).bytes=\(request.bytes)",
                "\(key).format=\(request.format.rawValue)",
                "\(key).request_timeout_ms=\(request.requestTimeoutMilliseconds)",
                "\(key).resource_timeout_ms=\(request.resourceTimeoutMilliseconds)"
            ]
            if let status = request.httpStatus { fields.append("\(key).http_status=\(status)") }
            if let code = request.urlErrorCode { fields.append("\(key).url_error_code=\(code)") }
        }
        for (index, response) in captured.responses.enumerated() {
            let key = "decode_\(index)"
            fields += [
                "\(key).route=\(response.route.rawValue)", "\(key).http_status=\(response.httpStatus)",
                "\(key).bytes=\(response.bytes)", "\(key).payload=\(response.payload.rawValue)",
                "\(key).reason=\(response.reason.rawValue)", "\(key).path=\(response.path)"
            ]
            if let expected = response.expected { fields.append("\(key).expected=\(expected.rawValue)") }
        }
        for (index, transport) in captured.transport.enumerated() {
            fields += [
                "transport_\(index).route=\(transport.route.rawValue)",
                "transport_\(index).url_error_code=\(transport.urlErrorCode)"
            ]
        }
        for (index, response) in captured.http.enumerated() {
            fields += ["http_\(index).route=\(response.route.rawValue)", "http_\(index).status=\(response.httpStatus)"]
        }
        for (index, validation) in captured.validation.enumerated() {
            let key = "validation_\(index)"
            fields += ["\(key).route=\(validation.route.rawValue)", "\(key).reason=\(validation.reason.rawValue)"]
            if let count = validation.sourceCount { fields.append("\(key).sources=\(count)") }
        }
        return fields.joined(separator: " ")
    }
}
