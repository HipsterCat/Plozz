#if canImport(SwiftUI)
import SwiftUI
import CoreModels

/// Shared season actions and coverage, including completed seasons so a mixed
/// request never looks like the entire series has finished.
public struct SeasonRequestMenuContent: View {
    private let availability: MediaRequestAvailability
    private let isSubmitting: Bool
    private let refreshFailed: Bool
    private let showsDividers: Bool
    private let onRefresh: (() -> Void)?
    private let onRequest: ([Int]) -> Void

    public init(
        availability: MediaRequestAvailability,
        requestAllTitle _: String = "Request All Seasons",
        isSubmitting: Bool = false,
        refreshFailed: Bool = false,
        showsDividers: Bool = true,
        onRefresh: (() -> Void)? = nil,
        onRequest: @escaping ([Int]) -> Void
    ) {
        self.availability = availability
        self.isSubmitting = isSubmitting
        self.refreshFailed = refreshFailed
        self.showsDividers = showsDividers
        self.onRefresh = onRefresh
        self.onRequest = onRequest
    }

    private var seasons: [MediaSeasonRequestState] {
        availability.canonicalNumberedSeasons
    }

    private var requestableSeasons: [MediaSeasonRequestState] {
        seasons.filter(\.isRequestable)
    }

    public var body: some View {
        if requestableSeasons.count > 1 {
            Button(SeasonRequestPresentation(availability: availability).requestAllTitle) {
                onRequest(requestableSeasons.map(\.number))
            }
            .disabled(isSubmitting)
            if showsDividers { Divider() }
        }
        ForEach(seasons) { season in
            if season.isRequestable {
                Button("Request \(season.title)") {
                    onRequest([season.number])
                }
                .disabled(isSubmitting)
            } else {
                Button {} label: {
                    Label {
                        Text("\(season.title) — \(Text(season.statusTitle))")
                    } icon: {
                        Image(systemName: season.statusSystemImage)
                    }
                }
                .disabled(true)
            }
        }
        if SeasonRequestPresentation(availability: availability).hasFailures {
            Text("Failed or declined requests need attention in Seerr.")
        }
        if refreshFailed {
            Text("Couldn’t refresh. Showing last known season statuses.")
        }
        if let onRefresh {
            if showsDividers { Divider() }
            Button("Refresh Status", systemImage: "arrow.clockwise", action: onRefresh)
        }
    }
}
#endif
