import CoreModels
import SwiftUI

/// The compact bulk-action group above the unified season list.
public struct SeriesDownloadActions<Downloads: View>: View {
    private let hasDownloads: Bool
    private let canRequestSeasons: Bool
    private let availability: MediaRequestAvailability?
    private let isSubmitting: Bool
    private let isRefreshing: Bool
    private let refreshFailed: Bool
    private let actingName: String?
    private let onRefresh: () -> Void
    private let onRequest: ([Int]) -> Void
    private let downloads: Downloads

    public init(
        hasDownloads: Bool,
        canRequestSeasons: Bool,
        availability: MediaRequestAvailability?,
        isSubmitting: Bool,
        isRefreshing: Bool,
        refreshFailed: Bool,
        actingName: String?,
        onRefresh: @escaping () -> Void,
        onRequest: @escaping ([Int]) -> Void,
        @ViewBuilder downloads: () -> Downloads
    ) {
        self.hasDownloads = hasDownloads
        self.canRequestSeasons = canRequestSeasons
        self.availability = availability
        self.isSubmitting = isSubmitting
        self.isRefreshing = isRefreshing
        self.refreshFailed = refreshFailed
        self.actingName = actingName
        self.onRefresh = onRefresh
        self.onRequest = onRequest
        self.downloads = downloads()
    }

    private var hasRequestContent: Bool {
        guard canRequestSeasons else { return false }
        guard let availability else { return true }
        return isSubmitting || refreshFailed
            || availability.canonicalNumberedSeasons.isEmpty
            || !availability.requestableSeasonNumbers.isEmpty
            || SeasonRequestPresentation(availability: availability).hasFailures
    }

    public var body: some View {
        if hasDownloads || hasRequestContent {
            Section {
                if hasDownloads {
                    downloads
                }
                if hasRequestContent {
                    SeasonRequestControls(
                        availability: availability,
                        isSubmitting: isSubmitting,
                        isRefreshing: isRefreshing,
                        refreshFailed: refreshFailed,
                        actingName: actingName,
                        onRefresh: onRefresh,
                        onRequest: onRequest
                    )
                }
            }
            .lineLimit(nil)
        }
    }
}

private struct SeasonRequestControls: View {
    let availability: MediaRequestAvailability?
    let isSubmitting: Bool
    let isRefreshing: Bool
    let refreshFailed: Bool
    let actingName: String?
    let onRefresh: () -> Void
    let onRequest: ([Int]) -> Void

    var body: some View {
        if isSubmitting {
            SeriesDownloadActionLabel(
                title: "Requesting…",
                subtitle: "Request for your library",
                systemImage: "clock.arrow.circlepath",
                detail: actingName.map { "Requests as \($0)." }
            ) {}
        } else if let availability, !availability.requestableSeasonNumbers.isEmpty {
            Button {
                onRequest(availability.requestableSeasonNumbers)
            } label: {
                SeriesDownloadActionLabel(
                    title: SeasonRequestPresentation(availability: availability).requestAllTitle,
                    subtitle: "Request for your library",
                    systemImage: "plus.circle",
                    detail: actingName.map { "Requests as \($0)." }
                ) {}
            }
            .buttonStyle(.plain)
        }

        if refreshFailed {
            SeasonRequestRetryRow(
                message: availability == nil
                    ? "Couldn’t load season statuses."
                    : "Couldn’t refresh. Showing last known season statuses.",
                isEnabled: !isSubmitting && !isRefreshing,
                onRetry: onRefresh
            )
        } else if let availability, availability.canonicalNumberedSeasons.isEmpty {
            SeasonRequestRetryRow(
                message: "Season information is unavailable.",
                isEnabled: !isSubmitting && !isRefreshing,
                onRetry: onRefresh
            )
        } else if availability == nil, !isSubmitting {
            SeriesDownloadActionLabel(
                title: "Loading Seasons…",
                subtitle: "Checking request status",
                systemImage: "clock"
            ) {
                ProgressView()
                    .controlSize(.small)
            }
        }

        if let availability, SeasonRequestPresentation(availability: availability).hasFailures {
            Text("Failed or declined requests need attention in Seerr.")
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SeasonRequestRetryRow: View {
    let message: LocalizedStringResource
    let isEnabled: Bool
    let onRetry: () -> Void

    var body: some View {
        Button(action: onRetry) {
            SeriesDownloadActionLabel(
                title: "Retry Season Status",
                subtitle: message,
                systemImage: "arrow.clockwise"
            ) {}
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

public struct SeriesDownloadActionLabel<Accessory: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

    private let title: LocalizedStringResource
    private let subtitle: LocalizedStringResource
    private let systemImage: String
    private let detail: LocalizedStringResource?
    private let accessory: Accessory

    public init(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        systemImage: String,
        detail: LocalizedStringResource? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.detail = detail
        self.accessory = accessory()
    }

    public var body: some View {
        let contentLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: iconSize)
                .accessibilityHidden(true)
            contentLayout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(Color.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                accessory
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        #if os(iOS)
        .alignmentGuide(.listRowSeparatorLeading) {
            $0[.leading] + iconSize + 12
        }
        #endif
    }
}

public struct SeasonRequestRefreshButton: View {
    private let isRefreshing: Bool
    private let isSubmitting: Bool
    private let onRefresh: () -> Void

    public init(isRefreshing: Bool, isSubmitting: Bool, onRefresh: @escaping () -> Void) {
        self.isRefreshing = isRefreshing
        self.isSubmitting = isSubmitting
        self.onRefresh = onRefresh
    }

    public var body: some View {
        Button(action: onRefresh) {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .opacity(isRefreshing ? 0 : 1)
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .accessibilityLabel("Refresh Season Status")
        .disabled(isRefreshing || isSubmitting)
    }
}
