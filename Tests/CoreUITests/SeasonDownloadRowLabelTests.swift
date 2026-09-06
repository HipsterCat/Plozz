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
                    HStack(spacing: 12) {
                        SeasonDownloadRowLabel(
                            title: row.title,
                            status: row.statusTitle,
                            statusSystemImage: row.statusSystemImage
                        )
                        Spacer()
                        if row.canRequest {
                            Text("Request")
                                .fixedSize()
                        } else if row.hasLibraryContent {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                }
            }
            .font(.system(size: 17))
            .foregroundStyle(.white)
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
}
#endif
