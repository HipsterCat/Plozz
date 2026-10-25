#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

enum CardCaptionSettingsPage: String, CaseIterable {
    case home, recommended, browse, collections, playlists, search, watchlist, detail, people

    var title: LocalizedStringResource {
        switch self {
        case .home: "Home"
        case .recommended: "Recommended"
        case .browse: "Browse"
        case .collections: "Collections"
        case .playlists: "Playlists"
        case .search: "Search"
        case .watchlist: "Watchlist"
        case .detail: "Detail Page"
        case .people: "People"
        }
    }

    var controls: [CardCaptionView] {
        switch self {
        case .home: [.home, .continueWatching]
        case .recommended: [.recommended, .continueWatching]
        case .browse: [.browse]
        case .collections: [.collections]
        case .playlists: [.playlists]
        case .search: [.search]
        case .watchlist: [.watchlist]
        case .detail: [.episodes, .related, .extras]
        case .people: [.filmography]
        }
    }

    var firstControl: CardCaptionView { controls[0] }

    var sharedRowNote: LocalizedStringResource? {
        switch self {
        case .home: "Continue Watching also affects Recommended."
        case .recommended: "Continue Watching also affects Home."
        default: nil
        }
    }
}

extension CardCaptionSettingsScope {
    var pages: [CardCaptionSettingsPage] {
        switch self {
        case .all: CardCaptionSettingsPage.allCases
        case .home: [.home]
        case .libraries: [.recommended, .browse, .collections, .playlists]
        case .detail: [.detail]
        }
    }
}

struct CardCaptionCustomizationContent: View {
    @Binding var settings: CardCaptionSettings
    var style: CardStyle
    let scope: CardCaptionSettingsScope
    let visibility: HomeLibraryVisibilityModel?
    @Environment(HeroSettingsModel.self) private var hero: HeroSettingsModel?
    @State private var selectedPage: CardCaptionSettingsPage
    @State private var previewView: CardCaptionView

    init(
        settings: Binding<CardCaptionSettings>, style: CardStyle = .borderless,
        scope: CardCaptionSettingsScope = .all, visibility: HomeLibraryVisibilityModel? = nil
    ) {
        _settings = settings
        self.style = style
        self.scope = scope
        self.visibility = visibility
        _selectedPage = State(initialValue: scope.pages[0])
        _previewView = State(initialValue: scope.pages[0].firstControl)
    }

    private var views: [CardCaptionView] { selectedPage.controls }
    private var initialRowID: String {
        scope.pages.count > 1 ? "card-label-page" : "card-label-view-\(selectedPage.firstControl.rawValue)"
    }

    var body: some View {
        #if os(tvOS)
        ViewCustomizationList(
            title: "Customize labels", initialRowID: initialRowID,
            focusedHelp: { id in
                let view = views.first { "card-label-view-\($0.rawValue)" == id } ?? selectedPage.firstControl
                return ViewCustomizationHelp(
                    detail: view.cardLabelDetail,
                    illustration: .pageCaptions(preview(editing: view), style: style)
                )
            }
        ) {
            if scope.pages.count > 1 {
                Section {
                    ViewCustomizationRow(
                        id: "card-label-page", title: "Page", value: selectedPage.title
                    ) {
                        guard let index = scope.pages.firstIndex(of: selectedPage) else {
                            preconditionFailure("The selected caption page must belong to this editor.")
                        }
                        selectedPage = scope.pages[(index + 1) % scope.pages.count]
                    }
                }
            }
            Section {
                labelControls
            } footer: {
                if let note = selectedPage.sharedRowNote {
                    Text(note)
                }
            }
        }
        #else
        ViewCustomizationList(title: "Customize labels", initialRowID: "") {
            if scope.pages.count > 1 {
                Section {
                    ViewCustomizationMenu(
                        id: "card-label-page", title: "Page",
                        value: selectedPage.title, selection: $selectedPage
                    ) {
                        ForEach(scope.pages, id: \.self) { page in
                            Text(page.title).tag(page)
                        }
                    }
                }
            }
            Section {
                labelControls
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if selectedPage != .detail {
                        Text(selectedPage.firstControl.cardLabelDetail)
                    }
                    if let note = selectedPage.sharedRowNote {
                        Text(note)
                    }
                }
            }
            Section {
                CardLabelScopePreview(preview: preview(editing: previewView), style: style)
            }
        }
        .onChange(of: selectedPage) { _, page in previewView = page.firstControl }
        #endif
    }

    private var labelControls: some View {
        ForEach(views, id: \.self) { view in
            CardCaptionViewChoices(
                view: view,
                settings: Binding(
                    get: { settings },
                    set: {
                        previewView = view
                        settings = $0
                    }
                ),
                title: selectedPage == .detail || view == .continueWatching ? view.cardLabelTitle : "Card labels"
            )
        }
    }

    private func preview(editing view: CardCaptionView) -> CardLabelScopePreview.Snapshot {
        #if os(tvOS)
        let showcase = selectedPage == .recommended
            || (selectedPage == .home && (hero?.effectiveSettings.followsFocus ?? HeroSettings.default.followsFocus))
        #else
        let showcase = false
        #endif
        return CardLabelScopePreview.snapshot(
            page: selectedPage, editing: views.contains(view) ? view : selectedPage.firstControl,
            settings: settings, isShowcase: showcase,
            seriesArtwork: visibility?.continueWatchingUsesSeriesArtwork ?? true,
            layout: visibility?.continueWatchingLayout ?? .landscape
        )
    }
}

extension CardCaptionView {
    var cardLabelTitle: LocalizedStringResource {
        self == .episodes ? "Episodes" : displayName
    }

