#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

struct LibraryCardLabelSettingsView: View {
    @Bindable var cards: CardStyleSettingsModel
    let visibility: HomeLibraryVisibilityModel
    @State private var selectedPage = CardCaptionView.recommended
    @State private var previewView = CardCaptionView.recommended

    static let pages: [CardCaptionView] = [.recommended, .browse, .collections, .playlists]

    static func controls(on page: CardCaptionView) -> [CardCaptionView] {
        page == .recommended ? [.recommended, .continueWatching] : [page]
    }

    private var views: [CardCaptionView] { Self.controls(on: selectedPage) }

    var body: some View {
        #if os(tvOS)
        ViewCustomizationList(
            title: "Customize labels", initialRowID: "library-label-target",
            focusedHelp: { id in
                let view = views.first { "card-label-view-\($0.rawValue)" == id } ?? selectedPage
                return ViewCustomizationHelp(
                    detail: view.libraryLabelDetail,
                    illustration: .libraryCaptions(preview(editing: view), style: cards.style)
                )
            }
        ) {
            Section {
                ViewCustomizationRow(
                    id: "library-label-target", title: "Page", value: selectedPage.displayName
                ) {
                    let index = Self.pages.firstIndex(of: selectedPage) ?? 0
                    selectedPage = Self.pages[(index + 1) % Self.pages.count]
                }
            }
            Section {
                labelControls
            } footer: {
                if selectedPage == .recommended {
                    Text("Continue Watching also affects Home.")
                }
            }
        }
        #else
        ViewCustomizationList(title: "Customize labels", initialRowID: "") {
            Section {
                ViewCustomizationMenu(
                    id: "library-label-target", title: "Page",
                    value: selectedPage.displayName, selection: $selectedPage
                ) {
                    ForEach(Self.pages, id: \.self) { page in
                        Text(page.displayName).tag(page)
                    }
                }
            }
            Section {
                labelControls
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedPage.libraryLabelDetail)
                    if selectedPage == .recommended {
                        Text("Continue Watching also affects Home.")
                    }
                }
            }
            Section {
                CardLabelScopePreview(preview: preview(editing: previewView), style: cards.style)
            }
        }
        .onChange(of: selectedPage) { _, page in previewView = page }
        #endif
    }

    private var labelControls: some View {
        ForEach(views, id: \.self) { view in
            CardCaptionViewChoices(
                view: view,
                settings: Binding(
                    get: { cards.captions },
                    set: {
                        previewView = view
                        cards.captions = $0
                    }
                ),
                title: view == .continueWatching ? view.displayName : "Card labels"
            )
        }
    }

    private func preview(editing view: CardCaptionView) -> CardLabelScopePreview.Snapshot {
        #if os(tvOS)
        let showcase = selectedPage == .recommended
        #else
        let showcase = false
        #endif
        return CardLabelScopePreview.snapshot(
            page: selectedPage, editing: views.contains(view) ? view : selectedPage,
            settings: cards.captions, isShowcase: showcase,
            seriesArtwork: visibility.continueWatchingUsesSeriesArtwork,
            layout: visibility.continueWatchingLayout
        )
    }
}

private extension CardCaptionView {
    var libraryLabelDetail: LocalizedStringResource {
        switch self {
        case .recommended:
            "Changes labels below Recommended cards in all libraries. Continue Watching follows this page unless its labels are set to On or Off."
        case .browse:
            "Changes labels below Browse cards, including titles inside collections and playlists."
        case .collections:
            "Changes labels below collection covers in all libraries. Titles inside a collection use Browse."
        case .playlists:
            "Changes labels below playlist covers in all libraries. Titles inside a playlist use Browse."
        case .continueWatching:
            "Also affects Home. Follow page uses each page's label setting; On or Off overrides both."
        default:
            "Changes labels below cards, not logos, descriptions, or playback information."
        }
    }
}

struct CardLabelScopePreview: View {
    struct Snapshot: Hashable {
        let page: CardCaptionView
        let rows: [Row]
        let layout: ContinueWatchingCardLayout

        var accessibilitySummary: Text {
            var text = Text(page == .home ? LocalizedStringResource("Home") : page.displayName)
            for row in rows {
                text = text + Text(verbatim: ". ")
                    + Text(row.isContinueWatching ? LocalizedStringResource("Continue Watching") : "Card labels")
                    + Text(verbatim: ": ")
                    + Text(row.showsLabels ? CardCaptionOverride.show.displayName : CardCaptionOverride.hide.displayName)
            }
            return text
        }
    }

    struct Row: Hashable {
        let isContinueWatching: Bool
        let showsLabels: Bool
        let highlighted: Bool
    }

    let preview: Snapshot
    let style: CardStyle
    @Environment(\.themePalette) private var palette
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.page == .home ? LocalizedStringResource("Home") : preview.page.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            diagram
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preview.accessibilitySummary)
        .accessibilityIdentifier("library-label-preview-\(preview.page.rawValue)")
    }

    private func rowTitle(_ row: Row) -> LocalizedStringResource {
        row.isContinueWatching ? "Continue Watching" : "Card labels"
    }

    private var diagram: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 320, y: size.height / 180)
            if layoutDirection == .rightToLeft {
                context.translateBy(x: 320, y: 0)
                context.scaleBy(x: -1, y: 1)
            }
            context.fill(Path(CGRect(x: 0, y: 0, width: 320, height: 180)),
                         with: .color(palette.settingsBackground))
            let rows = preview.rows.count == 1 ? preview.rows + preview.rows : preview.rows
            for (index, row) in rows.enumerated() {
                let top = CGFloat(index) * 86 + 8
                context.draw(
                    Text(rowTitle(row)).font(.system(size: 9, weight: .medium))
                        .foregroundColor(palette.secondaryText),
                    at: CGPoint(x: 12, y: top), anchor: .topLeading
                )
                let landscape = row.isContinueWatching && preview.layout == .landscape
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
        page: CardCaptionView, editing view: CardCaptionView, settings: CardCaptionSettings,
        isShowcase: Bool,
        seriesArtwork: Bool, layout: ContinueWatchingCardLayout
    ) -> Snapshot {
        var rows = [Row(
            isContinueWatching: false,
            showsLabels: settings.showsLabels(in: page, isShowcase: isShowcase),
            highlighted: view != .continueWatching
        )]
        if page == .home || page == .recommended {
            rows.insert(Row(
                isContinueWatching: true,
                showsLabels: settings.showsLabels(
                    in: page, isShowcase: isShowcase, hasArtworkTitle: seriesArtwork, isContinueWatching: true
                ),
                highlighted: view == .continueWatching || settings.override(for: .continueWatching) == .automatic
            ), at: 0)
        }
        return Snapshot(page: page, rows: rows, layout: layout)
    }
}
#endif
