import CoreModels
import Foundation

enum TopShelfMetadata {
    static func apply(
        to snapshot: inout TopShelfSnapshot.Item, item: MediaItem, details: MediaItem?,
        spoilerSettings: SpoilerSettings, locale: Locale?
    ) {
        let metadata = details ?? item
        let hidesText = spoilerSettings.shouldHideText(for: item)
        let title = hidesText ? TopShelfPublisher.resolved(spoilerSettings.maskedTitle(for: item), locale) : item.title
        let seriesTitle = cleaned([item.parentTitle, metadata.parentTitle]).first
        let episodeLabel = item.seasonEpisodeLabel ?? metadata.seasonEpisodeLabel
        snapshot.title = item.kind == .episode
            ? cleaned([seriesTitle, title]).joined(separator: " — ") : title
        if hidesText {
            snapshot.summary = cleaned([seriesTitle, episodeLabel ?? title]).joined(separator: " · ")
        } else {
            snapshot.summary = cleaned([metadata.overview, item.overview]).first
        }
        snapshot.genre = cleaned((metadata.genres.isEmpty ? item.genres : metadata.genres).map(Optional.some))
            .prefix(3).joined(separator: " · ")
        if snapshot.genre?.isEmpty == true { snapshot.genre = nil }
        snapshot.duration = validDuration(item.runtime) ?? validDuration(metadata.runtime)
        snapshot.releaseDate = metadata.releaseDate ?? item.releaseDate
        if item.kind == .episode {
            snapshot.subtitle = episodeLabel
        } else if snapshot.releaseDate != nil {
            snapshot.subtitle = nil
        } else if let year = metadata.productionYear ?? item.productionYear {
            snapshot.subtitle = String(year)
        }
        snapshot.mediaOptions = mediaOptions(for: metadata)

        var attributes: [TopShelfSnapshot.NamedAttribute] = []
        func append(_ name: LocalizedStringResource, _ values: [String?]) {
            let values = cleaned(values)
            guard !values.isEmpty, attributes.count < 4 else { return }
            attributes.append(.init(name: TopShelfPublisher.resolved(name, locale), values: values))
        }
        var progress = item
        progress.runtime = snapshot.duration
        if let duration = snapshot.duration, duration.isFinite,
           progress.resumePosition?.isFinite != false, progress.playedPercentage?.isFinite != false {
            append("Time Left", [progress.resumeRemainingText])
        }
        append("Content Rating", [cleaned([metadata.officialRating, item.officialRating]).first])
        let people = metadata.people.isEmpty ? item.people : metadata.people
        // Unwatched guest appearances can reveal plot points just like episode titles.
        if !hidesText {
            append("Cast", Array(people.filter(\.isCast).prefix(3).map { Optional($0.name) }))
        }
        append("Director", Array(people.filter { $0.kind?.lowercased() == "director" }.prefix(2).map { Optional($0.name) }))
        let studios = metadata.studios.isEmpty ? item.studios : metadata.studios
        append("Studio", Array(studios.prefix(2).map(Optional.some)))
        if !spoilerSettings.shouldHideRatings(for: item) {
            let ratings = metadata.ratings.isEmpty && !metadata.usesProviderRatings ? item.ratings : metadata.ratings
            append("Ratings", ratings.filter { $0.value.isFinite && $0.value >= 0 && $0.value <= $0.scale.maximum }
                .sorted { $0.sortRank < $1.sortRank }.prefix(3).map { "\($0.displayName) \($0.displayValue)" })
        }
        snapshot.namedAttributes = attributes
    }

    private static func validDuration(_ duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    private static func cleaned(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
    }

    private static func mediaOptions(for item: MediaItem) -> [TopShelfSnapshot.MediaOption] {
        guard [.movie, .episode, .video].contains(item.kind) else { return [] }
        let version = item.selectedVersion ?? item.versions.first(where: \.isDefault) ?? item.versions.first
        let badges = version?.technicalBadges ?? item.technicalBadges
        var options: [TopShelfSnapshot.MediaOption] = []
        if badges.contains(where: { $0.label == "4K" || $0.label == "8K" }) { options.append(.ultraHD) }
        else if badges.contains(where: { ["720p", "1080p", "1440p"].contains($0.label) }) { options.append(.hd) }
        if badges.contains(where: { $0.label == "Dolby Vision" }) { options.append(.dolbyVision) }
        else if badges.contains(where: { $0.style == .hdr }) { options.append(.hdr) }
        if badges.contains(where: { $0.label == "Dolby Atmos" }) { options.append(.dolbyAtmos) }
        let subtitle = version?.sourceMetadata?.subtitle ?? item.mediaInfo?.subtitle
        if let codec = subtitle?.codec?.lowercased(), ["eia_608", "eia_708", "cea_608", "cea_708"].contains(codec) {
            options.append(.closedCaptions)
        }
        if let title = subtitle?.title, TrackLabeling.isHearingImpaired(title) { options.append(.sdh) }
        return options
    }
}
