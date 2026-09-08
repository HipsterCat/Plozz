import Foundation

/// View-scoped request coverage. Successful submissions briefly survive Seerr's
/// eventually consistent reads; explicit server states always win.
public struct SeasonRequestState: Sendable, Equatable {
    public private(set) var availability: MediaRequestAvailability?
    private var acceptedAt: [Int: Date] = [:]
    private static let confirmationGrace: TimeInterval = 60

    public init(availability: MediaRequestAvailability? = nil) {
        self.availability = availability
    }

    public static func itemKey(for item: MediaItem) -> String {
        "\(item.stablePresentationID)|\(item.providerIDs["Tmdb"] ?? "")"
    }

    public mutating func reset() {
        availability = nil
        acceptedAt = [:]
    }

    /// Call only after the server accepts the request, never when opening a
    /// picker or presenting the administrator confirmation dialog.
    public mutating func accept(_ seasonNumbers: [Int], now: Date = Date()) {
        var current = availability ?? MediaRequestAvailability(status: .unknown)
        let selected = Set(seasonNumbers.filter { $0 > 0 })
        let existing = Set(current.seasons.map(\.number))
        for number in selected.subtracting(existing).sorted() {
            current.seasons.append(
                MediaSeasonRequestState(number: number, title: "Season \(number)", status: .unknown)
            )
        }
        let requestable = Set(current.requestableSeasonNumbers)
        for number in selected.intersection(requestable) {
            acceptedAt[number] = now
        }
        availability = current.markingRequested(Array(selected))
    }

    /// A failed fetch should leave this state untouched. An old-title or
    /// old-connection response must be discarded by the owning view.
    public mutating func apply(
        _ refreshed: MediaRequestAvailability,
        now: Date = Date(),
        presentInLibrary: [Int] = []
    ) {
        let confirmed = Set(refreshed.seasons.filter {
            !$0.isRequestable || $0.status != .unknown
        }.map(\.number))
        acceptedAt = acceptedAt.filter {
            let elapsed = now.timeIntervalSince($0.value)
            return elapsed >= 0 && elapsed < Self.confirmationGrace && !confirmed.contains($0.key)
        }
        availability = refreshed.reconcilingAccepted(Set(acceptedAt.keys), previous: availability)
            .markingPresentInLibrary(presentInLibrary)
    }
}
