#if os(tvOS)
import XCTest
import UIKit
import CoreModels
@testable import FeatureHome

/// Locks the Immersive Home's pin and hero rules: which row is pinned, which
/// title the hero stands in with before anything is focused, and how the hero's
/// backdrop steers off the picture the focused card already shows.
@MainActor
final class FocusHeroModelTests: XCTestCase {
    private func item(_ id: String) -> MediaItem {
        MediaItem(id: id, title: id, kind: .movie)
    }

    private func row(_ id: String, _ items: [String]) -> FocusHeroRow {
        FocusHeroRow(id: id, itemIDs: items, leadItem: items.first.map(item), items: items.map(item))
    }

    func testTheFirstRowStandsInUntilSomethingIsFocused() {
        let model = FocusHeroModel()
        let watchlist = row("watchlist", ["terror", "dune"])
        model.seed(from: [watchlist])
        XCTAssertEqual(model.subject?.item?.id, "terror")

        // Live Continue Watching arrives above the cached rows.
        let continueWatching = row("continue", ["tbate", "arcane"])
        model.seed(from: [continueWatching, watchlist])
        XCTAssertEqual(model.subject?.item?.id, "tbate", "Nothing focused yet, so the hero follows the new first row")
    }

    func testAFocusedRowKeepsThePinWhenARowArrivesAboveIt() {
        let model = FocusHeroModel()
        let watchlist = row("watchlist", ["terror", "dune"])
        let rows = [watchlist]
        model.seed(from: rows)
        // Focus lands on the first row: already the stand-in, but it must be recorded.
        model.activate(watchlist, in: rows)
        model.show(.item(item("dune")), in: watchlist)

        let continueWatching = row("continue", ["tbate"])
        let grown = [continueWatching, watchlist]
        model.seed(from: grown)
        XCTAssertEqual(model.resolvedActiveRowID(in: grown), "watchlist")
        XCTAssertEqual(model.subject?.item?.id, "dune", "The focused title stays in the hero")
    }

    func testRowTopsAndTheSlotComeFromCurrentRowsOnly() {
        let model = FocusHeroModel()
        let notice = row("notice", [])
        let continueWatching = row("continue", ["tbate"])
        let watchlist = row("watchlist", ["terror"])
        model.record(height: 900, for: notice.id)
        model.record(height: 406, for: continueWatching.id)
        model.record(height: 540, for: watchlist.id)

        let rows = [continueWatching, watchlist]
        XCTAssertEqual(model.top(ofRowAt: 1, in: rows, rowSpacing: 28), 434)
        let bottom = FocusHeroLayout.rowsBottom(rowSpacing: 28)
        XCTAssertEqual(
            model.slotTop(in: rows, rowSpacing: 28),
            max(FocusHeroLayout.lowestSlotTop, bottom - 406),
            "The details end above the pinned row, not a taller one elsewhere"
        )
        model.activate(watchlist, in: rows)
        XCTAssertEqual(
            model.slotTop(in: rows, rowSpacing: 28),
            max(FocusHeroLayout.lowestSlotTop, bottom - 406),
            "The details leave with the rows, not ahead of them"
        )
        model.advanceRows(to: 0.5)
        XCTAssertEqual(model.slotTop(in: rows, rowSpacing: 28), max(FocusHeroLayout.lowestSlotTop, bottom - 473))
        model.advanceRows(to: 1)
        XCTAssertEqual(model.slotTop(in: rows, rowSpacing: 28), max(FocusHeroLayout.lowestSlotTop, bottom - 540))
    }

    func testSubPointMeasurementNoiseIsIgnored() {
        let model = FocusHeroModel()
        model.record(height: 540, for: "watchlist")
        model.record(height: 540.3, for: "watchlist")
        XCTAssertEqual(model.rowHeights["watchlist"], 540)
    }

    func testNativeScrollOwnsRowMovementWithoutRestartingAnUnchangedDestination() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let controller = UIViewController()
        window.rootViewController = controller
        let viewport = ScrollRecorder(frame: window.bounds)
        viewport.contentSize = CGSize(width: 1920, height: 3000)
        controller.view.addSubview(viewport)
        let horizontal = UIScrollView()
        viewport.addSubview(horizontal)
        let position = FocusHeroNativeScrollPosition.PositionView()
        viewport.addSubview(position)
        window.isHidden = false
        defer {
            position.stop()
            window.isHidden = true
        }

        position.move(to: 340, rowID: "continue")
        XCTAssertEqual(viewport.contentOffset.y, 340)
        XCTAssertEqual(viewport.requests.last?.animated, false)
        XCTAssertFalse(viewport.isScrollEnabled)
        XCTAssertTrue(horizontal.isScrollEnabled, "Pinning must not disable native horizontal navigation.")

        position.move(to: 840, rowID: "posters")
        position.move(to: 840, rowID: "posters")
        settle(viewport, at: 840)
        if !UIAccessibility.isReduceMotionEnabled {
            XCTAssertGreaterThan(viewport.steps.count, 3, "Row changes move a frame at a time on the rows' spring.")
            XCTAssertEqual(viewport.steps, viewport.steps.sorted(), "An unchanged destination does not restart the move.")
        }

