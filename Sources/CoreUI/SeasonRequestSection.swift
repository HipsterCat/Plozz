import CoreModels
import SwiftUI

/// Server requests stay separate from downloads of episodes already in the library.
public struct SeasonRequestSection: View {
    private let availability: MediaRequestAvailability?
    private let isSubmitting: Bool
    private let refreshFailed: Bool
    private let actingName: String?
    private let onRefresh: () -> Void
    private let onRequest: ([Int]) -> Void

    public init(
        availability: MediaRequestAvailability?,
        isSubmitting: Bool,
        refreshFailed: Bool,
        actingName: String?,
        onRefresh: @escaping () -> Void,
        onRequest: @escaping ([Int]) -> Void
    ) {
        self.availability = availability
        self.isSubmitting = isSubmitting
        self.refreshFailed = refreshFailed
        self.actingName = actingName
        self.onRefresh = onRefresh
        self.onRequest = onRequest
    }

    public var body: some View {
        Section {
            if let availability {
                let presentation = SeasonRequestPresentation(
                    availability: availability,
                    isSubmitting: isSubmitting
                )
                if isSubmitting || presentation.hasActiveRequests || presentation.hasFailures {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(presentation.title)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = presentation.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } icon: {
                        Image(systemName: presentation.systemImage)
                    }
                }
                if availability.canonicalNumberedSeasons.isEmpty {
                    Text("Season information is unavailable.")
                        .foregroundStyle(.secondary)
                }
                SeasonRequestMenuContent(
                    availability: availability,
                    isSubmitting: isSubmitting,
                    refreshFailed: refreshFailed,
                    showsDividers: false,
                    onRefresh: onRefresh,
                    onRequest: onRequest
                )
            } else if refreshFailed {
                Button("Retry Season Status", systemImage: "arrow.clockwise", action: onRefresh)
            } else {
                ProgressView("Loading Seasons…")
            }
        } header: {
            Text("Request Seasons")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Requests add missing seasons to your media server. Downloads save available episodes to this device.")
                if let actingName {
                    Text("Requests as \(actingName).")
                }
            }
        }
        .lineLimit(nil)
    }
}
