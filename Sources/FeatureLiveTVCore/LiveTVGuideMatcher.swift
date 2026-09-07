#if DEBUG
import Foundation

public struct LiveTVGuideMatcher: Sendable {
    public init() {}

    public func match(
        channels: [LiveTVPrototypeChannel],
        guideChannels: [String: [String]]
    ) -> [String: [LiveTVPrototypeChannel]] {
        let playlistIDs = Dictionary(
            grouping: channels.compactMap { channel in
                channel.guideID.map { ($0, channel) }
            },
            by: \.0
        )
        var result: [String: [LiveTVPrototypeChannel]] = [:]

        for guideID in guideChannels.keys {
            if let exact = playlistIDs[guideID] {
                result[guideID] = exact.map(\.1)
                continue
            }
            if let aliasID = verifiedAliases.first(where: {
                $0.value == guideID
            })?.key,
               let aliases = playlistIDs[aliasID] {
                result[guideID] = aliases.map(\.1)
            }
        }

        let matchedIDs = Set(result.values.flatMap { $0.map(\.id) })
        let unmatched = channels.filter { !matchedIDs.contains($0.id) }
        let playlistNames = Dictionary(
            grouping: unmatched,
            by: { normalizedDisplayName($0.guideName ?? $0.name) }
        )
        var guideNames: [String: [(id: String, name: String)]] = [:]
        for (guideID, names) in guideChannels where result[guideID] == nil {
            for name in names {
                guideNames[normalizedDisplayName(name), default: []]
                    .append((guideID, name))
            }
        }

        var candidates: [String: [LiveTVPrototypeChannel]] = [:]
        for (normalized, playlistMatches) in playlistNames {
            guard !normalized.isEmpty, shareOneIdentity(playlistMatches),
                  let guideMatches = guideNames[normalized],
                  Set(guideMatches.map(\.id)).count == 1,
                  let guide = guideMatches.first,
                  playlistMatches.allSatisfy({ channel in
                      sourceRegionsAreCompatible(channel.guideID, guide.id)
                          && affiliateCallSignsAreCompatible(
                              playlistID: channel.guideID, playlistName: channel.name,
                              guideID: guide.id, guideName: guide.name
                          )
                          && feedQualifiersAreCompatible(
                              playlistID: channel.guideID, playlistName: channel.name,
                              guideID: guide.id, guideName: guide.name
                          )
                  })
            else { continue }
            candidates[guide.id, default: []].append(contentsOf: playlistMatches)
        }
        for (guideID, channels) in candidates where shareOneIdentity(channels) {
            result[guideID] = channels.sorted { $0.id < $1.id }
        }
        return result
    }

    private func shareOneIdentity(_ channels: [LiveTVPrototypeChannel]) -> Bool {
        guard channels.count != 1 else { return true }
        guard let guideID = channels.first?.guideID, !guideID.isEmpty else { return false }
        return channels.allSatisfy { $0.guideID == guideID }
    }

    public func normalizedDisplayName(_ input: String) -> String {
        let folded = input.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixPattern = #"\s*\((?:2160p|1080p|720p|576p|480p|360p|240p|UHD|FHD|HD|SD)\)\s*$"#
        let range = NSRange(folded.startIndex..., in: folded)
        let stripped: String
        if let expression = try? NSRegularExpression(
            pattern: suffixPattern,
            options: [.caseInsensitive]
        ) {
            stripped = expression.stringByReplacingMatches(
                in: folded, range: range, withTemplate: ""
            )
        } else {
            stripped = folded
        }
        return stripped.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private let verifiedAliases: [String: String] = [
        "DareToDreamNetwork.us@SD": "3ABN.Dare.to.Dream.Network.us2",
        "3ABNEnglish.us@SD": "3ABN.us2",
        "3ABNKids.us@SD": "3ABN.Kids.Network.us2",
        "3ABNLatino.us@SD": "3ABN.Latino.Network.us2",
        "3ABNPraiseHimMusicNetwork.us@SD": "3ABN.Praise.Him.Music.us2",
        "3ABNProclaimNetwork.us@SD": "3ABN.Proclaim.Network.us2",
    ]

    private func sourceRegionsAreCompatible(_ playlistID: String?, _ guideID: String) -> Bool {
        guard let playlistRegion = sourceRegion(in: playlistID),
              let guideRegion = sourceRegion(in: guideID)
        else { return true }
        return playlistRegion == guideRegion
    }

    private func sourceRegion(in identifier: String?) -> String? {
        guard let identifier else { return nil }
        let pattern = #"\.([A-Za-z]{2})(?:\d+)?(?:@|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: identifier,
                range: NSRange(identifier.startIndex..., in: identifier)
              ),
              let range = Range(match.range(at: 1), in: identifier)
        else { return nil }
        return identifier[range].lowercased()
    }

    private func feedQualifiersAreCompatible(
        playlistID: String?,
        playlistName: String,
        guideID: String,
        guideName: String
    ) -> Bool {
        if let playlistID,
           feedQualifiers(in: playlistID) != feedQualifiers(in: guideID) {
            return false
        }
        let playlist = feedQualifiers(in: "\(playlistID ?? "") \(playlistName)")
        let guide = feedQualifiers(in: "\(guideID) \(guideName)")
        return playlist == guide
    }

    private func feedQualifiers(in text: String) -> Set<String> {
        let lower = text.lowercased()
        let words = ["east", "west", "pacific", "mountain", "central", "alaska", "hawaii"]
        var result = Set(words.filter { word in
            lower.range(
                of: #"(?<![a-z])\#(word)(?![a-z])"#,
                options: .regularExpression
            ) != nil
        })
        for offset in 1...3 where lower.contains("+\(offset)") {
            result.insert("+\(offset)")
        }
        return result
    }

    private func affiliateCallSignsAreCompatible(
        playlistID: String?,
        playlistName: String,
        guideID: String,
        guideName: String
    ) -> Bool {
        let playlist = affiliateCallSign(in: "\(playlistID ?? "") \(playlistName)")
        let guide = affiliateCallSign(in: "\(guideID) \(guideName)")
        switch (playlist, guide) {
        case (nil, nil):
            return true
        case let (playlist?, guide?):
            return playlist == guide
        default:
            return false
        }
    }

    private func affiliateCallSign(in text: String) -> String? {
        let upper = text.uppercased()
        let pattern = #"(?<![A-Z])([KW][A-Z]{3})(?![A-Z])"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: upper,
                range: NSRange(upper.startIndex..., in: upper)
              ),
              let range = Range(match.range(at: 1), in: upper)
        else { return nil }
        return String(upper[range])
    }
}
#endif
