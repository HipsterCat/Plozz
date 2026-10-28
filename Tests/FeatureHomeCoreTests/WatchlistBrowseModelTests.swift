import CoreModels
import FeatureHomeCore
import XCTest

@MainActor
final class WatchlistBrowseModelTests: XCTestCase {
    func testChoicesSurviveRemountWithoutLeakingIntoAnotherProfile() throws {
        let suite = "WatchlistBrowseModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WatchlistBrowsePreferencesStore(namespace: "first", defaults: defaults)
        let model = WatchlistBrowseModel(store: store)
        model.preferences.filter = .shows
        model.preferences.sort = .init(field: .releaseDate, direction: .descending)
        XCTAssertEqual(WatchlistBrowseModel(store: store).preferences, model.preferences)
        let other = WatchlistBrowseModel(store: .init(namespace: "second", defaults: defaults))
        XCTAssertEqual(other.preferences, .default)
    }
}
