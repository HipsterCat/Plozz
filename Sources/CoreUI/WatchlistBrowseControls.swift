import SwiftUI
import CoreModels

public struct WatchlistBrowseControls: View {
    @Binding private var preferences: WatchlistBrowsePreferences
    @Environment(\.locale) private var locale

    public init(preferences: Binding<WatchlistBrowsePreferences>) {
        _preferences = preferences
    }

    public var body: some View {
        BrowseQueryControls {
            #if os(tvOS)
            filterMenu
            sortMenu
            #else
            sortMenu
            filterMenu
            #endif
        }
    }

    private var sortMenu: some View {
        BrowseSortMenu(sort: preferences.sort, fields: WatchlistBrowsePreferences.sortFields) {
            preferences.sort = $0
        }
        .accessibilityIdentifier("watchlist-sort-menu")
    }

    private var filterMenu: some View {
        BrowseFilterMenu(activeCount: preferences.filter == .all ? 0 : 1, summary: filterSummary) {
            Picker("Filter", selection: $preferences.filter) {
                ForEach(WatchlistMediaFilter.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            if preferences.filter != .all {
                Button("Clear Filters") { preferences.filter = .all }
            }
        }
        #if os(iOS)
        .frame(minWidth: 44, minHeight: 44)
        #endif
        .accessibilityIdentifier("watchlist-filter-menu")
    }

    private var filterSummary: String {
        var name = preferences.filter.displayName
        name.locale = locale
        return String(localized: name) // l10n:content — resolves the existing filter label
    }
}

public struct WatchlistEmptyStateView: View {
    private let isFiltered: Bool
    private let clearFilters: () -> Void

    public init(isFiltered: Bool, clearFilters: @escaping () -> Void) {
        self.isFiltered = isFiltered
        self.clearFilters = clearFilters
    }

    public var body: some View {
        ContentUnavailableView {
            Label {
                if isFiltered {
                    Text("No titles match these filters.")
                } else {
                    Text("Your Watchlist is empty")
                }
            } icon: {
                Image(systemName: "bookmark")
            }
        } description: {
            if !isFiltered {
                Text("Add a movie or show from Plozz or any connected Watchlist.")
            }
        } actions: {
            if isFiltered { Button("Clear Filters", action: clearFilters) }
        }
    }
}
