import Foundation
import CoreModels

public struct SiloSetupFailure: Error, Sendable {
    public let diagnostic: SiloSetupDiagnostic
    public let underlying: AppError

    public init(_ diagnostic: SiloSetupDiagnostic, underlying: AppError = .invalidResponse) {
        self.diagnostic = diagnostic
        self.underlying = underlying
    }

    public var userMessage: LocalizedStringResource {
        switch diagnostic.reason {
        case .addressMismatch:
            return "Silo supplied an approval link for a different address. Go back and enter the public address configured in Silo."
        case .redirect:
            return "This address redirects to another server address. Go back and enter the final address shown in your browser."
        default: break
        }
        if diagnostic.response == .html {
            return "This address returned a web page instead of Silo's API. Check the server address and any proxy sign-in requirements."
        }
        switch diagnostic.reason {
        case .network, .unauthorized, .rateLimited: return underlying.userMessage
        default: break
        }
        switch diagnostic.stage {
        case .validation: return "We couldn't verify Silo at this address. Check the address and update Silo if needed."
        case .capability, .start, .approvalLink:
            return "Silo couldn't create a sign-in code. Try again. If this continues, check that device pairing is enabled and Silo is up to date."
        case .poll: return "We couldn't complete Silo approval. Try again to get a new code."
        case .profiles: return "Silo approved this device, but we couldn't load your profiles. Try again without repeating approval."
        case .pin: return "We couldn't verify your Silo profile PIN. Try again."
        case .session: return "We couldn't finish connecting your Silo profile. Try again."
        }
    }
}

public enum SiloSetupRequest {
    public static func decode<T: Decodable>(
        _ type: T.Type, endpoint: Endpoint, baseURL: URL, http: any HTTPClient,
        stage: SiloSetupDiagnostic.Stage
    ) async throws -> T {
        let data: Data
        let status: Int
        let response: SiloSetupDiagnostic.Response
        do {
            let result = try await http.sendRaw(endpoint, baseURL: baseURL)
            data = result.0
            status = result.1.statusCode
            response = .init(mimeType: result.1.mimeType)
        } catch {
            if error is CancellationError || error as? AppError == .cancelled { throw AppError.cancelled }
            throw failure(error, stage: stage)
        }
        try Task.checkCancellation()
        let reason: SiloSetupDiagnostic.Reason
        let underlying: AppError
        switch status {
        case 200...299:
            do { return try JSONDecoder().decode(type, from: data) }
            catch {
                throw SiloSetupFailure(.init(stage: stage, reason: .malformed, httpStatus: status, response: response),
                                       underlying: .decoding)
            }
        case 300...399: reason = .redirect; underlying = .invalidResponse
        case 401, 403: reason = .unauthorized; underlying = .unauthorized
        case 404: reason = .notFound; underlying = .notFound
        case 429: reason = .rateLimited; underlying = .rateLimited(retryAfter: nil)
        case 500...599: reason = .server; underlying = .invalidResponse
        default: reason = .invalidResponse; underlying = .invalidResponse
        }
        throw SiloSetupFailure(.init(stage: stage, reason: reason, httpStatus: status, response: response),
                               underlying: underlying)
    }

    public static func failure(_ error: Error, stage: SiloSetupDiagnostic.Stage) -> SiloSetupFailure {
        if let failure = error as? SiloSetupFailure { return failure }
        let underlying = (error as? AppError) ?? .invalidResponse
        let reason: SiloSetupDiagnostic.Reason
        switch underlying {
        case .serverUnreachable: reason = .network
        case .unauthorized: reason = .unauthorized
        case .notFound: reason = .notFound
        case .rateLimited: reason = .rateLimited
        case .decoding: reason = .malformed
        default: reason = .invalidResponse
        }
        return SiloSetupFailure(.init(stage: stage, reason: reason), underlying: underlying)
    }
}
