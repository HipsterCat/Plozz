#if DEBUG
import CoreUI
import CoreModels
import FeatureLiveTVCore
import SwiftUI

typealias PrototypeBrowseFocus = LiveTVGuideFocusTarget

struct PrototypeBrowser: View {
    let model: LiveTVPrototypeModel
    let imports: LiveTVPrototypeImportModel
    @Binding var selectedID: String?
    @Binding var railActive: Bool
    @Binding var focusedProgram: LiveTVPrototypeProgram?
    @Binding var hasFocus: Bool
    let topRequest: Int
    @Binding var guideOffset: TimeInterval
    let restoreFocusRequest: Int
    let isPresented: Bool
    let isRestoringFocus: Bool
    let focusRestored: (Int) -> Void
    let tune: (String) -> Void
    let details: (LiveTVPrototypeProgram) -> Void
    let openControls: () -> Void
    let openToolbar: () -> Void
    let isLoading: Bool
    let loadFailed: Bool
    let reload: () -> Void
    @State private var scrollID: String?
    @State private var pendingFocus: PrototypeBrowseFocus?
    @State private var restorationFallback: PrototypeBrowseFocus?
    @State private var lastFocused: PrototypeBrowseFocus?
    @State private var timelineOffset: CGFloat = 0
    @State private var timeAnchor = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 1_800) * 1_800)
    @FocusState private var focused: PrototypeBrowseFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let focusReturnTarget = returnTarget
            VStack(spacing: PrototypeLayout.smallGap) {
                if model.guideChannelCount > 0 {
                    if geometry.size.width >= 650 {
                        PrototypeTimeRuler(
                            start: guideStart, now: model.now, width: geometry.size.width,
                            timelineOffset: timelineOffset, guideOffset: $guideOffset,
                            goToNow: goToNow
                        )
                        .disabled(railActive || isRestoringFocus)
                    } else {
                        PrototypeGuidePaging(start: guideStart, offset: $guideOffset, goToNow: goToNow)
                            .disabled(railActive || isRestoringFocus)
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
                                    PrototypeGuideRow(
                                        channel: channel,
                                        programs: model.programs(
                                            for: channel.id, from: guideStart,
                                            hours: geometry.size.width >= 650 ? 6 : 2
                                        ),
                                        start: guideStart, now: model.now,
                                        width: geometry.size.width, timelineOffset: $timelineOffset,
                                        focus: $focused, railActive: railActive || isRestoringFocus,
                                        returnTarget: focusReturnTarget,
                                        favorite: model.favoriteIDs.contains(channel.id),
                                        playing: model.playingChannelID == channel.id,
                                        toggleFavorite: { model.toggleFavorite(channel.id) },
                                        tune: { tune(channel.id) }, details: details,
                                        controls: openControls,
                                        top: { goToTop(proxy) },
                                        goToNow: goToNow
                                    )
                                    .id(channel.id)
                                    .onAppear { completePendingFocus(channel.id) }
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.vertical, PrototypeLayout.smallGap)
                        }
                        .scrollIndicators(.hidden)
                        .overlay(alignment: .topLeading) {
                            if geometry.size.width >= 650, model.guideChannelCount > 0 {
                                HStack(spacing: PrototypeLayout.smallGap) {
                                    Color.clear.frame(width: PrototypeLayout.stationWidth(for: geometry.size.width))
                                    PrototypeNowLine(start: guideStart, now: model.now, timelineOffset: timelineOffset)
                                }
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                        }
                        .scrollPosition(id: $scrollID, anchor: .top)
                        .onChange(of: topRequest) { _, _ in goToTop(proxy) }
                        .task(id: isPresented && isRestoringFocus ? restoreFocusRequest : -1) {
                            guard isPresented, isRestoringFocus else { return }
                            let request = restoreFocusRequest
                            guard let target = playbackReturnTarget else {
                                focusRestored(request)
                                return
                            }
                            pendingFocus = nil
                            restorationFallback = nil
                            revealCurrentProgram(width: geometry.size.width)
                            if lastFocused?.channelID != target.channelID {
                                proxy.scrollTo(target.channelID, anchor: .center)
                            }
                            if reduceMotion { await Task.yield() }
                            else { try? await Task.sleep(for: .milliseconds(340)) }
                            guard !Task.isCancelled else { return }
                            guard let latestTarget = playbackReturnTarget else {
                                focusRestored(request)
                                return
                            }
                            revealCurrentProgram(width: geometry.size.width)
                            if latestTarget.channelID != target.channelID {
                                proxy.scrollTo(latestTarget.channelID, anchor: .center)
                                await Task.yield()
                            }
                            focused = latestTarget
                            pendingFocus = nil
                            await Task.yield()
                            guard !Task.isCancelled else { return }
                            if focused == latestTarget {
                                focusRestored(request)
                                return
                            }
                            restorationFallback = .channel(latestTarget.channelID)
                            proxy.scrollTo(latestTarget.channelID, anchor: .center)
                            await Task.yield()
                            guard !Task.isCancelled else { return }
                            HandoffDiagnostics.emit("LIVE_TV event=guideFocusFallback kind=channel")
                            focused = restorationFallback
                            await Task.yield()
                            guard !Task.isCancelled else { return }
                            if focused != restorationFallback {
                                HandoffDiagnostics.emit("LIVE_TV event=guideFocusRestore result=unconfirmed")
                            }
                            focusRestored(request)
                        }
                    }
                }
            }
            .onChange(of: geometry.size.width) { old, new in
                let oldWidth = max(1, old - PrototypeLayout.stationWidth(for: old) - PrototypeLayout.smallGap)
                let newWidth = max(1, new - PrototypeLayout.stationWidth(for: new) - PrototypeLayout.smallGap)
                timelineOffset = new < 650 ? 0 : min(newWidth * 2, timelineOffset / oldWidth * newWidth)
            }
        }
        #if os(tvOS)
        .onExitCommand {
            if !isRestoringFocus { openToolbar() }
        }
        #endif
        .onChange(of: focused, initial: true) { _, target in
            hasFocus = target != nil
            if let target {
                switch target {
                case .channel:
                    focusedProgram = nil
                case .program(let channelID, let programID):
                    focusedProgram = model.programs(for: channelID, from: guideStart, hours: 6)
                        .first { $0.id == programID }
                }
                selectedID = target.channelID
                lastFocused = target
                railActive = false
                if isRestoringFocus, target == returnTarget {
                    focusRestored(restoreFocusRequest)
                }
            }
        }
        .onChange(of: guideOffset) { _, _ in timelineOffset = 0 }
        .onChange(of: isRestoringFocus) { _, restoring in
            if !restoring { restorationFallback = nil }
            if restoring, playbackReturnTarget == nil {
                focusRestored(restoreFocusRequest)
            }
        }
        .onChange(of: model.visibleChannels) { _, channels in
            if channels.isEmpty, isRestoringFocus {
                focusRestored(restoreFocusRequest)
            }
            if !channels.contains(where: { $0.id == selectedID }) {
                focusedProgram = nil
                selectedID = channels.first?.id
                scrollID = selectedID
                lastFocused = selectedID.map(PrototypeBrowseFocus.channel)
            }
        }
        .onDisappear { hasFocus = false }
    }

    private var guideStart: Date {
        timeAnchor.addingTimeInterval(guideOffset)
    }

    private var returnTarget: PrototypeBrowseFocus? {
        if isRestoringFocus { return restorationFallback ?? playbackReturnTarget }
        if case .program(let channelID, let programID) = lastFocused,
           model.visibleChannels.contains(where: { $0.id == channelID }),
           LiveTVGuideTimeline.slots(
               programs: model.programs(for: channelID, from: guideStart, hours: 6),
               from: guideStart, to: guideStart.addingTimeInterval(21_600)
           ).contains(where: { $0.program?.id == programID }) {
            return lastFocused
        }
        let channelID = model.visibleChannels.first { $0.id == selectedID }?.id
            ?? model.visibleChannels.first?.id
        return channelID.map(PrototypeBrowseFocus.channel)
    }

    private var playbackReturnTarget: PrototypeBrowseFocus? {
        .returningToPlayback(in: model, selectedChannelID: selectedID)
    }

    private func completePendingFocus(_ id: String) {
        guard !isRestoringFocus, pendingFocus?.channelID == id else { return }
        focused = pendingFocus
        pendingFocus = nil
    }

    private func revealCurrentProgram(width: CGFloat) {
        guard let target = playbackReturnTarget,
              let program = model.currentProgram(for: target.channelID) else { return }
        if model.now < guideStart || model.now >= guideStart.addingTimeInterval(21_600) {
            goToNow()
        }
        let timelineWidth = max(1, width - PrototypeLayout.stationWidth(for: width) - PrototypeLayout.smallGap)
        let visibleStart = guideStart.addingTimeInterval(Double(timelineOffset / timelineWidth) * 7_200)
        let visibleEnd = visibleStart.addingTimeInterval(7_200)
        if program.end <= visibleStart || program.start >= visibleEnd {
            timelineOffset = min(timelineWidth * 2, max(
                0, timelineWidth * (model.now.timeIntervalSince(guideStart) - 1_800) / 7_200
            ))
        }
    }

    private func goToNow() {
        timeAnchor = Date(timeIntervalSince1970: floor(model.now.timeIntervalSince1970 / 1_800) * 1_800)
        guideOffset = 0
        timelineOffset = 0
    }

    private func goToTop(_ proxy: ScrollViewProxy) {
        guard let first = model.visibleChannels.first else { return }
        railActive = false
        selectedID = first.id
        focusedProgram = nil
        pendingFocus = .channel(first.id)
        proxy.scrollTo(first.id, anchor: .top)
        focused = .channel(first.id)
    }
}

