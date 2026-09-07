#if DEBUG
import CoreUI
import FeatureLiveTVCore
import SwiftUI

enum PrototypeBrowseFocus: Hashable {
    case channel(String)
    case program(channelID: String, programID: String)

    var channelID: String {
        switch self {
        case .channel(let id), .program(let id, _): id
        }
    }
}

struct PrototypeBrowser: View {
    let model: LiveTVPrototypeModel
    let imports: LiveTVPrototypeImportModel
    let guide: Bool
    @Binding var selectedID: String?
    @Binding var railActive: Bool
    let topRequest: Int
    @Binding var guideOffset: TimeInterval
    let tune: (String) -> Void
    let details: (LiveTVPrototypeProgram) -> Void
    let openControls: () -> Void
    let isLoading: Bool
    let loadFailed: Bool
    let reload: () -> Void
    @State private var scrollID: String?
    @State private var pendingFocus: String?
    @State private var lastFocused: PrototypeBrowseFocus?
    @FocusState private var focused: PrototypeBrowseFocus?

    var body: some View {
        GeometryReader { geometry in
            let focusReturnTarget = returnTarget
            VStack(spacing: PrototypeLayout.gap) {
                if guide {
                    PrototypeGuideControls(start: guideStart, offset: $guideOffset)
                        .disabled(railActive)
                    if geometry.size.width >= 650 {
                        PrototypeTimeRuler(start: guideStart, now: model.now, width: geometry.size.width)
                    }
                }
                if isLoading {
                    ContentUnavailableView {
                        Label("Loading your channels", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("The full playlist loads first. Guide listings follow without delaying playback.")
                    }
                } else if model.channels.isEmpty && loadFailed {
                    ContentUnavailableView {
                        Label("Playlist unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check your connection and retry the source.")
                    } actions: {
                        Button("Retry", action: reload).buttonStyle(PrototypeButtonStyle())
                    }
                } else if model.channels.isEmpty {
                    ContentUnavailableView {
                        Label("No supported channels", systemImage: "tv")
                    } description: {
                        Text("The playlist has no supported HTTP or HTTPS streams. Sources shows how many entries were skipped.")
                    } actions: {
                        Button("Reload playlist", action: reload).buttonStyle(PrototypeButtonStyle())
                    }
                } else if model.visibleChannels.isEmpty {
                    ContentUnavailableView {
                        if model.guideOnly && imports.guidePhase == .loading {
                            Label("Loading guide listings", systemImage: "calendar")
                        } else {
                            Label("No matching channels", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    } description: {
                        if model.guideOnly && imports.guidePhase == .loading {
                            Text("Matching channels appear as each guide source loads. Clear filters to browse all channels now.")
                        } else {
                            Text("Try another search or clear your filters.")
                        }
                    } actions: {
                        Button("Clear filters") { model.resetFilters() }
                            .buttonStyle(PrototypeButtonStyle())
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: PrototypeLayout.smallGap) {
                                ForEach(model.visibleChannels) { channel in
                                    if guide {
                                        PrototypeGuideRow(
                                            channel: channel, gapState: imports.gapState(for: channel),
                                            programs: model.programs(for: channel.id, from: guideStart, hours: 2),
                                            start: guideStart, now: model.now,
                                            width: geometry.size.width,
                                            focus: $focused, railActive: railActive,
                                            returnTarget: focusReturnTarget,
                                            favorite: model.favoriteIDs.contains(channel.id),
                                            toggleFavorite: { model.toggleFavorite(channel.id) },
                                            tune: { tune(channel.id) }, details: details,
                                            controls: openControls,
                                            top: { goToTop(proxy) },
                                            goToNow: { guideOffset = 0 }
                                        )
                                        .id(channel.id)
                                        .onAppear { completePendingFocus(channel.id) }
                                    } else {
                                        Button { tune(channel.id) } label: {
                                            PrototypeChannelRow(
                                                channel: channel,
                                                program: model.currentProgram(for: channel.id),
                                                now: model.now,
                                                favorite: model.favoriteIDs.contains(channel.id),
                                                wide: geometry.size.width > 800
                                            )
                                        }
                                        .buttonStyle(PrototypeButtonStyle(
                                            selected: model.playingChannelID == channel.id, padded: false
                                        ))
                                        .focused($focused, equals: .channel(channel.id))
                                        .disabled(railActive && focusReturnTarget != .channel(channel.id))
                                        .id(channel.id)
                                        .accessibilityIdentifier("live-tv-channel-\(channel.number)")
                                        .contextMenu {
                                            Button(
                                                model.favoriteIDs.contains(channel.id)
                                                    ? "Remove from Favorites" : "Add to Favorites",
                                                systemImage: "star"
                                            ) { model.toggleFavorite(channel.id) }
                                            Button("Browse controls", systemImage: "slider.horizontal.3", action: openControls)
                                            Button("Back to top", systemImage: "arrow.up.to.line") { goToTop(proxy) }
                                        }
                                        .onAppear { completePendingFocus(channel.id) }
                                    }
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.vertical, PrototypeLayout.smallGap)
                        }
                        .scrollPosition(id: $scrollID, anchor: .top)
                        .onChange(of: topRequest) { _, _ in goToTop(proxy) }
                    }
                }
            }
        }
        .onChange(of: focused) { _, target in
            if let target {
                selectedID = target.channelID
                lastFocused = target
                railActive = false
            }
        }
        .onChange(of: guide) { _, _ in scrollID = selectedID }
        .onChange(of: model.visibleChannels) { _, channels in
            if !channels.contains(where: { $0.id == selectedID }) {
                selectedID = channels.first?.id
                scrollID = selectedID
                lastFocused = selectedID.map(PrototypeBrowseFocus.channel)
            }
        }
    }

    private var guideStart: Date {
        Date(timeIntervalSince1970: floor(model.now.timeIntervalSince1970 / 1_800) * 1_800 + guideOffset)
    }

    private var returnTarget: PrototypeBrowseFocus? {
        if guide, case .program(let channelID, let programID) = lastFocused,
           model.visibleChannels.contains(where: { $0.id == channelID }),
           LiveTVGuideTimeline.slots(
               programs: model.programs(for: channelID, from: guideStart, hours: 2),
               from: guideStart, to: guideStart.addingTimeInterval(7_200)
           ).contains(where: { $0.program?.id == programID }) {
            return lastFocused
        }
        let channelID = model.visibleChannels.first { $0.id == selectedID }?.id
            ?? model.visibleChannels.first?.id
        return channelID.map(PrototypeBrowseFocus.channel)
    }

    private func completePendingFocus(_ id: String) {
        guard pendingFocus == id else { return }
        focused = .channel(id)
        pendingFocus = nil
    }

    private func goToTop(_ proxy: ScrollViewProxy) {
        guard let first = model.visibleChannels.first else { return }
        railActive = false
        selectedID = first.id
        pendingFocus = first.id
        proxy.scrollTo(first.id, anchor: .top)
        focused = .channel(first.id)
    }
}

private struct PrototypeChannelRow: View {
    let channel: LiveTVPrototypeChannel
    let program: LiveTVPrototypeProgram?
    let now: Date
    let favorite: Bool
    let wide: Bool

    var body: some View {
        HStack(spacing: PrototypeLayout.gap) {
            PrototypeStationMark(channel: channel)
            VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
                HStack(spacing: PrototypeLayout.smallGap) {
                    Text(channel.name).font(.headline).lineLimit(1)
                    if favorite {
                        Image(systemName: "star.fill").font(.caption2)
                            .accessibilityLabel("Favorite")
                    }
                }
                if wide {
                    Text("\(channel.number, format: .number.grouping(.never))  ·  \(channel.category)")
                        .font(.caption).opacity(0.7).lineLimit(1)
                } else if let program {
                    Text(program.title).font(.subheadline).opacity(0.75).lineLimit(1)
                } else {
                    Text(channel.category).font(.subheadline).opacity(0.75).lineLimit(1)
                }
            }
            .frame(maxWidth: wide ? 310 : .infinity, alignment: .leading)
            if wide {
                VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
                    if let program {
                        Text(program.title).font(.headline).lineLimit(1)
                        HStack(spacing: PrototypeLayout.smallGap) {
                            Text(program.start, format: .dateTime.hour().minute())
                            Text("–")
                            Text(program.end, format: .dateTime.hour().minute())
                        }
                        .font(.caption).opacity(0.7)
                        ProgressView(value: program.progress(at: now))
                            .tint(ThemePalette.brandBlue)
                            .frame(maxWidth: 260)
                    } else {
                        Text(channel.tagline).font(.subheadline).opacity(0.75).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(channel.source.title).font(.caption).opacity(0.7)
            } else {
                Text(channel.number, format: .number.grouping(.never))
                    .font(.caption.monospacedDigit()).opacity(0.6)
            }
        }
        .padding(PrototypeLayout.gap)
        .frame(minHeight: PrototypeLayout.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct PrototypeGuideControls: View {
    let start: Date
    @Binding var offset: TimeInterval

    var body: some View {
        HStack {
            Text(start, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.subheadline.monospacedDigit())
                .lineLimit(2)
            Spacer()
            PrototypeGuidePaging(offset: $offset)
        }
        .buttonStyle(PrototypeButtonStyle())
        .font(.subheadline)
    }
}

private struct PrototypeGuidePaging: View {
    @Binding var offset: TimeInterval

    var body: some View {
        HStack(spacing: PrototypeLayout.smallGap) {
            Button("Earlier", systemImage: "chevron.left") { offset = max(-86_400, offset - 7_200) }
                .labelStyle(.iconOnly).disabled(offset <= -86_400)
            Button("Now") { offset = 0 }
            Button("Later", systemImage: "chevron.right") { offset = min(604_800, offset + 7_200) }
                .labelStyle(.iconOnly).disabled(offset >= 604_800)
        }
    }
}

private struct PrototypeTimeRuler: View {
    let start: Date
    let now: Date
    let width: CGFloat
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: PrototypeLayout.smallGap) {
            Text("Channel")
                .frame(width: width > 1_100 ? 300 : 210, alignment: .leading)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach([0, 3_600], id: \.self) { seconds in
                        Text(start.addingTimeInterval(TimeInterval(seconds)), format: .dateTime.hour().minute())
                            .frame(width: geometry.size.width / 2, alignment: .leading)
                    }
                }
                if start <= now && now < start.addingTimeInterval(7_200) {
                    Rectangle().fill(ThemePalette.brandBlue)
                        .frame(width: 2, height: 22)
                        .offset(x: geometry.size.width * now.timeIntervalSince(start) / 7_200)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 24)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(palette.secondaryText)
    }
}

private struct PrototypeGuideRow: View {
    let channel: LiveTVPrototypeChannel
    let gapState: LiveTVGuideGapState
    let programs: [LiveTVPrototypeProgram]
    let start: Date
    let now: Date
    let width: CGFloat
    let focus: FocusState<PrototypeBrowseFocus?>.Binding
    let railActive: Bool
    let returnTarget: PrototypeBrowseFocus?
    let favorite: Bool
    let toggleFavorite: () -> Void
    let tune: () -> Void
    let details: (LiveTVPrototypeProgram) -> Void
    let controls: () -> Void
    let top: () -> Void
    let goToNow: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        if width < 650 {
            VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
                PrototypeGuideStation(
                    channel: channel, favorite: favorite, tune: tune, toggleFavorite: toggleFavorite,
                    controls: controls, top: top
                )
                    .focused(focus, equals: .channel(channel.id))
                    .disabled(railActive && returnTarget != .channel(channel.id))
                ForEach(programs) { program in
                    Button { details(program) } label: {
                        PrototypeProgramLabel(program: program, now: now)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PrototypeButtonStyle())
                    .focused(focus, equals: .program(channelID: channel.id, programID: program.id))
                    .disabled(railActive && returnTarget != .program(channelID: channel.id, programID: program.id))
                }
                if programs.isEmpty { PrototypeGuideGap(state: gapState) }
            }
            .padding(.bottom, PrototypeLayout.gap)
        } else {
            HStack(spacing: PrototypeLayout.smallGap) {
                PrototypeGuideStation(
                    channel: channel, favorite: favorite, tune: tune, toggleFavorite: toggleFavorite,
                    controls: controls, top: top
                )
                    .frame(width: width > 1_100 ? 300 : 210)
                    .focused(focus, equals: .channel(channel.id))
                    .disabled(railActive && returnTarget != .channel(channel.id))
                HStack(spacing: 0) {
                    ForEach(LiveTVGuideTimeline.slots(
                        programs: programs, from: start, to: start.addingTimeInterval(7_200)
                    )) { slot in
                        if let program = slot.program {
                            Button { details(program) } label: {
                                PrototypeProgramLabel(program: program, now: now)
                                    .frame(maxWidth: .infinity, minHeight: PrototypeLayout.rowHeight, alignment: .leading)
                                    .padding(.horizontal, PrototypeLayout.smallGap)
                            }
                            .buttonStyle(PrototypeButtonStyle(
                                selected: program.start <= now && now < program.end, padded: false
                            ))
                            .frame(width: slotWidth(slot))
                            .clipped()
                            .focused(focus, equals: .program(channelID: channel.id, programID: program.id))
                            .disabled(
                                railActive && returnTarget != .program(channelID: channel.id, programID: program.id)
                            )
                            .contextMenu {
                                Button("Watch channel live", systemImage: "play.fill", action: tune)
                                Button(
                                    favorite ? "Remove from Favorites" : "Add to Favorites",
                                    systemImage: "star", action: toggleFavorite
                                )
                                Button("Browse controls", systemImage: "slider.horizontal.3", action: controls)
                                Button("Back to top", systemImage: "arrow.up.to.line", action: top)
                                Button("Now", systemImage: "clock", action: goToNow)
                            }
                        } else {
                            PrototypeGuideGap(state: gapState).frame(width: slotWidth(slot)).clipped()
                        }
                    }
                }
            }
        }
    }

    private func slotWidth(_ slot: LiveTVGuideSlot) -> CGFloat {
        let seconds = slot.end.timeIntervalSince(slot.start)
        let stationWidth: CGFloat = width > 1_100 ? 300 : 210
        return max(0, width - stationWidth - PrototypeLayout.smallGap) * seconds / 7_200
    }
}

private struct PrototypeGuideStation: View {
    let channel: LiveTVPrototypeChannel
    let favorite: Bool
    let tune: () -> Void
    let toggleFavorite: () -> Void
    let controls: () -> Void
    let top: () -> Void