    var cardLabelDetail: LocalizedStringResource {
        switch self {
        case .home:
            "Changes labels below Home cards, not the hero logo or description. Continue Watching follows Home unless set to On or Off."
        case .recommended:
            "Changes labels below Recommended cards in all libraries. Continue Watching follows this page unless its labels are set to On or Off."
        case .browse:
            "Changes labels below Browse cards, including titles inside collections and playlists."
        case .collections:
            "Changes labels below collection covers in all libraries. Titles inside a collection use Browse."
        case .playlists:
            "Changes labels below playlist covers in all libraries. Titles inside a playlist use Browse."
        case .continueWatching:
            "Shared by Home and Recommended. Follow page uses each page's label setting; On or Off overrides both."
        case .search: "Changes labels below cards in search results."
        case .watchlist: "Changes labels below cards on the Watchlist page."
        case .episodes: "Changes episode labels in the episode browser and on detail pages."
        case .related: "Changes labels below related titles on detail pages."
        case .extras: "Changes labels below trailers, clips, and other extras on detail pages."
        case .filmography: "Changes labels below titles on a person's page."
        }
    }
}

struct CardLabelScopePreview: View {
    struct Snapshot: Hashable {
        let page: CardCaptionSettingsPage
        let rows: [Row]
        let layout: ContinueWatchingCardLayout

        var accessibilitySummary: Text {
            var text = Text(page.title)
            for row in rows {
                text = text + Text(verbatim: ". ")
                    + Text(row.title)
                    + Text(verbatim: ": ")
                    + Text(row.showsLabels ? CardCaptionOverride.show.displayName : CardCaptionOverride.hide.displayName)
            }
            return text
        }
    }

    struct Row: Hashable {
        let view: CardCaptionView
        let showsLabels: Bool
        let highlighted: Bool

        var isContinueWatching: Bool { view == .continueWatching }
        var title: LocalizedStringResource {
            [.continueWatching, .episodes, .related, .extras].contains(view) ? view.cardLabelTitle : "Card labels"
        }
    }

    let preview: Snapshot
    let style: CardStyle
    @Environment(\.themePalette) private var palette
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.page.title)
                .font(.caption.weight(.semibold))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            diagram
                .aspectRatio(320 / diagramHeight, contentMode: .fit)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preview.accessibilitySummary)
        .accessibilityIdentifier("card-label-preview-\(preview.page.rawValue)")
    }

    private var diagramHeight: CGFloat { CGFloat(max(2, preview.rows.count)) * 86 + 8 }

    private var diagram: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 320, y: size.height / diagramHeight)
            if layoutDirection == .rightToLeft {
                context.translateBy(x: 320, y: 0)
                context.scaleBy(x: -1, y: 1)
            }
            context.fill(Path(CGRect(x: 0, y: 0, width: 320, height: diagramHeight)),
                         with: .color(palette.settingsBackground))
            let rows = preview.rows.count == 1 ? preview.rows + preview.rows : preview.rows
            for (index, row) in rows.enumerated() {
                let top = CGFloat(index) * 86 + 8
                context.draw(
                    Text(row.title).font(.system(size: 9, weight: .medium))
                        .foregroundColor(palette.secondaryText),
                    at: CGPoint(x: 12, y: top), anchor: .topLeading
                )
                let landscape = (row.isContinueWatching && preview.layout == .landscape)
                    || row.view == .episodes || row.view == .extras
                let width: CGFloat = landscape ? 88 : 32
                let count = landscape ? 3 : 6
                let height: CGFloat = landscape ? 49.5 : 48
                for column in 0..<count {
                    let x = 12 + CGFloat(column) * (landscape ? 102 : 50)
                    let y = top + 14
                    if style == .framed {
                        context.fill(Path(roundedRect: CGRect(x: x - 3, y: y - 3, width: width + 6, height: height + 17),
                                          cornerRadius: 4), with: .color(palette.fill))
                    }
                    let art = CGRect(x: x, y: y, width: width, height: height)
                    context.fill(Path(roundedRect: art, cornerRadius: 3), with: .color(palette.tertiaryText.opacity(0.3)))
                    var icon = context.resolve(Image(systemName: "photo"))
                    icon.shading = .color(palette.tertiaryText)
                    context.draw(icon, in: CGRect(x: art.midX - 9, y: art.midY - 7, width: 18, height: 14))
                    let label = Path(roundedRect: CGRect(x: x, y: art.maxY + 4, width: width, height: 7), cornerRadius: 2)
                    let ink = row.highlighted ? palette.accent : palette.tertiaryText
                    if row.showsLabels {
                        context.fill(label, with: .color(ink))
                    }
                    if row.highlighted {
                        context.stroke(label, with: .color(ink),
                                       style: StrokeStyle(lineWidth: 1.5, dash: row.showsLabels ? [] : [3, 2]))
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    static func snapshot(
        page: CardCaptionSettingsPage, editing view: CardCaptionView, settings: CardCaptionSettings,
        isShowcase: Bool,
        seriesArtwork: Bool, layout: ContinueWatchingCardLayout
    ) -> Snapshot {
        let rowViews = page == .home || page == .recommended
            ? [.continueWatching, page.firstControl] : page.controls
        let rows = rowViews.map { rowView in
            Row(
                view: rowView,
                showsLabels: settings.showsLabels(
                    in: rowView == .continueWatching ? page.firstControl : rowView,
                    isShowcase: isShowcase,
                    hasArtworkTitle: rowView == .continueWatching && seriesArtwork,
                    isContinueWatching: rowView == .continueWatching
                ),
                highlighted: rowView == view || (rowView == .continueWatching && view == page.firstControl
                    && settings.override(for: .continueWatching) == .automatic)
            )
        }
        return Snapshot(page: page, rows: rows, layout: layout)
    }
}
#endif
