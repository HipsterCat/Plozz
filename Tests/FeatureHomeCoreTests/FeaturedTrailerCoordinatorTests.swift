#if canImport(AVFoundation)
import CoreModels
import XCTest
@testable import FeatureHomeCore

@MainActor
final class FeaturedTrailerCoordinatorTests: XCTestCase {
    func testDeinitializationReleasesPendingReservation() async {
        let controller = HeroTrailerController()
        var coordinator: FeaturedTrailerCoordinator? = .init(settleDelay: .seconds(60))
        coordinator?.update(
            rowID: UUID(), item: .init(id: "movie", title: "Movie", kind: .movie),
            scope: ObjectIdentifier(controller), priority: 0, muted: true,
            controller: controller, resolve: { _ in nil }
        )
        XCTAssertTrue(controller.isFeaturedReserved)
        coordinator = nil
        let released = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !controller.isFeaturedReserved }, object: nil
        )
        await fulfillment(of: [released], timeout: 2)
        XCTAssertFalse(controller.isFeaturedReserved)
    }

    func testOnlyNearestVisibleRowOwnsPlayerAndRemovalReturnsToRemainingRow() {
        let coordinator = FeaturedTrailerCoordinator(settleDelay: .seconds(60))
        let controller = HeroTrailerController()
        defer { coordinator.stop() }
        let first = UUID()
        let second = UUID()
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie)
        let scope = ObjectIdentifier(controller)
        coordinator.update(rowID: first, item: item, scope: scope, priority: 4, muted: true,
                           controller: controller, resolve: { _ in nil })
        let firstOwner = controller.featuredOwnerID
        coordinator.update(rowID: second, item: item, scope: scope, priority: 8, muted: true,
                           controller: controller, resolve: { _ in nil })
        XCTAssertEqual(coordinator.activeRowID, first)
        XCTAssertEqual(controller.featuredOwnerID, firstOwner)
        coordinator.update(rowID: second, item: item, scope: scope, priority: 1, muted: false,
                           controller: controller, resolve: { _ in nil })
        XCTAssertEqual(coordinator.activeRowID, second)
        XCTAssertNotEqual(controller.featuredOwnerID, firstOwner)
        XCTAssertFalse(controller.isMuted)
        coordinator.withdraw(rowID: second)
        XCTAssertEqual(coordinator.activeRowID, first)
        XCTAssertTrue(controller.isMuted)
        coordinator.withdraw(rowID: first)
        XCTAssertNil(coordinator.activeRowID)
        XCTAssertFalse(controller.isFeaturedReserved)
    }

    func testChangingScopeCancelsResolutionEvenWhenProviderItemIDMatches() async throws {
        let coordinator = FeaturedTrailerCoordinator(settleDelay: .zero)
        let controller = HeroTrailerController()
        defer { coordinator.stop() }
        let rowID = UUID()
        let firstScope = NSObject()
        let secondScope = NSObject()
        let gate = ResolutionGate()
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie).taggingSource("account")
        coordinator.update(
            rowID: rowID, item: item, scope: ObjectIdentifier(firstScope), priority: 0,
            muted: true, controller: controller,
            resolve: { _ in await gate.resolve() }
        )
        for _ in 0..<100 {
            if await gate.started { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let started = await gate.started
        XCTAssertTrue(started)
        let oldOwner = controller.featuredOwnerID
        coordinator.update(
            rowID: rowID, item: item, scope: ObjectIdentifier(secondScope), priority: 0,
            muted: true, controller: controller, resolve: { _ in nil }
        )
        XCTAssertNotEqual(oldOwner, controller.featuredOwnerID)
        await gate.finish()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(controller.player.currentItem, "A stale signed URL must never reach the player.")
        XCTAssertEqual(coordinator.activeItemID, item.stablePresentationID)
    }
}

private actor ResolutionGate {
    private var continuation: CheckedContinuation<HeroTrailerSource?, Never>?
    var started: Bool { continuation != nil }

    func resolve() async -> HeroTrailerSource? {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume(returning: HeroTrailerSource(
            ownerItemID: "movie", trailerItemID: "trailer",
            url: URL(fileURLWithPath: "/unused-stale-trailer.mov"), duration: 10
        ))
        continuation = nil
    }
}
#endif