private struct PrototypeGuidePaging: View {
    let start: Date
    @Binding var offset: TimeInterval
    let goToNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(start, format: .dateTime.month(.abbreviated).day())
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: PrototypeLayout.smallGap) {
            Button { offset = max(-86_400, offset - 7_200) } label: {
                Image(systemName: "chevron.backward").frame(minWidth: 36, minHeight: 36)
            }
            .accessibilityLabel("Earlier").disabled(offset <= -86_400)
            Button(action: goToNow) {
                Text("Now").padding(.horizontal, 12).frame(minHeight: 36)
            }
            Button { offset = min(604_800, offset + 7_200) } label: {
                Image(systemName: "chevron.forward").frame(minWidth: 36, minHeight: 36)
            }
            .accessibilityLabel("Later").disabled(offset >= 604_800)
            }
        }
        .font(.caption)
        .buttonStyle(PrototypeButtonStyle(padded: false))
    }
}

private struct PrototypeTimeRuler: View {
    let start: Date
    let now: Date
    let width: CGFloat
    let timelineOffset: CGFloat
    @Binding var guideOffset: TimeInterval
    let goToNow: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(alignment: .bottom, spacing: PrototypeLayout.smallGap) {
            PrototypeGuidePaging(start: start, offset: $guideOffset, goToNow: goToNow)
                .frame(width: PrototypeLayout.stationWidth(for: width), alignment: .leading)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(0..<12, id: \.self) { tick in
                        Text(start.addingTimeInterval(TimeInterval(tick * 1_800)), format: .dateTime.hour().minute())
                            .lineLimit(1)
                            .frame(width: geometry.size.width / 4, alignment: .leading)
                    }
                }
                .offset(x: -timelineOffset)
                PrototypeNowLine(start: start, now: now, timelineOffset: timelineOffset)
            }
            .frame(height: 24)
            .clipped()
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(palette.secondaryText)
    }
}

