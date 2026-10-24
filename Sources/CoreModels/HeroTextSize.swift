import Foundation

/// A profile-scoped adjustment, independent of artwork and any app-wide scale.
public struct HeroTextSize: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: Int
    public static let steps = -5...5
    public static let `default` = HeroTextSize(rawValue: 0)
    public static let allSizes = steps.map { HeroTextSize(rawValue: $0) }

    public init(rawValue: Int) {
        self.rawValue = min(max(rawValue, Self.steps.lowerBound), Self.steps.upperBound)
    }

    public var scale: Double {
        #if os(tvOS)
        let increment = rawValue > 0 ? 0.1 : 0.05
        #else
        let increment = 0.05
        #endif
        return 1 + Double(rawValue) * increment
    }
    public var position: Int { rawValue - Self.steps.lowerBound }

    public func descriptionLineLimit(base: Int) -> Int {
        precondition(base > 0)
        return base + (rawValue > 0 ? 1 : 0)
    }

    public func scrimHeightScale(logoSize: HeroLogoSize, descriptionLines: Int = 3) -> Double {
        let textHeight = scale * Double(descriptionLineLimit(base: descriptionLines)) / Double(descriptionLines)
        return max(1, logoSize.scale, textHeight)
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
