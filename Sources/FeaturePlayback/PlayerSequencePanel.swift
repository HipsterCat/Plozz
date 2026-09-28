#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

/// One fixed-height player card for season episodes or the active playlist.
/// The horizontal row constructs only visible cards and requests pages on demand.
struct PlayerSequencePanel: View {
    enum Source: Equatable { case episodes, playlist }

    @Environment(\.playerCardMetrics) private var metrics
    let player: PlayerViewModel
    let source: Source
    @FocusState.Binding var focus: PlayerControls.FocusSlot?

    private var compact: Bool { metrics.contentHeight < 160 }
    private var tileWidth: CGFloat { compact ? 80 : 164 }
    private var thumbnailHeight: CGFloat { compact ? 44 : 92 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            if source == .episodes, let browser = player.episodeBrowser {
                if !browser.seasons.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(browser.seasons, id: \.id) { season in
                                Button {
                                    Task { await browser.selectSeason(season.id) }
                                } label: {
                                    Text(verbatim: season.title)
                                        .font(compact ? .caption2.weight(.semibold) : .subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, compact ? 4 : 6)
                                }
                                .buttonStyle(.bordered)
                                .tint(browser.selectedSeasonID == season.id ? .white : .gray)
                            }
                        }
                    }
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
                } else {
                    episodeRow(browser)
                }
            } else if source == .playlist, let playlist = player.playlistContext {
                playlistRow(playlist)
                if let error = playlist.loadError {
                    errorRow(error) { playlist.retry() }
                }
            }
        }
        .padding(metrics.contentPadding)
        .modifier(PlayerCardHeight(metrics: metrics))
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PanelGlassBackground(cornerRadius: metrics.panelCornerRadius))
        .task {
            if source == .episodes { await player.episodeBrowser?.loadIfNeeded() }
        }
    }

    private func errorRow(_ error: AppError, retry: @escaping () -> Void) -> some View {
        HStack {
            Text(error.userMessage)
                .font(.caption)
            Button("Try Again", action: retry)
                .font(.caption)
        }
    }

    private func episodeRow(_ browser: PlayerEpisodeBrowser) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 18) {
                ForEach(browser.episodes.indices, id: \.self) { index in
                    card(browser.episodes[index], index: index, selected: false) {
                        player.playEpisode(browser.episodes[index])
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, compact ? 2 : 12)
        }
    }

    private func playlistRow(_ playlist: VideoPlaylistPlaybackContext) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(0..<playlist.totalCount, id: \.self) { index in
                        Group {
                            if let item = playlist.items[index] {
                                card(item, index: index, selected: index == playlist.currentIndex) {
                                    Task { await player.playPlaylistItem(at: index) }
                                }
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.12))
                                    .frame(width: tileWidth, height: compact ? 76 : 150)
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
                .padding(.horizontal, 6)
                .padding(.vertical, compact ? 2 : 12)
            }
            .onAppear { proxy.scrollTo(playlist.currentIndex, anchor: .center) }
        }
    }

    private func card(
        _ item: MediaItem, index: Int, selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                FallbackAsyncImage(
                    references: item.artworkReferences(for: .episodeThumbnail),
                    variant: .landscapeCard
                ) {
                    Image(systemName: "play.rectangle")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.12))
                }
                .frame(width: tileWidth, height: thumbnailHeight)
                .clipped()
                Text(verbatim: item.title)
                    .font(.caption.weight(selected ? .bold : .medium))
                    .lineLimit(2)
                    .frame(height: compact ? 24 : 40, alignment: .topLeading)
            }
            .frame(width: tileWidth)
            .padding(compact ? 2 : 5)
        }
        .buttonStyle(PlayerOverVideoCardStyle(
            focused: focus == .sequenceItem(index),
            cornerRadius: 12
        ))
        .focused($focus, equals: .sequenceItem(index))
        .accessibilityLabel(Text(verbatim: item.title))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
#endif
