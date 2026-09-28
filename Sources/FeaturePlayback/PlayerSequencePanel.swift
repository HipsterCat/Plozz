#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

struct PlayerSequenceLayout {
    let metrics: PlayerCardMetrics
    let cardMetrics: PlozzMetrics
    let contained: Bool
    let hasError: Bool

    var compact: Bool { metrics.contentHeight < 160 }
    var gap: CGFloat { compact ? 6 : 10 }
    var columnSpacing: CGFloat {
        metrics.columnSpacing + (contained ? metrics.contentPadding / 2 : 0)
    }
    var containerVerticalInset: CGFloat { contained ? metrics.contentPadding / 2 : 0 }
    var rowHeight: CGFloat {
        metrics.cardHeight - containerVerticalInset * 2
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

/// Episode cards live inside one player panel; playlist cards stand alone.
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
            contained: source == .episodes,
            hasError: source == .playlist && player.playlistContext?.loadError != nil
        )
    }

    var body: some View {
        Group {
            if source == .episodes {
                content
                    .frame(height: metrics.cardHeight - layout.containerVerticalInset * 2)
                    .padding(.horizontal, metrics.contentPadding)
                    .padding(.vertical, layout.containerVerticalInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(PanelGlassBackground(cornerRadius: metrics.panelCornerRadius))
            } else {
                content.frame(height: metrics.cardHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            if source == .episodes { await player.episodeBrowser?.loadIfNeeded() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: layout.gap) {
            if source == .episodes, let browser = player.episodeBrowser {
                episodeContent(browser)
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
    }

    @ViewBuilder
    private func episodeContent(_ browser: PlayerEpisodeBrowser) -> some View {
        if let error = browser.loadError {
            errorRow(error) { Task { await browser.loadIfNeeded() } }
        } else if browser.isLoading {
            ProgressView("Loading episodes…")
        } else if browser.episodes.isEmpty {
            emptyRow("No episodes available")
        } else {
            episodeRow(browser)
        }
    }

    private func emptyRow(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(metrics.titleFont)
            .padding(metrics.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: layout.rowHeight)
            .background {
                if source == .playlist {
                    PlayerOverVideoSurface(focused: false, cornerRadius: metrics.panelCornerRadius)
                }
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
            if source == .playlist {
                PlayerOverVideoSurface(focused: false, cornerRadius: cardMetrics.landscapeCardCornerRadius)
            }
        }
    }

    private func episodeRetry(
        _ error: AppError, title: LocalizedStringKey, retry: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(metrics.castNameFont)
            Text(error.userMessage)
                .font(.caption)
                .lineLimit(2)
            Button("Try Again", action: retry)
                .font(.caption)
        }
        .padding(metrics.contentPadding)
        .frame(
            width: metrics.isVertical ? nil : layout.cardWidth,
            height: metrics.isVertical ? max(120, metrics.castRowHeight) : layout.rowHeight,
            alignment: .leading
        )
        .background(.white.opacity(0.08), in: RoundedRectangle(
            cornerRadius: cardMetrics.landscapeCardCornerRadius,
            style: .continuous
        ))
    }

    private func episodeRow(_ browser: PlayerEpisodeBrowser) -> some View {
        ScrollViewReader { proxy in
            sequenceScroll {
                if let error = browser.previousLoadError {
                    episodeRetry(error, title: "Earlier episodes") {
                        Task { await browser.retryPrevious() }
                    }
                }
                ForEach(Self.episodeEntries(from: browser)) { entry in
                    card(
                        entry.item, focusSlot: .episodeItem(entry.id),
                        selected: false, episodeBadge: entry.badge
                    ) {
                        player.playEpisode(entry.item)
                    }
                    .id(entry.id)
                    .task(id: browser.previousSeasonIndex) {
                        guard entry.id == browser.episodes.first?.id else { return }
                        await browser.loadPrevious()
                    }
                    .task(id: browser.nextSeasonIndex) {
                        guard entry.id == browser.episodes.last?.id else { return }
                        await browser.loadNext()
                    }
                }
                if let error = browser.nextLoadError {
                    episodeRetry(error, title: "Later episodes") {
                        Task { await browser.retryNext() }
                    }
                }
            }
            .onAppear {
                if let id = browser.initialEntryID {
                    proxy.scrollTo(id, anchor: metrics.isVertical ? .top : .leading)
                }
            }
            .onChange(of: browser.prependAnchorID) { _, id in
                if let id {
                    proxy.scrollTo(id, anchor: metrics.isVertical ? .top : .leading)
                }
            }
        }
    }

    static func episodeEntries(from browser: PlayerEpisodeBrowser) -> [PlayerEpisodeEntry] {
        browser.episodes
    }

    private func playlistRow(_ playlist: VideoPlaylistPlaybackContext) -> some View {
        ScrollViewReader { proxy in
            sequenceScroll {
                ForEach(0..<playlist.totalCount, id: \.self) { index in
                    Group {
                        if let item = playlist.items[index] {
                            card(
                                item, focusSlot: .sequenceItem(index),
                                selected: index == playlist.currentIndex
                            ) {
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
                LazyHStack(spacing: layout.columnSpacing, content: content)
                    .padding(.trailing, metrics.contentPadding)
            }
            .frame(height: layout.rowHeight)
            .scrollClipDisabled()
        }
    }

    private func card(
        _ item: MediaItem, focusSlot: PlayerControls.FocusSlot, selected: Bool,
        episodeBadge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focus == focusSlot
        return Button(action: action) {
            Group {
                if metrics.isVertical {
                    HStack(spacing: 12) {
                        thumbnail(item)
                            .frame(
                                width: (metrics.castRowHeight - 12) * 16 / 9,
                                height: metrics.castRowHeight - 12
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            if let episodeBadge {
                                Text(verbatim: episodeBadge)
                                    .font(metrics.castRoleFont)
                                    .foregroundStyle(.secondary)
                            }
                            Text(verbatim: item.title)
                                .font(metrics.castNameFont)
                                .lineLimit(2)
                        }
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
                                if source == .episodes, let episodeBadge {
                                    Text(verbatim: episodeBadge)
                                        .font(metrics.castRoleFont.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.black.opacity(0.72), in: Capsule())
                                        .padding(10)
                                }
                            }
                            .overlay {
                                if source == .episodes, isFocused {
                                    RoundedRectangle(
                                        cornerRadius: PlozzTheme.Metrics.mediumMediaCornerRadius,
                                        style: .continuous
                                    )
                                    .strokeBorder(.white.opacity(0.92), lineWidth: 4)
                                }
                            }
                            .scaleEffect(source == .episodes && isFocused ? 1.035 : 1)
                            .animation(.easeOut(duration: 0.18), value: isFocused)
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
        .buttonStyle(PlayerSequenceCardStyle(
            focused: isFocused,
            cornerRadius: metrics.isVertical ? 14 : cardMetrics.landscapeCardCornerRadius,
            contained: source == .episodes,
            focusScale: metrics.isVertical ? 1 : 1.10
        ))
        .focusEffectDisabled(source == .episodes)
        .focused($focus, equals: focusSlot)
        .accessibilityLabel(Text(verbatim: [episodeBadge, item.title]
            .compactMap { $0 }.joined(separator: " · ")))
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

private struct PlayerSequenceCardStyle: ButtonStyle {
    let focused: Bool
    let cornerRadius: CGFloat
    let contained: Bool
    let focusScale: CGFloat

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if contained {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        } else {
            PlayerOverVideoCardStyle(
                focused: focused, cornerRadius: cornerRadius, focusScale: focusScale
            ).makeBody(configuration: configuration)
        }
    }
}
#endif
