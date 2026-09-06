import CoreModels
import SwiftUI

/// Bulk requests and refresh state above the unified season list.
public struct SeasonRequestControls: View {
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
                if isSubmitting {
                    Label("Requesting…", systemImage: "clock.arrow.circlepath")
                }
                if availability.canonicalNumberedSeasons.isEmpty {
                    Text("Season information is unavailable.")
                        .foregroundStyle(.secondary)
                }
                if !availability.requestableSeasonNumbers.isEmpty {
                    Button(presentation.requestAllTitle) {
                        onRequest(availability.requestableSeasonNumbers)
                    }
                    .disabled(isSubmitting)
                }
                if presentation.hasFailures {
                    Text("Failed or declined requests need attention in Seerr.")
                }
                if refreshFailed {
                    Text("Couldn’t refresh. Showing last known season statuses.")
                }
                Button("Refresh Status", systemImage: "arrow.clockwise", action: onRefresh)
            } else if refreshFailed {
                Button("Retry Season Status", systemImage: "arrow.clockwise", action: onRefresh)
            } else {
                ProgressView("Loading Seasons…")
            }
        } header: {
            Text("Requests")
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
