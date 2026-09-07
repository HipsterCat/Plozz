import CoreModels
import SwiftUI

public struct SeasonEpisodeCoverageHeader: View {
    private let coverage: SeasonEpisodeCoverage?
    private let isLoading: Bool
    private let hasNumberingConflict: Bool

    public init(coverage: SeasonEpisodeCoverage?, isLoading: Bool, hasNumberingConflict: Bool) {
        self.coverage = coverage
        self.isLoading = isLoading
        self.hasNumberingConflict = hasNumberingConflict
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let coverage {
                Text(coverage.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                if coverage.missing > 0 && coverage.unaired > 0 {
                    Text("\(coverage.missing) missing, \(coverage.unaired) not yet released")
                } else if coverage.missing > 0 {
                    Text("\(coverage.missing) missing from your library")
                } else if coverage.unaired > 0 {
                    Text("\(coverage.unaired) not yet released")
                }
            } else if isLoading {
                Text("Checking episode availability…")
            } else if hasNumberingConflict {
                Text("Episode numbering differs. Showing library episodes without a coverage count.")
            } else {
                Text("Library episodes")
            }
        }
        .font(.caption)
        .foregroundStyle(Color.secondary)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

/// One request action for the season, never one request per missing episode.
public struct SeasonEpisodeRequestControls: View {
    private let state: MediaSeasonRequestState?
    private let hasUnavailableEpisodes: Bool
    private let isSubmitting: Bool
    private let isRefreshing: Bool
    private let refreshFailed: Bool
    private let actingName: String?
    private let managementURL: URL?
    private let onRefresh: () -> Void
    private let onRequest: () -> Void

    public init(
        state: MediaSeasonRequestState?,
        hasUnavailableEpisodes: Bool,
        isSubmitting: Bool,
        isRefreshing: Bool,
        refreshFailed: Bool,
        actingName: String?,
        managementURL: URL?,
        onRefresh: @escaping () -> Void,
        onRequest: @escaping () -> Void
    ) {
        self.state = state
        self.hasUnavailableEpisodes = hasUnavailableEpisodes
        self.isSubmitting = isSubmitting
        self.isRefreshing = isRefreshing
        self.refreshFailed = refreshFailed
        self.actingName = actingName
        self.managementURL = managementURL
        self.onRefresh = onRefresh
        self.onRequest = onRequest
    }

    private var hasRequestStatus: Bool {
        guard let state, state.status != .available else { return false }
        return state.isInFlight || state.requestFailed
            || state.requestStatus == .failed || state.requestStatus == .declined
    }

    public var body: some View {
        if isSubmitting {
            SeriesDownloadActionLabel(
                title: "Submitting Request…",
                subtitle: "Request for your library",
                systemImage: "clock.arrow.circlepath"
            ) {}
        } else if refreshFailed && (hasUnavailableEpisodes || hasRequestStatus) {
            Button(action: onRefresh) {
                SeriesDownloadActionLabel(
                    title: "Retry Season Status",
                    subtitle: "Couldn’t confirm the latest request status.",
                    systemImage: "arrow.clockwise"
                ) {}
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        } else if let state, state.isRequestable, hasUnavailableEpisodes {
            Button(action: onRequest) {
                SeriesDownloadActionLabel(
                    title: "Request Season",
                    subtitle: "Request for your library",
                    systemImage: "plus.circle",
                    detail: actingName.map { "Requests as \($0)." }
                ) {}
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        } else if let state, hasRequestStatus || (hasUnavailableEpisodes && !state.isRequestable) {
            if let managementURL {
                Link(destination: managementURL) {
                    SeasonEpisodeRequestStatusLabel(state: state, opensSeerr: true)
                }
                .buttonStyle(.plain)
            } else {
                SeasonEpisodeRequestStatusLabel(state: state, opensSeerr: false)
            }
        } else if state == nil && hasUnavailableEpisodes {
            Button(action: onRefresh) {
                SeriesDownloadActionLabel(
                    title: isRefreshing ? "Checking Season Status…" : "Load Season Status",
                    subtitle: "Check whether this season can be requested",
                    systemImage: "arrow.clockwise"
                ) {}
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
    }
}

private struct SeasonEpisodeRequestStatusLabel: View {
    let state: MediaSeasonRequestState
    let opensSeerr: Bool

    private var title: LocalizedStringResource {
        if state.status == .available { return "Available on Server" }
        if state.requestFailed || state.requestStatus == .failed { return "Request Failed" }
        if state.requestStatus == .declined { return "Request Declined" }
        if state.requestStatus == .pending || state.status == .pending { return "Season Requested" }
        if state.requestStatus == .processing || state.status == .processing { return "Request Processing" }
        if state.requestStatus == .completed { return "Request Completed" }
        return "Season Already Managed"
    }

    var body: some View {
        SeriesDownloadActionLabel(
            title: title,
            subtitle: opensSeerr ? "Open in Seerr to review this season" : "This season is already tracked by Seerr",
            systemImage: state.statusSystemImage
        ) {
            if opensSeerr {
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(Color.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}
