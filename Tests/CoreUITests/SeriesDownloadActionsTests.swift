#if canImport(UIKit)
    import CoreModels
    import CoreUI
    import SwiftUI
    import UIKit
    import XCTest

    @MainActor
    final class SeriesDownloadActionsTests: XCTestCase {
        private var mixed: MediaRequestAvailability {
            MediaRequestAvailability(
                status: .partiallyAvailable,
                seasons: [
                    .init(number: 1, title: "Season 1", status: .available),
                    .init(number: 2, title: "Season 2", status: .pending),
                    .init(number: 3, title: "Season 3", status: .processing),
                    .init(number: 4, title: "Season 4", status: .unknown),
                    .init(number: 5, title: "Season 5", status: .unknown),
                ]
            )
        }

        func testActionsRenderLoadingFailureEmptyAndMixedSeasonStates() throws {
            let cases: [(String, MediaRequestAvailability?, Bool, Bool)] = [
                ("loading", nil, false, false),
                ("retry", nil, false, true),
                ("empty", .init(status: .unknown, seasons: []), false, false),
                ("mixed", mixed, false, false),
                ("submitting", mixed, true, false),
                ("stale", mixed, false, true),
            ]
            for (name, availability, submitting, failed) in cases {
                for width in [CGFloat(320), 640] {
                    let content = VStack(alignment: .leading, spacing: 12) {
                        SeriesDownloadActions(
                            hasDownloads: true,
                            canRequestSeasons: true,
                            availability: availability,
                            isSubmitting: submitting,
                            isRefreshing: false,
                            refreshFailed: failed,
                            actingName: "Viewer",
                            onRefresh: {},
                            onRequest: { _ in }
                        ) {
                            self.downloadButton()
                        }
                    }
                    .font(.body)
                    .tint(.blue)
                    .environment(\.colorScheme, .dark)
                    .frame(width: width, alignment: .leading)
                    .padding(16)
                    .background(.black)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertGreaterThan(image.size.height, 0)
                    XCTAssertEqual(image.size.width, width + 32, accuracy: 0.5)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "season-actions-\(name)-\(Int(width))pt"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }

        func testRequestOnlyAndDownloadOnlyActionsRemainIndependent() throws {
            for hasDownloads in [false, true] {
                let content = VStack {
                    SeriesDownloadActions(
                        hasDownloads: hasDownloads,
                        canRequestSeasons: !hasDownloads,
                        availability: hasDownloads ? nil : mixed,
                        isSubmitting: false,
                        isRefreshing: false,
                        refreshFailed: false,
                        actingName: nil,
                        onRefresh: {},
                        onRequest: { _ in }
                    ) {
                        self.downloadButton()
                    }
                }
                .frame(width: 300)
                let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
                XCTAssertEqual(image.size.width, 300, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(image.size.height, 44)
            }
        }

        func testNoEmptyActionGroupWhenEverySeasonIsAlreadyRequested() throws {
            let content = VStack {
                SeriesDownloadActions(
                    hasDownloads: false,
                    canRequestSeasons: true,
                    availability: .init(
                        status: .pending,
                        seasons: [
                            .init(number: 1, title: "Season 1", status: .pending)
                        ]),
                    isSubmitting: false,
                    isRefreshing: false,
                    refreshFailed: false,
                    actingName: nil,
                    onRefresh: {},
                    onRequest: { _ in }
                ) {}
            }
            .frame(width: 300)
            .padding(16)
            let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
            XCTAssertEqual(image.size.height, 32, accuracy: 0.5)
        }

        private func downloadButton(
            _ action: SeriesDownloadAction = .download,
            destination: MediaDownloadDestination = .iPhone
        ) -> some View {
            Button {
            } label: {
                SeriesDownloadActionLabel(
                    title: action.title(for: destination),
                    subtitle: "All available episodes in this show, for offline viewing.",
                    systemImage: action.systemImage
                ) {}
            }
            .buttonStyle(.plain)
            .disabled(!action.isEnabled)
        }

        #if os(iOS)
            func testNativeSeasonSheetLayoutAndStatusSpacing() async throws {
                for (name, size) in [
                    ("phone", CGSize(width: 375, height: 812)),
                    ("landscape", CGSize(width: 812, height: 375)),
                    ("tablet", CGSize(width: 768, height: 1024)),
                ] {
                    try await captureNativeSheet(
                        nativeSheet(availability: mixed, destination: name == "tablet" ? .iPad : .iPhone),
                        size: size,
                        name: "season-sheet-\(name)"
                    )
                }
            }

            func testNativeSeasonSheetLoadingRetryAndAccessibility() async throws {
                let size = CGSize(width: 375, height: 812)
                try await captureNativeSheet(
                    nativeSheet(availability: nil, isRefreshing: true),
                    size: size, name: "season-sheet-loading"
                )
                try await captureNativeSheet(
                    nativeSheet(availability: nil, hasDownloads: false, refreshFailed: true),
                    size: size, name: "season-sheet-request-only-retry"
                )
                for style in [ColorScheme.light, .dark] {
                    try await captureNativeSheet(
                        nativeSheet(availability: mixed, colorScheme: style)
                            .environment(\.dynamicTypeSize, .accessibility5),
                        size: size, name: "season-sheet-accessibility-\(style)", colorScheme: style
                    )
                }
            }

            private func nativeSheet(
                availability: MediaRequestAvailability?,
                destination: MediaDownloadDestination = .iPhone,
                hasDownloads: Bool = true,
                isRefreshing: Bool = false,
                refreshFailed: Bool = false,
                colorScheme: ColorScheme = .dark
            ) -> some View {
                var local = MediaItem(id: "local-season-1", title: "Season 1", kind: .season)
                local.seasonNumber = 1
                let seasons = SeriesDownloadSeasons(
                    librarySeasons: hasDownloads ? [local] : [],
                    looseEpisodes: [],
                    requestAvailability: availability
                )
                return NavigationStack {
                    List {
                        SeriesDownloadActions(
                            hasDownloads: hasDownloads,
                            canRequestSeasons: true,
                            availability: availability,
                            isSubmitting: false,
                            isRefreshing: isRefreshing,
                            refreshFailed: refreshFailed,
                            actingName: nil,
                            onRefresh: {},
                            onRequest: { _ in }
                        ) {
                            self.downloadButton(destination: destination)
                        }
                        if !seasons.rows.isEmpty {
                            Section {
                                ForEach(seasons.rows) { row in
                                    if row.hasLibraryContent {
                                        NavigationLink {
                                            Text("Episodes")
                                        } label: {
                                            self.seasonRow(row)
                                        }
                                    } else if row.canRequest {
                                        Button {
                                        } label: {
                                            self.seasonRow(row)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        self.seasonRow(row)
                                    }
                                }
                            } header: {
                                Text("Rick and Morty").textCase(nil)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .contentMargins(.top, 12, for: .scrollContent)
                    .listSectionSpacing(16)
                    .navigationTitle("Seasons")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {}
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            SeasonRequestRefreshButton(
                                isRefreshing: isRefreshing,
                                isSubmitting: false,
                                onRefresh: {}
                            )
                        }
                    }
                }
                .tint(.blue)
                .environment(\.colorScheme, colorScheme)
                .environment(\.locale, Locale(identifier: "en"))
            }

            private func seasonRow(_ row: SeriesDownloadSeason) -> some View {
                SeasonDownloadRowContent(
                    title: Text(row.title),
                    status: row.statusTitle,
                    statusSystemImage: row.statusSystemImage,
                    showsRequestAction: row.canRequest
                ) {
                    SeasonDownloadRowArtwork(showsMediaEdge: row.hasLibraryContent) {
                        MediaArtworkPlaceholder(glyphSize: 16, symbol: row.hasLibraryContent ? .playback : .media)
                    }
                } accessory: {
                }
            }

        #endif
    }
#endif
