import CoreModels
import CoreUI
import SwiftUI
@testable import AppShelliOS

struct HeroRequestControlsFixture: View {
    @State private var presentsSeasons = false
    @State private var availability: MediaRequestAvailability?
    @State private var refreshFailed = false
    @State private var requested = ""
    @State private var error: LocalizedStringResource?
    @State private var confirmationItem: MediaItem?
    @State private var confirmationSeasons: [Int]?
    @State private var confirmationContext: String?
    private let series = MediaItem(id: "series", title: "Fixture Series", kind: .series)
    private let movie = MediaItem(id: "movie", title: "Fixture Movie", kind: .movie)
    private var arguments: [String] { ProcessInfo.processInfo.arguments }
    private var isLight: Bool { arguments.contains("--light") }

    init() {
        let failed = ProcessInfo.processInfo.arguments.contains("--failed-seasons")
        _availability = State(initialValue: failed ? nil : Self.availableSeasons)
        _refreshFailed = State(initialValue: failed)
    }

    static var availableSeasons: MediaRequestAvailability {
        .init(status: .unknown, seasons: [
            .init(number: 1, title: "Season 1", status: .unknown),
            .init(number: 2, title: "Season 2", status: .available),
            .init(number: 3, title: "Season 3", status: .unknown)
        ])
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                requestControl("seasons", item: series, cta: .request, availability: availability, opensSeasons: true)
                requestControl("movie", item: movie, cta: .request)
                requestControl("submitting", item: movie, cta: .request, isRequesting: true)
                requestControl("requested", item: movie, cta: .requested)
                requestControl("downloading", item: movie, cta: .downloading(progress: 0.42))
                requestControl("loading-seasons", item: series, cta: .request, opensSeasons: true)
                requestControl("pending-seasons", item: series, cta: .requested,
                               availability: Self.availableSeasons.markingRequested([1]), opensSeasons: true)
                requestControl("submitting-seasons", item: series, cta: .request, isRequesting: true,
                               availability: Self.availableSeasons, opensSeasons: true)
                requestControl("failed-seasons", item: series, cta: .request,
                               availability: .init(status: .unknown, seasons: [
                                .init(number: 1, title: "Season 1", status: .unknown, requestFailed: true)
                               ]), opensSeasons: true)
                requestControl("processing-seasons", item: series, cta: .requested,
                               availability: .init(status: .processing, seasons: [
                                .init(number: 1, title: "Season 1", status: .processing),
                                .init(number: 2, title: "Season 2", status: .pending)
                               ]), opensSeasons: true)
                Text(verbatim: requested).accessibilityIdentifier("requested-seasons")
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isLight ? Color(white: 0.92) : Color.black)
        .plozzSheet(isPresented: $presentsSeasons) {
            PlozziOSSeasonRequestSheet(
                series: series, availability: availability,
                isRequesting: arguments.contains("--submitting-seasons"),
                isRefreshing: false, refreshFailed: refreshFailed, actingName: "Fixture Viewer",
                onRefresh: {
                    availability = Self.availableSeasons
                    refreshFailed = false
                },
                onRequest: { seasons in
                    if arguments.contains("--confirm-request") {
                        confirmationItem = series
                        confirmationSeasons = seasons
                        confirmationContext = "fixture"
                    } else {
                        submit(seasons)
                    }
                }
            )
            .modifier(requestPresentation(isSheet: true))
        }
        .modifier(requestPresentation(isSheet: false))
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.themePalette, isLight ? .light : .dark)
        .environment(\.colorScheme, isLight ? .light : .dark)
        .environment(\.plozzReduceTransparency, arguments.contains("--reduced"))
        .preferredColorScheme(isLight ? .light : .dark)
    }

    private func requestControl(
        _ id: String, item: MediaItem, cta: HeroCTA, isRequesting: Bool = false,
        availability: MediaRequestAvailability? = nil, opensSeasons: Bool = false
    ) -> some View {
        PlozziOSHeroRequestButton(item: item, request: .init(
            cta: cta, isRequesting: isRequesting, actingName: "Fixture Viewer",
            onRequest: { _ in requested = "movie" },
            seasonAvailability: availability,
            onOpenSeasonRequests: opensSeasons ? { presentsSeasons = true } : nil
        ))
        .accessibilityIdentifier("hero-\(id)")
    }

    private func submit(_ seasons: [Int]) {
        if arguments.contains("--request-fails") {
            error = "Fixture request failed"
        } else {
            requested = seasons.map(String.init).joined(separator: ",")
            availability = availability?.markingRequested(seasons)
        }
    }

    private func requestPresentation(isSheet: Bool) -> PlozziOSRequestPresentation {
        .init(
            presentsDownloads: $presentsSeasons, isSheet: isSheet, error: $error,
            confirmationItem: $confirmationItem, confirmationSeasons: $confirmationSeasons,
            confirmationContext: $confirmationContext,
            onConfirm: { _, seasons, _ in submit(seasons ?? []) }
        )
    }
}