        position.move(to: 340, rowID: "continue")
        settle(viewport, at: 340)
        XCTAssertEqual(viewport.contentOffset.y, 340, "Reversals retarget the same native viewport.")
        position.move(to: 356, rowID: "continue")
        XCTAssertEqual(viewport.contentOffset.y, 356)
        XCTAssertEqual(viewport.requests.last?.animated, false, "New measurements preserve the settled anchor.")
        position.stop()
        XCTAssertTrue(viewport.isScrollEnabled, "Teardown restores the viewport's original policy.")
    }

    private func settle(_ viewport: UIScrollView, at y: CGFloat) {
        // Long enough for the spring to finish, past the last sub-pixel steps
        // the viewport rounds away.
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(viewport.contentOffset.y, y)
    }

    private final class ScrollRecorder: UIScrollView {
        var requests: [(point: CGPoint, animated: Bool)] = []
        /// Offsets set directly, as the row spring does a frame at a time.
        var steps: [CGFloat] = []

        override var contentOffset: CGPoint {
            didSet { steps.append(contentOffset.y) }
        }

        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            requests.append((contentOffset, animated))
            super.setContentOffset(contentOffset, animated: animated)
        }
    }

    func testFocusedSubjectTakesFreshRowStateWithoutAnotherFocusMove() {
        let model = FocusHeroModel()
        var episode = MediaItem(id: "episode", title: "Episode", kind: .episode)
        episode.isPlayed = true
        let initial = FocusHeroRow(id: "row", itemIDs: [episode.stablePresentationID], leadItem: episode, items: [episode])
        model.activate(initial, in: [initial])
        model.show(.item(episode), in: initial)
        episode.isPlayed = false
        let fresh = FocusHeroRow(id: "row", itemIDs: [episode.stablePresentationID], leadItem: episode, items: [episode])
        model.seed(from: [fresh])
        XCTAssertEqual(model.subject?.item?.isPlayed, false)
        XCTAssertEqual(model.activeRowID, "row")
    }

    func testSameProviderIDOnDifferentAccountsDoesNotKeepRemovedSubject() {
        let model = FocusHeroModel()
        var first = item("shared-id")
        first.sourceAccountID = "first"
        var second = first
        second.sourceAccountID = "second"
        let initial = FocusHeroRow(id: "row", itemIDs: [first.stablePresentationID], leadItem: first, items: [first])
        model.activate(initial, in: [initial])
        model.show(.item(first), in: initial)
        let fresh = FocusHeroRow(id: "row", itemIDs: [second.stablePresentationID], leadItem: second, items: [second])
        model.seed(from: [fresh])
        XCTAssertEqual(model.subject?.item?.sourceAccountID, "second")
        XCTAssertNotEqual(FocusHeroSubject.item(first).id, FocusHeroSubject.item(second).id)
    }

    func testEveryTitleGetsTheSameFilledInDetails() async {
        let metadata = FocusHeroMetadata()
        let sparse = MediaItem(id: "arcane", title: "Arcane", kind: .series)
        XCTAssertEqual(metadata.item(for: sparse).genres, [], "A title shows as it is until its details load")
        await metadata.load(sparse) { items in
            items.map { item in
                var full = item
                full.genres = ["Animation"]
                full.officialRating = "TV-14"
                return full
            }
        }
        XCTAssertEqual(metadata.item(for: sparse).genres, ["Animation"])
        XCTAssertEqual(metadata.item(for: sparse).officialRating, "TV-14")
    }

    func testAFocusThatMovesOnLoadsNothingAndCanLoadLater() async {
        let metadata = FocusHeroMetadata()
        let item = MediaItem(id: "dune", title: "Dune", kind: .movie)
        let passing = Task { @MainActor in
            await metadata.load(item) { items in
                items.map { var full = $0; full.genres = ["Drama"]; return full }
            }
        }
        passing.cancel()
        await passing.value
        XCTAssertNil(metadata.item(for: item).genres.first, "A card passed on the way isn't fetched")
        await metadata.load(item) { items in
            items.map { var full = $0; full.genres = ["Drama"]; return full }
        }
        XCTAssertEqual(metadata.item(for: item).genres, ["Drama"])
    }

    func testTheHeroSkipsThePictureTheFocusedCardShows() {
        let main = ArtworkReference.remote(URL(string: "https://example.com/main.jpg")!)
        let second = ArtworkReference.remote(URL(string: "https://example.com/second.jpg")!)
        let item = MediaItem(
            id: "arcane",
            title: "Arcane",
            kind: .series,
            artworkSelections: [ArtworkSelection(placement: .homeHero, references: [main, second])]
        )
        XCTAssertEqual(HomeHeroArtwork.backdropReferences(for: item, avoiding: [main]).prefix(2), [second, main])
        XCTAssertEqual(
            HomeHeroArtwork.backdropReferences(for: item, avoiding: []).prefix(2), [main, second],
            "A poster row's card shows no backdrop, so the hero keeps its first choice"
        )

        let single = MediaItem(
            id: "solo",
            title: "Solo",
            kind: .series,
            artworkSelections: [ArtworkSelection(placement: .homeHero, references: [main])]
        )
        XCTAssertEqual(
            HomeHeroArtwork.backdropReferences(for: single, avoiding: [main]).first, main,
            "With only one picture the hero keeps it"
        )
    }
}
#endif
