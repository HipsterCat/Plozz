#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

struct PlayerSequenceLayout {
    let metrics: PlayerCardMetrics
    let cardMetrics: PlozzMetrics
    let hasSeasons: Bool
    let hasError: Bool

    var compact: Bool { metrics.contentHeight < 160 }
    var seasonHeight: CGFloat { compact ? 28 : 52 }
    var gap: CGFloat { compact ? 6 : 12 }
    var rowHeight: CGFloat {
        metrics.cardHeight - (hasSeasons ? seasonHeight + gap : 0)
            - (hasError ? 36 + gap : 0)
    }
    var titleHeight: CGFloat {
        (metrics.castNameSize * (compact ? 1.4 : 2.45)).rounded(.up)
    }
    var imageHeight: CGFloat {
        rowHeight - cardMetrics.cardInset * 2 - cardMetrics.landscapeCaptionInset
            - cardMetrics.landscapeCaptionTopSpacing - titleHeight
    }
    var imageWidth: CGFloat { (imageHeight * 16 / 9).rounded() }
    var cardWidth: CGFloat {
        imageWidth + cardMetrics.cardInset * 2
    }
}

/// Season episodes and playlist entries share the full-height player card row.
/// Only visible entries are built; playlist pages are still requested on demand.
struct PlayerSequencePanel: View {
    enum Source: Equatable { case episodes, playlist }

    @Environment(\.playerCardMetrics) private var metrics
    @Environment(\.plozzMetrics) private var cardMetrics
    let player: PlayerViewModel
    let source: Source
    @FocusState.Binding var focus: PlayerControls.FocusSlot?

