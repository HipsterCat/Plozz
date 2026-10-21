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
        isSubmitting: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let seasons = availability.canonicalNumberedSeasons
        let pending = seasons.filter { $0.effectiveRequestStatus == .pending }
        let awaitingRelease = seasons.filter {
            availability.downloadProgress == nil && $0.isAwaitingRelease(now: now, calendar: calendar)
        }
        let awaitingNumbers = Set(awaitingRelease.map(\.number))
        let processing = seasons.filter {
            $0.effectiveRequestStatus == .processing && !awaitingNumbers.contains($0.number)
        }
        let failures = seasons.filter { $0.effectiveRequestStatus == .failed }
        let declined = seasons.filter { $0.effectiveRequestStatus == .declined }
        let requestableCount = seasons.filter(\.isMissingSeasonRequestable).count
        let activeCount = pending.count + processing.count + awaitingRelease.count
        let activeDetail = Self.detail(
            pending: pending.count, processing: processing.count,
            failures: failures.count, declined: declined.count,
            awaitingRelease: awaitingRelease.count
        )

        hasActiveRequests = activeCount > 0
        hasFailures = !failures.isEmpty || !declined.isEmpty
        requestAllTitle = "Request All Missing (\(requestableCount))"

        if isSubmitting {
            title = "Requesting…"
            systemImage = "clock.arrow.circlepath"
            detail = activeDetail
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
            detail = activeDetail
        } else if !declined.isEmpty {
            if declined.count == 1, let season = declined.first {
                title = "S\(season.number) Request Declined"
            } else {
                title = "\(declined.count) Season Requests Declined"
            }
            systemImage = "exclamationmark.triangle.fill"
            detail = activeDetail
        } else if activeCount > 0 {
            // One request identifies its season; multiple requests summarize their count.
            if awaitingRelease.count == activeCount {
                if activeCount == 1, let season = awaitingRelease.first {
                    title = "S\(season.number) Requested · Unreleased"
                } else {
                    title = "\(activeCount) Seasons Requested · Unreleased"
                }
                systemImage = "calendar"
            } else if processing.count == activeCount {
                if activeCount == 1, let season = processing.first {
                    title = "S\(season.number) Processing"
                } else {
                    title = "\(activeCount) Seasons Processing"
                }
                systemImage = "arrow.triangle.2.circlepath"
            } else {
                if activeCount == 1, let season = pending.first {
                    title = "S\(season.number) Requested"
                } else {
                    title = "\(activeCount) Seasons Requested"
                }
                systemImage = "clock"
            }
            let stateCount = [pending.count, processing.count, awaitingRelease.count].filter { $0 > 0 }.count
            detail = stateCount > 1 ? activeDetail : nil
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
        declined: Int,
        awaitingRelease: Int = 0
    ) -> LocalizedStringResource? {
        let workflow = workflowDetail(
            pending: pending, processing: processing, failures: failures, declined: declined
        )
        guard awaitingRelease > 0 else { return workflow }
        if let workflow {
            return "\(workflow) · \(awaitingRelease) Unreleased"
        }
        return "\(awaitingRelease) Unreleased"
    }

    private static func workflowDetail(
        pending: Int,
        processing: Int,
        failures: Int,
        declined: Int
    ) -> LocalizedStringResource? {
        // Returning the switch directly keeps every branch visible to localization extraction.
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
