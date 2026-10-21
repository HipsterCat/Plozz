#if DEBUG && canImport(SwiftUI) && canImport(UIKit)
import CoreModels
import FeatureLiveTVCore
import SwiftUI
import UIKit
import XCTest
@testable import FeatureLiveTV

@MainActor
final class LiveTVChannelOrganizationViewTests: XCTestCase {
    func testManagementAndHiddenPagesDoNotMutateChoicesOnAppearance() {
        let store = OrganizationViewStore()
        let channel = LiveTVPrototypeChannel(
            id: "unknown", number: 1, name: "Untagged channel", category: "News",
            symbol: "tv", accent: 0, source: .iptv, tagline: "", configuredSourceID: "source"
        )
        let model = LiveTVPrototypeModel(channels: [channel], preferencesStore: store)
        let imports = LiveTVPrototypeImportModel(configuration: .empty, loader: LiveTVSourceLoader())
        let saved = store.value
        for width in [390.0, 1_024.0, 1_920.0] {
            let management = UIHostingController(rootView: NavigationStack {
                LiveTVChannelOrganizationView(model: model, imports: imports, canMutate: { false })
            })
            management.loadViewIfNeeded()
            management.view.frame = CGRect(x: 0, y: 0, width: width, height: 844)
            management.view.layoutIfNeeded()
            let hidden = UIHostingController(rootView: NavigationStack {
                LiveTVHiddenChannelManagementView(model: model, canMutate: { false })
            })
            hidden.loadViewIfNeeded()
            hidden.view.frame = management.view.frame
            hidden.view.layoutIfNeeded()
        }
        XCTAssertEqual(store.value, saved)
        XCTAssertEqual(store.saves, 0)
        XCTAssertEqual(model.hiddenChannelEntries.map(\.id), ["unknown"])
    }
}

private final class OrganizationViewStore: LiveTVPreferencesStoring, @unchecked Sendable {
    var value: LiveTVPreferences = {
        var organization = LiveTVChannelOrganization()
        organization.region = .init(isEnabled: true, languages: ["en"])
        return .init(organization: organization)
    }()
    var saves = 0
    func load() throws -> LiveTVPreferences { value }
    func save(_ preferences: LiveTVPreferences) throws { value = preferences; saves += 1 }
}
#endif
