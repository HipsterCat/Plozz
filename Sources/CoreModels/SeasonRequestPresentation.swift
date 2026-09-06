import Foundation

/// Shared presentation for every season-request affordance.
public struct SeasonRequestPresentation: Equatable, Sendable {
    public let title: LocalizedStringResource
    public let systemImage: String
    public let detail: LocalizedStringResource?
    public let hasActiveRequests: Bool
    public let hasFailures: Bool
    public let requestAllTitle: LocalizedStringResource

    public init(
        availability: MediaRequestAvailability,
        isSubmitting: Bool = false
    ) {
        let seasons = availability.canonicalNumberedSeasons
        let pending = seasons.filter { $0.effectiveRequestStatus == .pending }
        let processing = seasons.filter { $0.effectiveRequestStatus == .processing }
        let failures = seasons.filter { $0.effectiveRequestStatus == .failed }
        let declined = seasons.filter { $0.effectiveRequestStatus == .declined }
        let requestableCount = seasons.filter(\.isRequestable).count
        let activeCount = pending.count + processing.count

        hasActiveRequests = activeCount > 0
        hasFailures = !failures.isEmpty || !declined.isEmpty
        requestAllTitle = "Request All Missing (\(requestableCount))"

        if isSubmitting {
            title = "Requesting…"
            systemImage = "clock.arrow.circlepath"
            detail = Self.detail(
                pending: pending.count,
                processing: processing.count,
                failures: failures.count,
                declined: declined.count
            )
        } else if seasons.isEmpty {
            title = "Seasons Unavailable"
            systemImage = "exclamationmark.circle"
            detail = nil
        } else if !failures.isEmpty {
            if failures.count == 1, let season = failures.first {
                title = "S\(season.number) Request Failed"
            } else {
                title = "\(failures.count) Season Requests Failed"
            }
            systemImage = "exclamationmark.triangle.fill"
            detail = Self.detail(
                pending: pending.count,
                processing: processing.count,
                failures: failures.count,
                declined: declined.count
            )
        } else if !declined.isEmpty {
            if declined.count == 1, let season = declined.first {
                title = "S\(season.number) Request Declined"
            } else {
                title = "\(declined.count) Season Requests Declined"
            }
            systemImage = "exclamationmark.triangle.fill"
            detail = Self.detail(
                pending: pending.count,
                processing: processing.count,
                failures: 0,
                declined: declined.count
            )
        } else if activeCount > 0 {
            if processing.count == activeCount {
                title = activeCount == 1
                    ? "S\(processing[0].number) Processing"
                    : "\(activeCount) Seasons Processing"
                systemImage = "arrow.triangle.2.circlepath"
            } else {
                title = activeCount == 1
                    ? "S\(pending[0].number) Requested"
                    : "\(activeCount) Seasons Requested"
                systemImage = "clock"
            }
            detail = pending.isEmpty || processing.isEmpty
                ? nil
                : Self.detail(
                    pending: pending.count,
                    processing: processing.count,
                    failures: 0,
                    declined: 0
                )
        } else if requestableCount > 0 {
            title = "Request Seasons"
            systemImage = "plus.circle"
            detail = nil
        } else {
            title = "Season Requests"
            systemImage = seasons.allSatisfy { $0.status == .available }
                ? "checkmark.circle"
                : "list.bullet"
            detail = nil
        }
    }

    private static func detail(
        pending: Int,
        processing: Int,
        failures: Int,
        declined: Int
    ) -> LocalizedStringResource? {
        switch (pending, processing, failures, declined) {
        case (0, 0, 0, 0):
            nil
        case let (pending, 0, 0, 0):
            "\(pending) Requested"
        case let (0, processing, 0, 0):
            "\(processing) Processing"
        case let (0, 0, failures, 0):
            "\(failures) Failed"
        case let (0, 0, 0, declined):
            "\(declined) Declined"
        case let (pending, processing, 0, 0):
            "\(pending) Requested, \(processing) Processing"
        case let (pending, 0, failures, 0):
            "\(pending) Requested, \(failures) Failed"
        case let (0, processing, failures, 0):
            "\(processing) Processing, \(failures) Failed"
        case let (pending, processing, failures, 0):
            "\(pending) Requested, \(processing) Processing, \(failures) Failed"
        case let (pending, 0, 0, declined):
            "\(pending) Requested, \(declined) Declined"
        case let (0, processing, 0, declined):
            "\(processing) Processing, \(declined) Declined"
        case let (pending, processing, 0, declined):
            "\(pending) Requested, \(processing) Processing, \(declined) Declined"
        case let (0, 0, failures, declined):
            "\(failures) Failed, \(declined) Declined"
        case let (pending, 0, failures, declined):
            "\(pending) Requested, \(failures) Failed, \(declined) Declined"
        case let (0, processing, failures, declined):
            "\(processing) Processing, \(failures) Failed, \(declined) Declined"
        case let (pending, processing, failures, declined):
            "\(pending) Requested, \(processing) Processing, \(failures) Failed, \(declined) Declined"
        }
    }
}
