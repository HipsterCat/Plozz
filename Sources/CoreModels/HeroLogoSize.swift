import Foundation

/// Layout-only sizes from half to 1.5 times the original size, with finer stops near default.
public struct HeroLogoSize: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: Int
    public static let steps = -10...10
    public static let `default` = HeroLogoSize(rawValue: 0)
    public static let allSizes = [-10, -8, -6, -4, -2, -1, 0, 1, 2, 4, 6, 8, 10]
        .map { HeroLogoSize(rawValue: $0) }

    public init(rawValue: Int) {
        self.rawValue = min(max(rawValue, Self.steps.lowerBound), Self.steps.upperBound)
    }

    public var scale: Double { 1 + Double(rawValue) * 0.05 }

    /// Older saved sizes retain their exact scale until the user adjusts to a new stop.
    public var position: Int {
        Self.allSizes.indices.reduce(0) { closest, candidate in
            abs(Self.allSizes[candidate].rawValue - rawValue) < abs(Self.allSizes[closest].rawValue - rawValue)
                ? candidate : closest
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
