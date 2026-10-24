import Foundation
import XCTest
@testable import CoreModels

final class ContentRatingPresentationTests: XCTestCase {
    func testFrenchWarningIsNotLostOrConvertedToAnAmericanRating() {
        let raw = "FR/Tous publics avec avertissement"
        let rating = ContentRatingPresentation(raw)
        XCTAssertEqual(rating.label, "TP")
        XCTAssertTrue(rating.hasWarning)
        XCTAssertEqual(rating.original, raw)
        XCTAssertEqual(rating.text, "TP !")
        XCTAssertFalse(ContentRatingPresentation("FR/Tous publics").hasWarning)
        XCTAssertEqual(ContentRatingPresentation("FR/Interdit aux moins de 12 ans").label, "-12")
        let restricted = ContentRatingPresentation("FR/Interdit aux moins de 16 ans avec avertissement")
        XCTAssertEqual(restricted.label, "-16")
        XCTAssertTrue(restricted.hasWarning)
    }

    func testRecognizedDescriptionsUseTheirOwnRegionalCodes() {
        let examples: [(String, String)] = [
            ("FR/Tous publics", "TP"),
            ("DE/Freigegeben ab 12 Jahren", "FSK 12"),
            ("DE/Ohne Altersbeschränkung", "FSK 0"),
            ("DE/Keine Jugendfreigabe", "FSK 18"),
            ("ES/Apta para todos los públicos", "TP"),
            ("ES/No recomendada para menores de 16 años", "16"),
            ("AR/Apta para todo público", "ATP"),
            ("CL/Todo espectador", "TE"),
            ("BR/Livre", "L"),
            ("BR/Não recomendado para menores de 14 anos", "14"),
            ("IT/Vietato ai minori di 14 anni", "VM14"),
            ("IT/Per tutti", "T"),
            ("NL/Alle leeftijden", "AL"),
            ("DK/Tilladt for alle", "A"),
            ("FI/Sallittu", "S"),
            ("SE/Barntillåten", "Btl"),
            ("SE/Från 11 år", "11"),
            ("NO/12 år", "12"),
            ("PL/Bez ograniczeń wiekowych", "b.o."),
            ("PL/Od 16 lat", "16"),
            ("ID/Semua umur", "SU"),
            ("CA/Visa général", "G"),
            ("CA/13 ans et plus", "13+")
        ]
        for (source, expected) in examples {
            XCTAssertEqual(ContentRatingPresentation(source).label, expected, source)
            XCTAssertFalse(ContentRatingPresentation(source).hasWarning, source)
        }
    }

    func testExistingCodesAndScriptsStayInTheirOriginalClassificationSystem() {
        let examples: [(String, String)] = [
            ("US/PG-13", "PG-13"), ("US/R", "R"), ("US/TV-MA-LSV", "TV-MA-LSV"),
            ("GB/12A", "12A"), ("UK/15", "15"), ("IE/15A", "15A"),
            ("AU/MA 15+", "MA 15+"), ("NZ/RP13", "RP13"), ("CA/18A", "18A"),
            ("DE/FSK-16", "FSK 16"), ("FR/-12", "-12"), ("ES/7/i/fig", "7/i/fig"),
            ("IN/U/A 13+", "U/A 13+"), ("PT/M/12", "M/12"),
            ("BE/AL/TOUS", "AL/TOUS"), ("NL/AL", "AL"),
            ("JP/PG12", "PG12"), ("JP/R18+", "R18+"), ("KR/전체관람가", "전체관람가"),
            ("TW/輔12級", "輔12級"), ("HK/IIB", "IIB"),
            ("KZ/Б14", "Б14"), ("RU/16+", "16+"), ("UA/12+", "12+"),
            ("MX/B-15", "B-15"), ("SG/NC16", "NC16"), ("PH/R-13", "R-13"),
            ("ZA/10-12PG", "10-12PG"), ("TH/20", "20"), ("TR/13A", "13A"),
            ("GR/K-12", "K-12"), ("LT/N-13", "N-13"), ("RO/AP-12", "AP-12"),
            ("CZ/15+", "15+"), ("SK/12", "12"), ("BG/C+", "C+"), ("HU/KN", "KN"),
            ("AR/R-17", "R-17"), ("BR/A12", "A12"), ("CO/T", "T"),
            ("SE/15+", "15+"), ("FI/K-12", "K-12"), ("DK/7", "7"), ("NO/A", "A")
        ]
        for (source, expected) in examples {
            XCTAssertEqual(ContentRatingPresentation(source).label, expected, source)
        }
    }