private struct PrototypeNowLine: View {
    let start: Date
    let now: Date
    let timelineOffset: CGFloat
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        GeometryReader { geometry in
            let x = geometry.size.width * now.timeIntervalSince(start) / 7_200 - timelineOffset
            if x >= 0, x <= geometry.size.width {
                Rectangle().fill(ThemePalette.brandBlue.opacity(0.8))
                    .frame(width: 2, height: geometry.size.height)
                    .position(
                        x: direction == .rightToLeft ? geometry.size.width - x : x,
                        y: geometry.size.height / 2
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PrototypeGuideRow: View {
    let channel: LiveTVPrototypeChannel
    let programs: [LiveTVPrototypeProgram]
    let start: Date
    let now: Date
    let width: CGFloat
    @Binding var timelineOffset: CGFloat
    let focus: FocusState<PrototypeBrowseFocus?>.Binding
    let railActive: Bool
    let returnTarget: PrototypeBrowseFocus?
    let favorite: Bool
    let playing: Bool
    let toggleFavorite: () -> Void
    let tune: () -> Void
    let details: (LiveTVPrototypeProgram) -> Void
    let controls: () -> Void
    let top: () -> Void
    let goToNow: () -> Void
    @Environment(\.themePalette) private var palette
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = PrototypeLayout.rowHeight

    var body: some View {
        if width < 650 {
            VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
                PrototypeGuideStation(
                    channel: channel, favorite: favorite, playing: playing, tune: tune, toggleFavorite: toggleFavorite,
                    controls: controls, top: top, subtitle: programs.isEmpty ? channel.category : nil
                )
                    .focused(focus, equals: .channel(channel.id))
                    .disabled(railActive && returnTarget != .channel(channel.id))
                if !programs.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: PrototypeLayout.smallGap) {
                            ForEach(programs) { program in
                                Button { open(program) } label: {
                                    PrototypeProgramLabel(program: program, now: now)
                                        .frame(width: 230, alignment: .leading)
                                }
                                .buttonStyle(PrototypeButtonStyle())
                                .focused(focus, equals: .program(channelID: channel.id, programID: program.id))
                                .disabled(railActive && returnTarget != .program(channelID: channel.id, programID: program.id))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.bottom, PrototypeLayout.gap)
        } else {
            HStack(spacing: PrototypeLayout.smallGap) {
                PrototypeGuideStation(
                    channel: channel, favorite: favorite, playing: playing, tune: tune, toggleFavorite: toggleFavorite,
                    controls: controls, top: top, height: rowHeight
                )
                    .frame(width: PrototypeLayout.stationWidth(for: width))
                    .focused(focus, equals: .channel(channel.id))
                    .disabled(railActive && returnTarget != .channel(channel.id))
                if programs.isEmpty {
                    PrototypeGuideGap(category: channel.category, height: rowHeight)
                        .frame(maxWidth: .infinity)
                } else {
                    PrototypeSynchronizedTimeline(
                        offset: $timelineOffset,
                        isFocusedRow: focus.wrappedValue?.channelID == channel.id,
                        viewportWidth: timelineWidth
                    ) {
                        HStack(spacing: 0) {
                            ForEach(LiveTVGuideTimeline.slots(
                                programs: programs, from: start, to: start.addingTimeInterval(21_600)
                            )) { slot in
                                if let program = slot.program {
                                    Button { open(program) } label: {
                                        PrototypeProgramLabel(
                                            program: program, now: now,
                                            availableWidth: max(0, cellWidth(slot) - PrototypeLayout.smallGap * 2)
                                        )
                                        .padding(.horizontal, min(PrototypeLayout.smallGap, slotWidth(slot) / 4))
                                        .frame(width: cellWidth(slot), height: rowHeight, alignment: .leading)
                                        .clipped()
                                    }
                                    .buttonStyle(PrototypeButtonStyle(padded: false))
                                    .padding(.trailing, min(4, slotWidth(slot) / 4))
                                    .frame(width: slotWidth(slot), height: rowHeight)
                                    .clipped()
                                    .focused(focus, equals: .program(channelID: channel.id, programID: program.id))
                                    .disabled(
                                        railActive && returnTarget != .program(channelID: channel.id, programID: program.id)
                                    )
                                    .contextMenu {
                                        Button("Program details", systemImage: "info.circle") { details(program) }
                                        Button("Watch channel live", systemImage: "play.fill", action: tune)
                                        Button(
                                            favorite ? "Remove from Favorites" : "Add to Favorites",
                                            systemImage: "star", action: toggleFavorite
                                        )
                                        Button("Search and options", systemImage: "magnifyingglass", action: controls)
                                        Button("Back to top", systemImage: "arrow.up.to.line", action: top)
                                        Button("Now", systemImage: "clock", action: goToNow)
                                    }
                                } else {
                                    PrototypeGuideGap(category: channel.category, height: rowHeight)
                                        .frame(width: slotWidth(slot)).clipped()
                                }
                            }
                        }
                        .frame(width: timelineWidth * 3, height: rowHeight)
                    }
                    .frame(width: timelineWidth, height: rowHeight)
                }
            }
            .frame(height: rowHeight)
        }
    }

    private func slotWidth(_ slot: LiveTVGuideSlot) -> CGFloat {
        let seconds = slot.end.timeIntervalSince(slot.start)
        return timelineWidth * seconds / 7_200
    }

    private func cellWidth(_ slot: LiveTVGuideSlot) -> CGFloat {
        slotWidth(slot) - min(4, slotWidth(slot) / 4)
    }

    private var timelineWidth: CGFloat {
        max(1, width - PrototypeLayout.stationWidth(for: width) - PrototypeLayout.smallGap)
    }

    private func open(_ program: LiveTVPrototypeProgram) {
        if program.start <= now && now < program.end { tune() }
        else { details(program) }
    }
}

private struct PrototypeGuideStation: View {
    let channel: LiveTVPrototypeChannel
    let favorite: Bool
    let playing: Bool
    let tune: () -> Void
    let toggleFavorite: () -> Void
    let controls: () -> Void
    let top: () -> Void
    var subtitle: String? = nil
    var height: CGFloat? = nil

    var body: some View {
        Button(action: tune) {
            HStack(spacing: PrototypeLayout.smallGap) {
                PrototypeStationMark(channel: channel, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.subheadline).opacity(0.75).lineLimit(1)
                    }
                    HStack {
                        Text(channel.number, format: .number.grouping(.never))
                        if playing {
                            Image(systemName: "speaker.wave.2.fill").accessibilityLabel("Current channel")
                        }
                        if favorite { Image(systemName: "star.fill").accessibilityLabel("Favorite") }
                    }
                    .font(.caption).opacity(0.7)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: PrototypeLayout.rowHeight)
            .padding(.horizontal, PrototypeLayout.smallGap)
            .frame(height: height)
            .clipped()
        }
        .buttonStyle(PrototypeButtonStyle(selected: playing, padded: false))
        .accessibilityIdentifier("live-tv-channel-\(channel.number)")
        .contextMenu {
            Button(
                favorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: "star", action: toggleFavorite
            )
            Button("Search and options", systemImage: "magnifyingglass", action: controls)
            Button("Back to top", systemImage: "arrow.up.to.line", action: top)
        }
    }
}

struct PrototypeProgramLabel: View {
    let program: LiveTVPrototypeProgram
    let now: Date
    var availableWidth: CGFloat? = nil
    @ScaledMetric(relativeTo: .subheadline) private var minimumTitleWidth: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
            if let availableWidth, availableWidth < minimumTitleWidth {
                Image(systemName: "ellipsis").font(.caption)
            } else {
                Text(program.title).font(.subheadline.weight(.semibold))
                    .lineLimit(availableWidth == nil ? 2 : 1)
            }
            if availableWidth == nil {
                Text(program.start, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit()).opacity(0.7)
                    .lineLimit(1)
            }
            if availableWidth == nil, program.start <= now && now < program.end {
                ProgressView(value: program.progress(at: now)).tint(ThemePalette.brandBlue)
                    .accessibilityLabel("Program progress")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(program.title))
        .accessibilityValue(
            Text("\(program.start, format: .dateTime.hour().minute()) to \(program.end, format: .dateTime.hour().minute())")
        )
    }
}

private struct PrototypeGuideGap: View {
    let category: String
    let height: CGFloat
    @Environment(\.themePalette) private var palette
    var body: some View {
        Text(category)
            .font(.subheadline).foregroundStyle(palette.secondaryText).lineLimit(2)
            .padding(.horizontal, PrototypeLayout.smallGap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .background(palette.fillSubtle, in: RoundedRectangle(cornerRadius: PrototypeLayout.radius))
            .accessibilityHint("Channel genre. No program listing for this time.")
    }
}

/// Each virtualized row keeps its station outside the horizontal scroller.
/// Only the focused/dragged row publishes movement; followers never feed back.
private struct PrototypeSynchronizedTimeline<Content: View>: View {
    @Binding var offset: CGFloat
    let isFocusedRow: Bool
    let viewportWidth: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var position = ScrollPosition(x: 0)
    @State private var currentOffset: CGFloat = 0
    @State private var synchronizationTarget: CGFloat?
    @State private var isDragging = false

    var body: some View {
        ScrollView(.horizontal) {
            content()
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .onScrollPhaseChange { _, phase in
            isDragging = phase == .tracking || phase == .interacting || phase == .decelerating
            if isDragging { synchronizationTarget = nil }
        }
        .onScrollGeometryChange(for: CGFloat.self) {
            min(max(0, $0.contentOffset.x + $0.contentInsets.leading), viewportWidth * 2)
        } action: { _, value in
            currentOffset = value
            if let target = synchronizationTarget {
                if abs(target - value) < 1 { synchronizationTarget = nil }
                return
            }
            guard isFocusedRow || isDragging, abs(offset - value) >= 1 else { return }
            offset = value
        }
        .onChange(of: offset) { _, value in synchronize(to: value) }
        .onChange(of: viewportWidth) { _, _ in
            synchronize(to: min(offset, viewportWidth * 2))
        }
        .onAppear { synchronize(to: offset) }
    }

    private func synchronize(to value: CGFloat) {
        guard abs(currentOffset - value) >= 1 else { return }
        synchronizationTarget = value
        position.scrollTo(x: value)
    }
}
#endif
