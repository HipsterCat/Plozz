import XCTest
@testable import CoreModels

final class HeroTextSizeTests: XCTestCase {
    func testDescriptionAndScrimGrowWithoutChangingDefaultsOrShrinkingCoverage() {
        for base in [2, 3] {
            for size in HeroTextSize.allSizes {
                XCTAssertEqual(size.descriptionLineLimit(base: base), base + (size.rawValue > 0 ? 1 : 0))
                for logo in HeroLogoSize.allSizes {
                    let coverage = size.scrimHeightScale(logoSize: logo, descriptionLines: base)
                    XCTAssertGreaterThanOrEqual(coverage, 1)
                    XCTAssertGreaterThanOrEqual(coverage, logo.scale)
                    XCTAssertGreaterThanOrEqual(
                        coverage, size.scale * Double(size.descriptionLineLimit(base: base)) / Double(base)
                    )
                }
            }
        }
        XCTAssertEqual(HeroTextSize.default.scrimHeightScale(logoSize: .default), 1)
        XCTAssertEqual(HeroTextSize(rawValue: -5).scrimHeightScale(logoSize: HeroLogoSize(rawValue: -10)), 1)
        XCTAssertEqual(HeroTextSize(rawValue: 5).scrimHeightScale(logoSize: HeroLogoSize(rawValue: 10)),
                       HeroTextSize(rawValue: 5).scale * 4 / 3, accuracy: 0.0001)
    }

    func testSizesAreBoundedWithACenteredDefaultAndRoundTrip() throws {
        XCTAssertEqual(HeroTextSize.default.scale, 1)
        XCTAssertEqual(HeroTextSize.default.position, 5)
        XCTAssertEqual(HeroTextSize.allSizes.count, 11)
        XCTAssertEqual(HeroTextSize(rawValue: .min).scale, 0.75)
        #if os(tvOS)
        XCTAssertEqual(HeroTextSize(rawValue: .max).scale, 1.5)
        #else
        XCTAssertEqual(HeroTextSize(rawValue: .max).scale, 1.25)
        #endif
        for (index, size) in HeroTextSize.allSizes.enumerated() {
            XCTAssertEqual(size.position, index)
            #if os(tvOS)
            let increment = size.rawValue > 0 ? 0.1 : 0.05
            #else
            let increment = 0.05
            #endif
            XCTAssertEqual(size.scale, 1 + Double(size.rawValue) * increment, accuracy: 0.0001)
            XCTAssertEqual(try JSONDecoder().decode(HeroTextSize.self, from: JSONEncoder().encode(size)), size)
        }
        XCTAssertEqual(try JSONDecoder().decode(HeroTextSize.self, from: Data("100".utf8)).rawValue, 5)
        XCTAssertThrowsError(try JSONDecoder().decode(HeroTextSize.self, from: Data("\"invalid\"".utf8)))
    }

    func testOlderSettingsPreserveTypographyAndExistingChoices() throws {
        let home = try JSONDecoder().decode(
            HeroSettings.self, from: Data(#"{"logoSize":4,"showcaseLogoSize":-8,"maxItems":3}"#.utf8)
        )
        XCTAssertEqual(home.textSize, .default)
        XCTAssertEqual(home.showcaseTextSize, .default)
        XCTAssertEqual(home.logoSize.rawValue, 4)
        XCTAssertEqual(home.showcaseLogoSize.rawValue, -8)
        XCTAssertEqual(home.maxItems, 3)
        let library = try JSONDecoder().decode(
            LibraryPresentationSettings.self, from: Data(#"{"logoSize":8}"#.utf8)
        )
        XCTAssertEqual(library.textSize, .default)
        XCTAssertEqual(library.logoSize.rawValue, 8)
        let detail = try JSONDecoder().decode(DetailPageSettings.self, from: Data(#"{"logoSize":6}"#.utf8))
        XCTAssertEqual(detail.textSize, .default)
        XCTAssertEqual(detail.logoSize.rawValue, 6)
    }

    @MainActor
    func testSurfaceAndProfileIsolationPersistThroughTransfer() throws {
        let suite = "HeroTextSizeTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let home = HeroSettingsModel(store: HeroSettingsStore(defaults: defaults))
        let library = LibraryPresentationSettingsModel(store: LibraryPresentationSettingsStore(defaults: defaults))
        let detail = DetailPageSettingsModel(store: DetailPageSettingsStore(defaults: defaults))
        home.settings.textSize = HeroTextSize(rawValue: -3)
        home.settings.showcaseTextSize = HeroTextSize(rawValue: 5)
        library.settings.textSize = HeroTextSize(rawValue: 2)
        detail.settings.textSize = HeroTextSize(rawValue: 4)
        XCTAssertEqual(HeroSettingsStore(defaults: defaults).load(), home.settings)
        XCTAssertEqual(LibraryPresentationSettingsStore(defaults: defaults).load(), library.settings)
        XCTAssertEqual(DetailPageSettingsStore(defaults: defaults).load(), detail.settings)
        XCTAssertEqual(try JSONDecoder().decode(
            DetailPageSettings.self, from: JSONEncoder().encode(detail.settings)
        ), detail.settings)
        XCTAssertEqual(home.settings.logoSize, .default)
        XCTAssertEqual(home.settings.showcaseLogoSize, .default)
        XCTAssertEqual(library.settings.logoSize, .default)
        XCTAssertEqual(detail.settings.logoSize, .default)
        XCTAssertEqual(library.settings.showcaseSettings.showcaseTextSize, library.settings.textSize)
        XCTAssertEqual(library.settings.showcaseSettings.textSize, .default)
        XCTAssertEqual(HeroSettingsStore(defaults: defaults, namespace: "other").load().textSize, .default)
        XCTAssertEqual(LibraryPresentationSettingsStore(defaults: defaults, namespace: "other").load().textSize, .default)
        XCTAssertEqual(DetailPageSettingsStore(defaults: defaults, namespace: "other").load().textSize, .default)
        let snapshot = ProfileSettingsTransfer.capture(namespace: nil, defaults: defaults)
        ProfileSettingsTransfer.apply(snapshot, namespace: "other", defaults: defaults)
        XCTAssertEqual(HeroSettingsStore(defaults: defaults, namespace: "other").load(), home.settings)
        XCTAssertEqual(LibraryPresentationSettingsStore(defaults: defaults, namespace: "other").load(), library.settings)
        XCTAssertEqual(DetailPageSettingsStore(defaults: defaults, namespace: "other").load(), detail.settings)
        home.settings.textSize = .default
        XCTAssertEqual(home.settings.showcaseTextSize.rawValue, 5)
        XCTAssertEqual(library.settings.textSize.rawValue, 2)
        XCTAssertEqual(detail.settings.textSize.rawValue, 4)
        XCTAssertEqual(HeroSettingsStore(defaults: defaults, namespace: "other").load().textSize.rawValue, -3)
    }
}
