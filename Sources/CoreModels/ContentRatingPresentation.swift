import Foundation

/// Display aliases, not age equivalences. Never use this value for parental controls.
public struct ContentRatingPresentation: Equatable, Sendable {
    public let original: String
    public let label: String  // l10n:content - regional classification code or original provider content
    public let hasWarning: Bool

    public init(_ rating: String) {
        original = rating
        let (region, value) = Self.splitRegion(rating.trimmingCharacters(in: .whitespacesAndNewlines))
        let key = Self.key(value)
        if let alias = Self.aliases[key],
           region.map(alias.regions.contains) ?? true {
            label = alias.label
            hasWarning = alias.hasWarning
        } else {
            label = value
            hasWarning = false
        }
    }

    /// Text-only surfaces retain the warning independently of the age code.
    public var text: String {  // l10n:content - classification code plus a warning marker
        hasWarning ? "\(label) !" : label
    }

    private struct Alias {
        let label: String
        let regions: Set<String>
        var hasWarning = false
    }

    private static func key(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2212}", with: "-")
    }

    private static func splitRegion(_ value: String) -> (String?, String) {
        // AL/TOUS is itself a Belgian classification; U/A and M/12 are not country prefixes.
        guard key(value) != "al/tous", let separator = value.firstIndex(of: "/") else {
            return (nil, value)
        }
        let prefix = value[..<separator].trimmingCharacters(in: .whitespaces).uppercased()
        guard let region = regions[prefix] else { return (nil, value) }
        let remainder = value[value.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return (nil, value) }
        return (region, remainder)
    }

    private static let regions: [String: String] = {
        let pairs = [
            ("AR", "ARG"), ("AU", "AUS"), ("AT", "AUT"), ("BE", "BEL"), ("BG", "BGR"),
            ("BR", "BRA"), ("CA", "CAN"), ("CH", "CHE"), ("CL", "CHL"), ("CN", "CHN"),
            ("CO", "COL"), ("CZ", "CZE"), ("DE", "DEU"), ("DK", "DNK"), ("EE", "EST"),
            ("ES", "ESP"), ("FI", "FIN"), ("FR", "FRA"), ("GB", "GBR"), ("GR", "GRC"),
            ("HK", "HKG"), ("HR", "HRV"), ("HU", "HUN"), ("ID", "IDN"), ("IE", "IRL"),
            ("IL", "ISR"), ("IN", "IND"), ("IS", "ISL"), ("IT", "ITA"), ("JP", "JPN"),
            ("KR", "KOR"), ("KZ", "KAZ"), ("LT", "LTU"), ("LV", "LVA"), ("MX", "MEX"),
            ("MY", "MYS"), ("NL", "NLD"), ("NO", "NOR"), ("NZ", "NZL"), ("PH", "PHL"),
            ("PL", "POL"), ("PT", "PRT"), ("RO", "ROU"), ("RS", "SRB"), ("RU", "RUS"),
            ("SE", "SWE"), ("SG", "SGP"), ("SK", "SVK"), ("TH", "THA"), ("TR", "TUR"),
            ("TW", "TWN"), ("UA", "UKR"), ("US", "USA"), ("ZA", "ZAF")
        ]
        var result = Dictionary(uniqueKeysWithValues: pairs.flatMap { [($0.0, $0.0), ($0.1, $0.0)] })
        result["UK"] = "GB"
        return result
    }()

    private static let aliases: [String: Alias] = {
        var result: [String: Alias] = [:]
        func add(_ label: String, regions: Set<String>, names: [String], warning: Bool = false) {
            for name in names {
                result[key(name)] = Alias(label: label, regions: regions, hasWarning: warning)
            }
        }

        add("TP", regions: ["FR"], names: ["Tous publics", "Tout public"])
        add("TP", regions: ["FR"], names: [
            "Tous publics avec avertissement", "Tout public avec avertissement",
            "TP avec avertissement", "Tous publics (avec avertissement)",
            "Tous publics - avec avertissement", "Tous publics - avertissement"
        ], warning: true)
        for age in [10, 12, 16, 18] {
            let names = ["Interdit aux moins de \(age) ans", "Interdit aux mineurs de moins de \(age) ans"]
            add("-\(age)", regions: ["FR"], names: names)
            add("-\(age)", regions: ["FR"], names:
                (names + ["-\(age)", "\(age)"]).map { "\($0) avec avertissement" },
                warning: true)
        }
        for age in [0, 6, 12, 16, 18] {
            add("FSK \(age)", regions: ["DE"], names: [
                "FSK\(age)", "FSK-\(age)", "FSK \(age)", "FSK ab \(age)",
                "FSK ab \(age) freigegeben", "Freigegeben ab \(age) Jahren", "ab \(age)"
            ])
        }
        add("FSK 0", regions: ["DE"], names: ["Ohne Altersbeschränkung"])
        add("FSK 18", regions: ["DE"], names: ["Keine Jugendfreigabe"])
        add("TP", regions: ["ES"], names: ["Apta para todos los públicos", "Apto para todos los públicos"])
        for age in [7, 12, 13, 16, 18] {
            add("\(age)", regions: ["ES"], names: ["No recomendada para menores de \(age) años"])
        }
        add("ATP", regions: ["AR"], names: ["Apta para todo público", "Apto para todo público"])
        add("TE", regions: ["CL"], names: ["Todo espectador"])
        add("L", regions: ["BR"], names: ["Livre", "Livre para todos os públicos"])
        for age in [6, 10, 12, 14, 16, 18] {
            add("\(age)", regions: ["BR"], names: [
                "Não recomendado para menores de \(age) anos",
                "Não recomendada para menores de \(age) anos"
            ])
        }
        add("T", regions: ["IT"], names: ["Per tutti"])
        for age in [14, 18] {
            add("VM\(age)", regions: ["IT"], names: [
                "Vietato ai minori di \(age) anni", "VM \(age)", "VM-\(age)"
            ])
        }
        add("AL", regions: ["NL", "BE"], names: ["Alle leeftijden"])
        add("A", regions: ["DK"], names: ["Tilladt for alle"])
        add("S", regions: ["FI"], names: ["Sallittu"])
        add("Btl", regions: ["SE"], names: ["Barntillåten"])
        for age in [7, 11, 15] {
            add("\(age)", regions: ["SE"], names: ["Från \(age) år"])
        }
        for age in [6, 7, 9, 11, 12, 15, 18] {
            add("\(age)", regions: [7, 11, 15].contains(age) ? ["NO", "SE"] : ["NO"], names: ["\(age) år"])
        }
        add("b.o.", regions: ["PL"], names: ["Bez ograniczeń wiekowych", "Bez ograniczeń"])
        for age in [7, 12, 16, 18] {
            add("\(age)", regions: ["PL"], names: ["Od \(age) lat"])
        }
        add("SU", regions: ["ID"], names: ["Semua umur"])
        add("G", regions: ["CA"], names: ["Visa général"])
        for age in [13, 16, 18] {
            add("\(age)+", regions: ["CA"], names: ["\(age) ans et plus"])
        }
        return result
    }()
}
