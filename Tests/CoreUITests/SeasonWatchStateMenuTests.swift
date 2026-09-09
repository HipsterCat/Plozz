#if canImport(UIKit)
import CoreModels
import CoreUI
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SeasonWatchStateMenuTests: XCTestCase {
    private final class Handler: MediaItemActionHandling {
        var requestedItems: [MediaItem] = []
        var requestedContexts: [MediaItemActionContext] = []
        var performedActions: [MediaItemAction] = []
        var availableActions: [MediaItemAction] = [.markWatched]

        func actions(for item: MediaItem, context: MediaItemActionContext) -> [MediaItemAction] {
            requestedItems.append(item)
            requestedContexts.append(context)
            return availableActions
        }

        func perform(_ action: MediaItemAction, on item: MediaItem, context: MediaItemActionContext) {
            performedActions.append(action)
        }
    }

    func testSeasonMenuResolvesHandlerBeforePresentationWithoutInheritingEpisodeContext() {
        let handler = Handler()
        let season = MediaItem(id: "s2", title: "Season 2", kind: .season, sourceAccountID: "a")
        let host = UIHostingController(rootView:
            SeasonWatchStateMenu(for: season, action: {}) {
                Text("Season 2")
            }
                .buttonStyle(PlozzSeasonTabStyle(isSelected: true))
                .mediaItemActionContext(MediaItemActionContext(precedingContainerIDs: ["s1"]))
                .mediaItemActionHandler(handler)
        )
        let size = host.sizeThatFits(in: CGSize(width: 500, height: 200))
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertFalse(handler.requestedItems.isEmpty)
        XCTAssertTrue(handler.requestedItems.allSatisfy { $0 == season })
        XCTAssertTrue(handler.requestedContexts.allSatisfy { $0 == .none })
        XCTAssertTrue(handler.performedActions.isEmpty)
    }

    func testSeasonWithoutWatchActionsStillRenders() {
        let handler = Handler()
        handler.availableActions = []
        let season = MediaItem(id: "s2", title: "Season 2", kind: .season)
        let host = UIHostingController(rootView:
            SeasonWatchStateMenu(for: season, action: {}) {
                Text("Season 2")
            }
                .buttonStyle(PlozzSeasonTabStyle(isSelected: true))
                .mediaItemActionHandler(handler)
        )
        let size = host.sizeThatFits(in: CGSize(width: 500, height: 200))
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertFalse(handler.requestedItems.isEmpty)
        XCTAssertTrue(handler.performedActions.isEmpty)
    }
}
#endif