    func testFormattingDoesNotRequireAnEnglishOrFrenchAppLocale() {
        for source in [
            " FR / TOUS PUBLICS AVEC AVERTISSEMENT \n",
            "fra/Tous\tpublics  avec\navertissement",
            "Tous publics avec avertissement"
        ] {
            XCTAssertEqual(ContentRatingPresentation(source).label, "TP")
            XCTAssertTrue(ContentRatingPresentation(source).hasWarning)
            XCTAssertEqual(ContentRatingPresentation(source).original, source)
        }
        XCTAssertEqual(ContentRatingPresentation("DEU/Ohne Altersbeschra\u{308}nkung").label, "FSK 0")
        XCTAssertEqual(ContentRatingPresentation("GBR/12A").label, "12A")
    }

    func testUnknownAndAmbiguousValuesAreNotGuessedFromAgeNumbersOrLanguage() {
        for source in [
            "U/A", "M/12", "AL/TOUS", "N/A", "FSK/12", "XX/PG-13", "FR/",
            "No rating supplied", "For children aged 12 only with an adult",
            "Tous publics avec avertissement supplémentaire", "TP (warning: flashing images)",
            "Public Averti", "Infoprogramm", "Approved", "Exempt"
        ] {
            XCTAssertEqual(ContentRatingPresentation(source).label, source, source)
        }
        XCTAssertEqual(ContentRatingPresentation("CA/Tous publics").label, "Tous publics")
        XCTAssertEqual(ContentRatingPresentation("FR/13 ans et plus").label, "13 ans et plus")
        XCTAssertEqual(ContentRatingPresentation("SE/Tillåten").label, "Tillåten")
        XCTAssertEqual(ContentRatingPresentation("JP/Restricted Screening").label, "Restricted Screening")
        XCTAssertEqual(ContentRatingPresentation("TR/Genel İzleyici Kitlesi").label, "Genel İzleyici Kitlesi")
        XCTAssertEqual(ContentRatingPresentation("IT/Vietato ai minori di 12 anni").label, "Vietato ai minori di 12 anni")
        XCTAssertEqual(ContentRatingPresentation("SE/12 år").label, "12 år")
    }

    func testRawMetadataAndAccessibilitySurvivePresentationAndSerialization() throws {
        let raw = "FR/Tous publics avec avertissement"
        let item = MediaItem(id: "film", title: "Fixture", kind: .movie, officialRating: raw)
        let badge = try XCTUnwrap(item.ratingBadge)
        XCTAssertEqual(ContentRatingPresentation(badge.label).label, "TP")
        XCTAssertEqual(badge.accessibilityText, raw)
        XCTAssertEqual(item.officialRating, raw)
        XCTAssertEqual(try JSONDecoder().decode(
            MediaItem.self, from: JSONEncoder().encode(item)
        ).officialRating, raw)
        for empty in [nil, "", " \n"] as [String?] {
            XCTAssertNil(MediaItem(id: "film", title: "Fixture", kind: .movie, officialRating: empty).ratingBadge)
        }
    }
}

@MainActor
final class ContentRatingSettingsTests: XCTestCase {
    func testDefaultsPersistenceProfileIsolationAndTransfer() throws {
        let suite = "ContentRatingSettingsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let primary = ContentRatingSettingsStore(defaults: defaults)
        let first = ContentRatingSettingsStore(defaults: defaults, namespace: "first")
        let second = ContentRatingSettingsStore(defaults: defaults, namespace: "second")
        XCTAssertTrue(primary.load())
        XCTAssertTrue(first.load())
        let model = ContentRatingSettingsModel(store: first)
        model.showsRatings = false
        XCTAssertFalse(ContentRatingSettingsModel(store: first).showsRatings)
        XCTAssertTrue(primary.load())
        XCTAssertTrue(second.load())
        let snapshot = ProfileSettingsTransfer.capture(namespace: "first", defaults: defaults)
        XCTAssertNotNil(snapshot[ContentRatingSettingsStore.storageKey])
        ProfileSettingsTransfer.apply(snapshot, namespace: "second", defaults: defaults)
        XCTAssertFalse(second.load())
        ProfileSettingsTransfer.removeOne(
            baseKey: ContentRatingSettingsStore.storageKey, namespace: "second", defaults: defaults
        )
        XCTAssertTrue(second.load())
        XCTAssertFalse(first.load())
    }
}
