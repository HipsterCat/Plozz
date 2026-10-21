import CoreModels

/// The same flat, profile-resolved list feeds every Home layout on every platform.
public struct HomePresentationRow: Identifiable, Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case home(HomeRow)
        case library(HomeLibrarySectionGroup.Row)
        case liveTV([HomeLiveTVChannel])
    }

    public let choice: HomeRowChoice
    public let source: Source
    public var id: HomeRowID { choice.id }

    public static func hasLiveTVRows(
        _ liveTV: HomeLiveTVSnapshot, visibility: HomeLibraryVisibility
    ) -> Bool {
        !resolve(rows: [], content: .init(), visibility: visibility, liveTV: liveTV).isEmpty
    }

    public static func displayState(
        _ state: LoadState<HomeViewModel.Content>,
        liveTV: HomeLiveTVSnapshot, visibility: HomeLibraryVisibility
    ) -> LoadState<HomeViewModel.Content> {
        if case .empty = state, hasLiveTVRows(liveTV, visibility: visibility) {
            return .loaded(.init())
        }
        return state
    }

    public static func resolve(
        rows: [HomeRow], content: HomeViewModel.Content, visibility: HomeLibraryVisibility,
        liveTV: HomeLiveTVSnapshot = .empty
    ) -> [Self] {
        let shared = HomeRowChoice.shared
        func entry(_ row: HomeRow) -> Self? {
            let id: HomeRowID
            if row.kind == .libraries {
                id = .libraries
            } else if let kind = HomeGlobalRow(rawValue: row.kind.rawValue) {
                id = .global(kind)
            } else {
                return nil
            }
            guard let choice = shared.first(where: { $0.id == id }) else { return nil }
            return Self(choice: choice, source: .home(row))
        }
        var available = rows.filter { $0.kind != .libraries }.compactMap(entry)
        if !liveTV.recentChannels.isEmpty, !rows.contains(where: { $0.kind == .continueWatching }),
           let recent = entry(HomeRow(kind: .continueWatching)) {
            available.insert(recent, at: 0)
        }
        if !liveTV.channels.isEmpty, let choice = shared.first(where: { $0.id == .liveTV }) {
            available.append(Self(choice: choice, source: .liveTV(liveTV.channels)))
        }
        if visibility.usesIndividualHomeRows {
            for group in content.librarySections where visibility.isEnabled(group.library.key) {
                for row in group.rows {
                    guard !row.section.items.isEmpty || row.isLoading || row.failure != nil else { continue }
                    if row.id == "pending-hubs" {
                        let known = (visibility.rowCustomization?.order ?? []).filter {
                            $0.libraryKey == group.library.key && $0.libraryKind == .hubs
                                && visibility.rowCustomization?.hidden.contains($0) != true
                        }
                        for id in known.isEmpty ? [.library(key: group.library.key, section: row.id)] : known {
                            available.append(Self(
                                choice: HomeRowChoice(
                                    id: id, title: row.section.title,
                                    localizedTitle: row.section.localizedTitle, library: group.library,
                                    isProviderDefault: true
                                ),
                                source: .library(row)
                            ))
                        }
                    } else {
                        available.append(Self(
                            choice: HomeRowChoice(section: row.section, library: group.library),
                            source: .library(row)
                        ))
                    }
                }
            }
            for var row in content.serverRows {
                if let libraryID = row.definition.section.libraryID,
                   !visibility.isEnabled("\(row.definition.accountID):\(libraryID)") { continue }
                row.items = row.items.filter { $0.isVisibleOnHome(isLibraryVisible: visibility.isEnabled) }
                guard !row.items.isEmpty || row.isLoading || row.failure != nil else { continue }
                available.append(Self(
                    choice: HomeRowChoice(serverRow: row.definition), source: .library(row.row)
                ))
            }
        }
        available += rows.filter { $0.kind == .libraries }.compactMap(entry)
        let byID = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = visibility.rowSections(choices: available.map(\.choice)).enabled
        return ordered.compactMap { byID[$0] }
    }
}