    private var layout: PlayerSequenceLayout {
        PlayerSequenceLayout(
            metrics: metrics,
            cardMetrics: cardMetrics,
            hasSeasons: source == .episodes && !(player.episodeBrowser?.seasons.isEmpty ?? true),
            hasError: source == .playlist && player.playlistContext?.loadError != nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.gap) {
            if source == .episodes, let browser = player.episodeBrowser {
                if !browser.seasons.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(browser.seasons, id: \.id) { season in
                                seasonButton(season, in: browser)
                            }
                        }
                    }
                    .frame(height: layout.seasonHeight)
                    .scrollClipDisabled()
                }
                if let error = browser.loadError {
                    errorRow(error) {
                        if let id = browser.selectedSeasonID {
                            Task { await browser.selectSeason(id) }
                        } else {
                            Task { await browser.loadIfNeeded() }
                        }
                    }
                } else if browser.isLoading {
                    ProgressView("Loading episodes…")
                } else if browser.episodes.isEmpty {
                    emptyRow("No episodes available")
                } else {
                    episodeRow(browser)
                }
            } else if source == .playlist, let playlist = player.playlistContext {
                if playlist.totalCount == 0 {
                    emptyRow("This playlist is empty.")
                } else {
                    playlistRow(playlist)
                }
                if let error = playlist.loadError {
                    errorRow(error) { playlist.retry() }
                }
            }
        }
        .frame(height: metrics.cardHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            if source == .episodes { await player.episodeBrowser?.loadIfNeeded() }
        }
    }

    private func emptyRow(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(metrics.titleFont)
            .padding(metrics.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: layout.rowHeight)
            .background {
                PlayerOverVideoSurface(focused: false, cornerRadius: metrics.panelCornerRadius)
            }
    }

    private func errorRow(_ error: AppError, retry: @escaping () -> Void) -> some View {
        HStack {
            Text(error.userMessage)
                .font(.caption)
            Button("Try Again", action: retry)
                .font(.caption)
        }
        .padding(.horizontal, cardMetrics.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 36)
        .background {
            PlayerOverVideoSurface(focused: false, cornerRadius: cardMetrics.landscapeCardCornerRadius)
        }
    }

    @ViewBuilder
    private func seasonButton(_ season: MediaItem, in browser: PlayerEpisodeBrowser) -> some View {
        let button = Button {
            Task { await browser.selectSeason(season.id) }
        } label: {
            Text(verbatim: season.title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        if layout.compact {
            button
                .font(.caption2.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(browser.selectedSeasonID == season.id ? .white : .gray)
        } else {
            button
                .buttonStyle(PlozzSeasonTabStyle(
                    isSelected: browser.selectedSeasonID == season.id
                ))
                .focusEffectDisabled()
        }
    }

    private func episodeRow(_ browser: PlayerEpisodeBrowser) -> some View {
        sequenceScroll {
            ForEach(Self.episodeEntries(from: browser), id: \.offset) { index, episode in
                card(episode, index: index, selected: false) {
                    player.playEpisode(episode)
                }
            }
        }
    }

    static func episodeEntries(
        from browser: PlayerEpisodeBrowser
    ) -> [(offset: Int, element: MediaItem)] {
        Array(browser.episodes.enumerated())
    }

    private func playlistRow(_ playlist: VideoPlaylistPlaybackContext) -> some View {
        ScrollViewReader { proxy in
            sequenceScroll {
                ForEach(0..<playlist.totalCount, id: \.self) { index in
                    Group {
                        if let item = playlist.items[index] {
                            card(item, index: index, selected: index == playlist.currentIndex) {
                                Task { await player.playPlaylistItem(at: index) }
                            }
                        } else {
                            RoundedRectangle(cornerRadius: metrics.isVertical ? 14 : cardMetrics.landscapeCardCornerRadius)
                                .fill(.white.opacity(0.12))
                                .frame(
                                    width: metrics.isVertical ? nil : layout.cardWidth,
                                    height: metrics.isVertical ? metrics.castRowHeight : layout.rowHeight
                                )
                                .task(id: playlist.retryGeneration) {
                                    do {
                                        _ = try await playlist.item(at: index)
                                    } catch is CancellationError {
                                        return
                                    } catch {
                                        // The context exposes the error beside the row.
                                    }
                                }
                        }
                    }
                    .id(index)
                }
            }
            .onAppear {
                if playlist.currentIndex > 0 {
                    proxy.scrollTo(
                        playlist.currentIndex, anchor: metrics.isVertical ? .top : .leading
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func sequenceScroll<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if metrics.isVertical {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8, content: content)
                    .padding(.vertical, metrics.contentPadding)
            }
            .frame(height: layout.rowHeight)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: metrics.columnSpacing, content: content)
                    .padding(.trailing, metrics.contentPadding)
            }
            .frame(height: layout.rowHeight)
            .scrollClipDisabled()
        }
    }

    private func card(
        _ item: MediaItem, index: Int, selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if metrics.isVertical {
                    HStack(spacing: 12) {
                        thumbnail(item)
                            .frame(
                                width: (metrics.castRowHeight - 12) * 16 / 9,
                                height: metrics.castRowHeight - 12
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(verbatim: item.title)
                            .font(metrics.castNameFont)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: metrics.castRowHeight)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        thumbnail(item)
                            .frame(width: layout.imageWidth, height: layout.imageHeight)
                            .clipShape(RoundedRectangle(
                                cornerRadius: PlozzTheme.Metrics.mediumMediaCornerRadius,
                                style: .continuous
                            ))
                            .plozzMediaEdge(
                                cornerRadius: PlozzTheme.Metrics.mediumMediaCornerRadius
                            )
                            .overlay(alignment: .bottomLeading) {
                                if source == .episodes, item.episodeNumber != nil,
                                   let subtitle = item.subtitle {
                                    Text(verbatim: subtitle)
                                        .font(metrics.castRoleFont.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.black.opacity(0.72), in: Capsule())
                                        .padding(10)
                                }
                            }
                        Text(verbatim: item.title)
                            .font(metrics.castNameFont)
                            .fontWeight(selected ? .bold : .semibold)
                            .lineLimit(layout.compact ? 1 : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: layout.titleHeight, alignment: .center)
                            .padding(.horizontal, cardMetrics.landscapeCaptionInset)
                            .padding(.top, cardMetrics.landscapeCaptionTopSpacing)
                    }
                    .padding([.top, .horizontal], cardMetrics.cardInset)
                    .padding(.bottom, cardMetrics.cardInset + cardMetrics.landscapeCaptionInset)
                    .frame(width: layout.cardWidth, height: layout.rowHeight, alignment: .topLeading)
                }
            }
        }
        .buttonStyle(PlayerOverVideoCardStyle(
            focused: focus == .sequenceItem(index),
            cornerRadius: metrics.isVertical ? 14 : cardMetrics.landscapeCardCornerRadius,
            focusScale: metrics.isVertical ? 1 : 1.10
        ))
        .focused($focus, equals: .sequenceItem(index))
        .accessibilityLabel(Text(verbatim: item.title))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func thumbnail(_ item: MediaItem) -> some View {
        FallbackAsyncImage(
            references: item.artworkReferences(for: .episodeThumbnail),
            variant: .landscapeCard
        ) {
            Image(systemName: "play.rectangle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.12))
        }
    }
}
#endif