    var body: some View {
        Button(action: tune) {
            HStack(spacing: PrototypeLayout.smallGap) {
                PrototypeStationMark(channel: channel, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack {
                        Text(channel.number, format: .number.grouping(.never))
                        if favorite { Image(systemName: "star.fill").accessibilityLabel("Favorite") }
                    }
                    .font(.caption).opacity(0.7)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: PrototypeLayout.rowHeight)
            .padding(.horizontal, PrototypeLayout.smallGap)
        }
        .buttonStyle(PrototypeButtonStyle(padded: false))
        .contextMenu {
            Button(
                favorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: "star", action: toggleFavorite
            )
            Button("Browse controls", systemImage: "slider.horizontal.3", action: controls)
            Button("Back to top", systemImage: "arrow.up.to.line", action: top)
        }
    }
}

struct PrototypeProgramLabel: View {
    let program: LiveTVPrototypeProgram
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
            Text(program.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(program.start, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit()).opacity(0.7)
            if program.start <= now && now < program.end {
                ProgressView(value: program.progress(at: now)).tint(ThemePalette.brandBlue)
                    .accessibilityLabel("Program progress")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PrototypeGuideGap: View {
    let state: LiveTVGuideGapState
    @Environment(\.themePalette) private var palette
    var body: some View {
        Text(state.title)
            .font(.subheadline).foregroundStyle(palette.secondaryText).lineLimit(2)
            .padding(.horizontal, PrototypeLayout.smallGap)
            .frame(maxWidth: .infinity, minHeight: PrototypeLayout.rowHeight)
            .background(palette.fillSubtle, in: RoundedRectangle(cornerRadius: PrototypeLayout.radius))
    }
}
#endif
