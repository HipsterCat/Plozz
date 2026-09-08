#if DEBUG
import CoreModels
import CryptoKit
import Foundation

extension LiveTVSourcesConfiguration {
    /// An explicit opt-in, never the fallback for absent or unreadable profile configuration.
    public static var freeUS: LiveTVSourcesConfiguration {
        LiveTVSourcesConfiguration(playlists: [
            LiveTVPlaylistSource(
                id: "free-us", name: "Free US channels",
                playlistURL: URL(string: "https://iptv-org.github.io/iptv/countries/us.m3u")!,
                guideURLs: LiveTVGuideSource.defaults.map(\.url)
            )
        ])
    }
}

enum LiveTVConfiguredSources {
    static func guides(for source: LiveTVPlaylistSource) -> [LiveTVGuideSource] {
        source.guideURLs.enumerated().map { index, url in
            let preset = source.id == "free-us" ? LiveTVGuideSource.defaults.first { $0.url == url } : nil
            return LiveTVGuideSource(
                id: preset?.id ?? "guide-\(digest(source.id + "\u{1F}" + url.absoluteString))",
                name: preset?.name ?? "\(source.name) · Guide \(index + 1)",
                url: url, provider: LiveTVGuideSource.provider(for: url)
            )
        }
    }

    static func scope(
        _ playlist: LiveTVPlaylistImport, to sourceID: String, preservesChannelIDs: Bool = false
    ) -> LiveTVPlaylistImport {
        LiveTVPlaylistImport(
            channels: playlist.channels.map { channel in
                LiveTVPrototypeChannel(
                    id: preservesChannelIDs ? channel.id : "iptv-source-\(digest(sourceID + "\u{1F}" + channel.id))",
                    number: channel.number, name: channel.name, category: channel.category,
                    symbol: channel.symbol, accent: channel.accent, source: channel.source,
                    tagline: channel.tagline, logoURL: channel.logoURL, streamURL: channel.streamURL,
                    logoNeedsDarkBackground: channel.logoNeedsDarkBackground,
                    guideID: channel.guideID, guideName: channel.guideName, httpHeaders: channel.httpHeaders,
                    playlistSourceID: sourceID
                )
            },
            entryCount: playlist.entryCount, skippedEntryCount: playlist.skippedEntryCount
        )
    }

    static func scope(_ guide: LiveTVGuideImport, to sourceID: String) -> LiveTVGuideImport {
        LiveTVGuideImport(
            programs: guide.programs.map {
                LiveTVPrototypeProgram(
                    id: "iptv-program-\(digest(sourceID + "\u{1F}" + $0.id))",
                    channelID: $0.channelID, title: $0.title, subtitle: $0.subtitle,
                    start: $0.start, end: $0.end
                )
            },
            matchedChannelCount: guide.matchedChannelCount, guideChannelCount: guide.guideChannelCount,
            programCount: guide.programCount, coverageStart: guide.coverageStart, coverageEnd: guide.coverageEnd,
            matches: guide.matches
        )
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
