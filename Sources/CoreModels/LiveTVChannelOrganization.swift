import Foundation

public struct LiveTVCategoryRule: Codable, Equatable, Identifiable, Sendable {
    public enum Visibility: String, Codable, CaseIterable, Sendable {
        case automatic, shown, hidden
    }

    public let sourceID: String?
    public let name: String
    public var visibility: Visibility
    public var isFavorite: Bool
    public var id: String { Self.identifier(sourceID: sourceID, name: name) }
    public var isDefault: Bool { visibility == .automatic && !isFavorite }

    public init(sourceID: String?, name: String, visibility: Visibility = .automatic, isFavorite: Bool = false) {
        self.sourceID = sourceID
        self.name = name
        self.visibility = visibility
        self.isFavorite = isFavorite
    }

    public static func identifier(sourceID: String?, name: String) -> String {
        LiveTVChannelHealthIdentity.digest(["category-v1", sourceID ?? "", LiveTVRegionMetadata.normalized(name)])
    }
}

public struct LiveTVRegionalFilter: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var countries: Set<String>
    public var languages: Set<String>

    public init(isEnabled: Bool = false, countries: Set<String> = [], languages: Set<String> = []) {
        self.isEnabled = isEnabled
        self.countries = Set(countries.map(LiveTVRegionMetadata.country))
        self.languages = Set(languages.map(LiveTVRegionMetadata.language))
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, countries, languages }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try values.decode(Bool.self, forKey: .isEnabled),
            countries: try values.decode(Set<String>.self, forKey: .countries),
            languages: try values.decode(Set<String>.self, forKey: .languages)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(isEnabled, forKey: .isEnabled)
        try values.encode(countries.sorted(), forKey: .countries)
        try values.encode(languages.sorted(), forKey: .languages)
    }
}

/// Provider metadata only; category labels are never guessed to be country or language tags.
public struct LiveTVChannelOrganizationMetadata: Codable, Equatable, Sendable {
    public let sourceID: String?
    public let categories: [String]
    public let countries: [String]
    public let languages: [String]

    public init(sourceID: String?, categories: [String], countries: [String], languages: [String]) {
        self.sourceID = sourceID
        self.categories = categories
        self.countries = countries
        self.languages = languages
    }
}

public enum LiveTVChannelHiddenReason: Equatable, Sendable {
    case channel, category, region, missingMetadata, scan
}

/// Profile choices, separate from catalog membership and individual favorites/hiding.
public struct LiveTVChannelOrganization: Codable, Equatable, Sendable {
    public var categories: [String: LiveTVCategoryRule] = [:]
    public var region = LiveTVRegionalFilter()
    public var shownChannelIDs: Set<String> = []
    public var excludedFavoriteIDs: Set<String> = []

    public init() {}

    public mutating func setCategory(_ rule: LiveTVCategoryRule) {
        categories[rule.id] = rule.isDefault ? nil : rule
    }

    public var hasVisibilityRules: Bool {
        region.isEnabled || categories.values.contains { $0.visibility != .automatic }
    }

    public func resettingVisibility() -> Self {
        var result = self
        result.region.isEnabled = false
        for var rule in categories.values {
            rule.visibility = .automatic
            result.setCategory(rule)
        }
        result.shownChannelIDs = []
        return result
    }

    public func hiddenReason(
        channelID: String, metadata: LiveTVChannelOrganizationMetadata, categoryIDs: [String]? = nil
    ) -> LiveTVChannelHiddenReason? {
        guard !shownChannelIDs.contains(channelID) else { return nil }
        var explicitlyShown = false
        let ids = categoryIDs ?? metadata.categories.map {
            LiveTVCategoryRule.identifier(sourceID: metadata.sourceID, name: $0)
        }
        for id in ids {
            let rule = categories[id]
            if rule?.visibility == .hidden { return .category }
            if rule?.visibility == .shown { explicitlyShown = true }
        }
        guard region.isEnabled, !explicitlyShown else { return nil }
        if metadata.countries.contains(where: { region.countries.contains(LiveTVRegionMetadata.country($0)) })
            || metadata.languages.contains(where: { region.languages.contains(LiveTVRegionMetadata.language($0)) }) {
            return nil
        }
        return metadata.countries.isEmpty && metadata.languages.isEmpty ? .missingMetadata : .region
    }

    public func isCategoryFavorite(
        channelID: String, metadata: LiveTVChannelOrganizationMetadata, categoryIDs: [String]? = nil
    ) -> Bool {
        guard !excludedFavoriteIDs.contains(channelID), !categories.isEmpty else { return false }
        let ids = categoryIDs ?? metadata.categories.map {
            LiveTVCategoryRule.identifier(sourceID: metadata.sourceID, name: $0)
        }
        return ids.contains { categories[$0]?.isFavorite == true }
    }

    public func migratingChannelIDs(_ migration: [String: String]) -> Self {
        var result = self
        result.shownChannelIDs = Set(shownChannelIDs.map { migration[$0] ?? $0 })
        result.excludedFavoriteIDs = Set(excludedFavoriteIDs.map { migration[$0] ?? $0 })
        return result
    }

    public func rebasing(onto latest: Self, from base: Self) -> Self {
        var result = latest
        for id in Set(base.categories.keys).union(categories.keys) where categories[id] != base.categories[id] {
            result.categories[id] = categories[id]
        }
        if region != base.region { result.region = region }
        result.shownChannelIDs.subtract(base.shownChannelIDs.subtracting(shownChannelIDs))
        result.shownChannelIDs.formUnion(shownChannelIDs.subtracting(base.shownChannelIDs))
        result.excludedFavoriteIDs.subtract(base.excludedFavoriteIDs.subtracting(excludedFavoriteIDs))
        result.excludedFavoriteIDs.formUnion(excludedFavoriteIDs.subtracting(base.excludedFavoriteIDs))
        return result
    }
}

public enum LiveTVRegionMetadata {
    public static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func country(_ value: String) -> String {
        let key = normalized(value)
        return countryAliases[key] ?? key
    }

    public static func language(_ value: String) -> String {
        let key = normalized(value)
        return languageAliases[key] ?? key
    }

    private static let countryAliases: [String: String] = {
        let locale = Locale(identifier: "en_US_POSIX")
        var result = ["usa": "us", "uk": "gb"]
        for region in Locale.Region.isoRegions {
            let code = normalized(region.identifier)
            result[code] = code
            if let name = locale.localizedString(forRegionCode: region.identifier) { result[normalized(name)] = code }
        }
        return result
    }()

    private static let languageAliases: [String: String] = {
        let locale = Locale(identifier: "en_US_POSIX")
        var result: [String: String] = [:]
        for language in Locale.LanguageCode.isoLanguageCodes {
            let code = normalized(language.identifier(.alpha2) ?? language.identifier)
            result[normalized(language.identifier)] = code
            if let alpha3 = language.identifier(.alpha3) { result[normalized(alpha3)] = code }
            result[code] = code
            if let name = locale.localizedString(forLanguageCode: language.identifier) { result[normalized(name)] = code }
        }
        return result
    }()
}
