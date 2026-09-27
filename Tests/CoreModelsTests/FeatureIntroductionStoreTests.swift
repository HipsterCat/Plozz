import XCTest
@testable import CoreModels

final class FeatureIntroductionStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "FeatureIntroductionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testNewIntroductionNeedsPresentation() {
        let store = FeatureIntroductionStore(defaults: makeDefaults())

        XCTAssertTrue(store.needsPresentation(.navigationStyles))
    }

    func testCompletedIntroductionDoesNotPresentAgain() {
        let store = FeatureIntroductionStore(defaults: makeDefaults())

        store.markCompleted(.navigationStyles)

        XCTAssertFalse(store.needsPresentation(.navigationStyles))
    }

    func testHomeLayoutIsOfferedOnceEvenWhenNavigationWasAlreadyCompleted() {
        let defaults = makeDefaults()
        let store = FeatureIntroductionStore(defaults: defaults)
        store.markCompleted(.navigationStyles)

        XCTAssertTrue(store.needsPresentation(.homeLayout))
        store.markCompleted(.homeLayout)

        let restored = FeatureIntroductionStore(defaults: defaults)
        XCTAssertFalse(restored.needsPresentation(.homeLayout))
        XCTAssertFalse(restored.needsPresentation(.navigationStyles))
    }

    func testCompletingHomeLayoutDoesNotCompleteNavigation() {
        let store = FeatureIntroductionStore(defaults: makeDefaults())
        store.markCompleted(.homeLayout)

        XCTAssertFalse(store.needsPresentation(.homeLayout))
        XCTAssertTrue(store.needsPresentation(.navigationStyles))
    }

    func testHigherVersionPresentsAgain() {
        let store = FeatureIntroductionStore(defaults: makeDefaults())
        let first = FeatureIntroduction(id: "example", version: 1)
        let second = FeatureIntroduction(id: "example", version: 2)

        store.markCompleted(first)

        XCTAssertTrue(store.needsPresentation(second))
    }

    func testCompletingOlderVersionDoesNotMoveStoredVersionBackward() {
        let store = FeatureIntroductionStore(defaults: makeDefaults())
        let first = FeatureIntroduction(id: "example", version: 1)
        let second = FeatureIntroduction(id: "example", version: 2)

        store.markCompleted(second)
        store.markCompleted(first)

        XCTAssertFalse(store.needsPresentation(second))
    }
}

final class ProfileAppearanceSetupStoreTests: XCTestCase {
    private func makeStore() -> ProfileAppearanceSetupStore {
        let suite = "ProfileAppearanceSetupStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ProfileAppearanceSetupStore(defaults: defaults)
    }

    func testPendingStateIsProfileSpecificAndDurable() {
        let store = makeStore()

        store.markPending(profileID: "new-profile")

        XCTAssertTrue(store.isPending(profileID: "new-profile"))
        XCTAssertFalse(store.isPending(profileID: "existing-profile"))

        store.markCompleted(profileID: "new-profile")
        XCTAssertFalse(store.isPending(profileID: "new-profile"))
    }
}
