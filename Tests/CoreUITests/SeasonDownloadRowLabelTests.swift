#if canImport(UIKit)
import CoreModels
import CoreUI
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SeasonDownloadRowLabelTests: XCTestCase {
    func testUnifiedRowsRenderEverySeasonOnceWithoutCuttingOffStatus() throws {
        var local = MediaItem(id: "library-1", title: "Season 1", kind: .season)
        local.seasonNumber = 1
        var partial = MediaItem(id: "library-2", title: "Season 2", kind: .season)
        partial.seasonNumber = 2
        let list = SeriesDownloadSeasons(
            librarySeasons: [local, partial],
            looseEpisodes: [],
            requestAvailability: .init(
                status: .partiallyAvailable,
                seasons: [
                    .init(number: 1, title: "Season 1", status: .available),
                    .init(number: 2, title: "Season 2", status: .processing),
                    .init(number: 3, title: "Season 3", status: .pending),
                    .init(number: 4, title: "Season 4", status: .unknown),
                    .init(number: 5, title: "Season 5", status: .unknown, requestStatus: .failed)
                ]
            )
        )
        XCTAssertEqual(list.rows.count, 5)
        for width in [CGFloat(276), 600] {
            let content = VStack(alignment: .leading, spacing: 18) {
                ForEach(list.rows) { row in
                    if row.canRequest {
                        Button {} label: {
                            self.rowContent(row)
                        }
                        .buttonStyle(.plain)
                    } else {
                        self.rowContent(row)
                    }
                }
            }
            .font(.body)
            .foregroundStyle(.blue)
            .tint(.blue)
            .environment(\.colorScheme, .dark)
            .frame(width: width, alignment: .leading)
            .padding(16)
            .background(.black)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width + 32, accuracy: 0.5)
            let attachment = XCTAttachment(image: image)
            attachment.name = "unified-seasons-\(Int(width))pt"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testArtworkAndRowHeightsMatchAcrossLibraryMissingAndRequestedStates() throws {
        let list = SeriesDownloadSeasons(
            librarySeasons: [], looseEpisodes: [],
            requestAvailability: .init(status: .pending, seasons: [
                .init(number: 1, title: "Season 1", status: .available),
                .init(number: 2, title: "Season 2", status: .unknown),
                .init(number: 3, title: "Season 3", status: .pending)
            ])
        )
        var heights: [CGFloat] = []
        for row in list.rows {
            let renderer = ImageRenderer(content: rowContent(row).frame(width: 600))
            let image = try XCTUnwrap(renderer.uiImage)
            heights.append(image.size.height)
            XCTAssertEqual(image.size.width, 600, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(image.size.height, 68)
        }
        XCTAssertEqual(heights[0], heights[1], accuracy: 0.5)
        XCTAssertEqual(heights[1], heights[2], accuracy: 0.5)
    }

    func testRequestRowGrowsForAccessibilityTextWithoutOverflowing() throws {
        let list = SeriesDownloadSeasons(
            librarySeasons: [], looseEpisodes: [],
            requestAvailability: .init(status: .unknown, seasons: [
                .init(number: 20, title: "Season 20", status: .unknown)
            ])
        )
        for colorScheme in [ColorScheme.light, .dark] {
            let content = Button {} label: {
                self.rowContent(list.rows[0])
            }
            .buttonStyle(.plain)
            .font(.body)
            .tint(.blue)
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.locale, Locale(identifier: "en"))
            .frame(width: 276)
            .padding(16)
            .background(colorScheme == .dark ? Color.black : Color.white)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, 308, accuracy: 0.5)
            XCTAssertGreaterThan(image.size.height, 100)
            XCTAssertLessThan(image.size.height, 450, "Request must not squeeze the labels into vertical text columns.")
            let attachment = XCTAttachment(image: image)
            attachment.name = "season-request-accessibility-\(colorScheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func rowContent(_ row: SeriesDownloadSeason) -> some View {
        SeasonDownloadRowContent(
            title: row.title,
            status: row.statusTitle,
            statusSystemImage: row.statusSystemImage,
            showsRequestAction: row.canRequest
        ) {
            SeasonDownloadRowArtwork {
                MediaArtworkPlaceholder(glyphSize: 16)
            }
        } accessory: {
            if row.hasLibraryContent {
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}
#endif
