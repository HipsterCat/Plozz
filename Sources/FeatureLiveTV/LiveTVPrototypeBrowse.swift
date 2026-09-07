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
    @Binding var selectedRowID: LiveTVGuideRowID?
    @Binding var railActive: Bool
    @Binding var focusedProgram: LiveTVPrototypeProgram?
    @Binding var hasFocus: Bool
    let topRequest: Int
    let nowRequest: Int
    @Binding var guideOffset: TimeInterval
    @Binding var timeAnchor: Date
    @Binding var timelineOffset: CGFloat
    let restoreFocusRequest: Int
    let isPresented: Bool
    let isRestoringFocus: Bool
    let restoresPlaybackFocus: Bool
    let watchOrigin: LiveTVGuideRowID?
    let focusRestored: (Int) -> Void
    let tune: (LiveTVGuideRowID) -> Void
    let details: (LiveTVPrototypeProgram) -> Void
    let openControls: () -> Void
    let openSources: () -> Void
    let openGuideTime: () -> Void
    let openToolbar: () -> Void
    let isLoading: Bool
    let loadFailed: Bool
    let reload: () -> Void
    @State private var scrollID: LiveTVGuideRowID?
    @State private var pendingFocus: PrototypeBrowseFocus?
    @State private var restorationFallback: PrototypeBrowseFocus?
    @State private var verticalFade = PrototypeScrollFade()
    @State private var lastFocused: PrototypeBrowseFocus?
    @State private var confirmedFocus: PrototypeBrowseFocus?
    @State private var mountedRows = Set<LiveTVGuideRowID>()
    @State private var restrictDirectionalEntry = true
    @FocusState private var focused: PrototypeBrowseFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let focusReturnTarget = returnTarget
            VStack(spacing: PrototypeLayout.gap) {
                if !model.guideChannels.isEmpty {
                    if geometry.size.width >= 650, model.guideChannelCount > 0 {
                        PrototypeTimeRuler(
                            start: guideStart, now: model.now, width: geometry.size.width,
                            timelineOffset: timelineOffset, section: currentSection
                        )
                        .disabled(railActive || isRestoringFocus)
                    } else {
                        PrototypeGuideSectionLabel(section: currentSection)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        Button("Sources", action: openSources).buttonStyle(PrototypeButtonStyle())
                    }
                } else if model.channels.isEmpty {
                    ContentUnavailableView {
                        Label("No supported channels", systemImage: "tv")
                    } description: {
                        Text("The playlist has no supported HTTP or HTTPS streams. Sources shows how many entries were skipped.")
                    } actions: {
                        Button("Reload playlist", action: reload).buttonStyle(PrototypeButtonStyle())
                        Button("Sources", action: openSources).buttonStyle(PrototypeButtonStyle())
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
                            .buttonStyle(PrototypeButtonStyle(surface: .guide))
                            .focusEffectDisabled()
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: PrototypeLayout.rowGap) {
                                ForEach(model.guideChannels) { entry in
                                    let channel = entry.channel
                                    VStack(alignment: .leading, spacing: PrototypeLayout.rowGap) {
                                        if entry.startsSection, entry.section != model.guideChannels.first?.section {
                                            PrototypeGuideSectionLabel(section: entry.section)
                                                .padding(.top, PrototypeLayout.smallGap)
                                        }
                                        PrototypeGuideRow(
                                            channel: channel, section: entry.section,
                                            programs: model.programs(
                                                for: channel.id, from: guideStart,
                                                hours: geometry.size.width >= 650 ? 6 : 2
                                            ),
                                            start: guideStart, now: model.now,
                                            width: geometry.size.width, timelineOffset: $timelineOffset,
                                            focus: $focused,
                                            railActive: (railActive && restrictDirectionalEntry) || isRestoringFocus,
                                            returnTarget: focusReturnTarget,
                                            favorite: model.favoriteIDs.contains(channel.id),
                                            playing: model.playingChannelID == channel.id,
                                            toggleFavorite: { model.toggleFavorite(channel.id) },
                                            tune: { tune(entry.id) }, details: details,
                                            controls: openControls,
                                            top: { goToTop(proxy) },
                                            goToNow: goToNow,
                                            focusChanged: confirmFocus,
                                            sources: openSources, guideTime: openGuideTime
                                        )
                                    }
                                    .id(entry.id)
                                    .onAppear {
                                        mountedRows.insert(entry.id)
                                        completePendingFocus(entry.id)
                                    }
                                    .onDisappear { mountedRows.remove(entry.id) }
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.top, PrototypeLayout.smallGap)
                        }
                        .scrollIndicators(.hidden)
                        .background(alignment: .topLeading) {
                            if geometry.size.width >= 650, model.guideChannelCount > 0 {
                                HStack(spacing: PrototypeLayout.columnGap) {
                                    Color.clear.frame(width: PrototypeLayout.stationWidth(for: geometry.size.width))
                                    PrototypeNowLine(start: guideStart, now: model.now, timelineOffset: timelineOffset)
                                }
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                        }
                        .verticalEdgeFadeMask(
                            fadeHeight: PrototypeLayout.verticalFade,
                            topStrength: verticalFade.leading,
                            bottomStrength: 0
                        )
                        .onScrollGeometryChange(for: PrototypeScrollFade.self) { geometry in
                            PrototypeScrollFade(
                                before: geometry.contentOffset.y + geometry.contentInsets.top,
                                after: geometry.contentSize.height
                                    - (geometry.contentOffset.y + geometry.containerSize.height)
                            )
                        } action: { _, fade in
                            verticalFade = fade
                        }
                        .scrollPosition(id: $scrollID, anchor: .top)
                        .onChange(of: topRequest) { _, _ in goToTop(proxy) }
                        .task(id: isPresented && isRestoringFocus ? restoreFocusRequest : -1) {
                            await restoreFocus(using: proxy, width: geometry.size.width)
                        }
                    }
                }
            }
            .onChange(of: geometry.size.width) { old, new in
                let oldWidth = PrototypeLayout.timelineWidth(for: old)
                let newWidth = PrototypeLayout.timelineWidth(for: new)
                timelineOffset = new < 650 ? 0 : min(newWidth * 2, timelineOffset / oldWidth * newWidth)
            }
        }
        .padding([.leading, .top], PrototypeLayout.guideInset)
        .padding(.trailing, PrototypeLayout.guideTrailingInset)
        .background { PrototypeGuideSurface() }
        .clipShape(PrototypeLayout.guideShape)
        #if os(tvOS)
        .focusSection()
        .onExitCommand {
            if !isRestoringFocus { openToolbar() }
        }
        #endif
        .onChange(of: confirmedFocus, initial: true) { _, target in
            hasFocus = target != nil
            if let target {
                switch target {
                case .channel:
                    focusedProgram = nil
                case .program(let channelID, let programID, _):
                    focusedProgram = model.programs(for: channelID, from: guideStart, hours: 6)
                        .first { $0.id == programID }
                }
                selectedID = target.channelID
                selectedRowID = target.rowID
                lastFocused = target
                restrictDirectionalEntry = true
                railActive = false
                if isRestoringFocus, target == returnTarget {
                    focusRestored(restoreFocusRequest)
                }
            }
        }
        #if os(iOS)
        .onChange(of: selectedRowID) { _, row in scrollID = row }
        #endif
        .onChange(of: nowRequest) { _, _ in goToNow() }
        .onChange(of: isRestoringFocus) { _, restoring in
            if !restoring { restorationFallback = nil }
            if restoring, restorationTarget == nil {
                focusRestored(restoreFocusRequest)
            }
        }
        .onChange(of: model.guideChannels) { _, rows in
            if rows.isEmpty, isRestoringFocus {
                focusRestored(restoreFocusRequest)
            }
            if !rows.contains(where: { $0.id == selectedRowID }) {
                focusedProgram = nil
                let replacement = selectedID.flatMap { model.guideRow(for: $0) } ?? rows.first?.id
                selectedRowID = replacement
                selectedID = replacement?.channelID
                scrollID = replacement
                lastFocused = replacement.map { .channel($0.channelID, section: $0.section) }
                if hasFocus, !isRestoringFocus {
                    pendingFocus = lastFocused
                    focused = lastFocused
                }
            }
        }
        .onDisappear { hasFocus = false }
    }

    private var guideStart: Date {
        timeAnchor.addingTimeInterval(guideOffset)
    }

    private var currentSection: LiveTVGuideSection {
        model.guideChannels.first { $0.id == scrollID }?.section
            ?? model.guideChannels.first?.section ?? .channels
    }

    private var returnTarget: PrototypeBrowseFocus? {
        if isRestoringFocus { return restorationFallback ?? restorationTarget }
        return browseReturnTarget
    }

    private var browseReturnTarget: PrototypeBrowseFocus? {
        if case .program(let channelID, let programID, _) = lastFocused,
           lastFocused?.rowID == selectedRowID,
           model.guideChannels.contains(where: { $0.id == lastFocused?.rowID }),
           LiveTVGuideTimeline.slots(
               programs: model.programs(for: channelID, from: guideStart, hours: 6),
               from: guideStart, to: guideStart.addingTimeInterval(21_600)
           ).contains(where: { $0.program?.id == programID }) {
            return lastFocused
        }
        let row = selectedID.flatMap {
            model.guideRow(for: $0, preferring: selectedRowID?.section)
        } ?? model.guideChannels.first?.id
        return row.map { .channel($0.channelID, section: $0.section) }
    }

    private var restorationTarget: PrototypeBrowseFocus? {
        restoresPlaybackFocus ? playbackReturnTarget : browseReturnTarget
    }

    private var playbackReturnTarget: PrototypeBrowseFocus? {
        .returningToPlayback(in: model, selectedChannelID: selectedID, originRow: watchOrigin)
    }

    private func completePendingFocus(_ id: LiveTVGuideRowID) {
        guard !isRestoringFocus, pendingFocus?.rowID == id else { return }
        focused = pendingFocus
        pendingFocus = nil
    }

    private func confirmFocus(_ target: PrototypeBrowseFocus, _ isFocused: Bool) {
        if isFocused { confirmedFocus = target }
        else if confirmedFocus == target { confirmedFocus = nil }
    }

    private func restoreFocus(using proxy: ScrollViewProxy, width: CGFloat) async {
        guard isPresented, isRestoringFocus else { return }
        let request = restoreFocusRequest
        guard let target = restorationTarget else {
            railActive = false
            focusRestored(request)
            return
        }
        pendingFocus = nil
        restorationFallback = nil
        if restoresPlaybackFocus { revealCurrentProgram(width: width) }
        proxy.scrollTo(target.rowID, anchor: .center)
        if reduceMotion { await Task.yield() }
        else { try? await Task.sleep(for: .milliseconds(340)) }
        guard !Task.isCancelled else { return }
        guard let latestTarget = restorationTarget else {
            railActive = false
            focusRestored(request)
            return
        }
        if restoresPlaybackFocus { revealCurrentProgram(width: width) }
        if latestTarget.rowID != target.rowID {
            proxy.scrollTo(latestTarget.rowID, anchor: .center)
        }
        await waitForRow(latestTarget.rowID)
        guard !Task.isCancelled else { return }
        focused = latestTarget
        await waitForFocus(latestTarget)
        guard !Task.isCancelled else { return }
        if confirmedFocus == latestTarget {
            focusRestored(request)
            return
        }
        let fallback = PrototypeBrowseFocus.channel(latestTarget.channelID, section: latestTarget.rowID.section)
        restorationFallback = fallback
        proxy.scrollTo(latestTarget.rowID, anchor: .center)
        await Task.yield()
        guard !Task.isCancelled else { return }
        HandoffDiagnostics.emit("LIVE_TV event=guideFocusFallback kind=channel")
        focused = fallback
        await waitForFocus(fallback)
        guard !Task.isCancelled else { return }
        if confirmedFocus != fallback {
            HandoffDiagnostics.emit("LIVE_TV event=guideFocusRestore result=unconfirmed")
            // A failed handoff must not strand directional focus on the sidebar.
            restrictDirectionalEntry = false
        }
        railActive = false
        focusRestored(request)
    }

    private func waitForRow(_ row: LiveTVGuideRowID) async {
        for _ in 0..<10 {
            guard !Task.isCancelled, !mountedRows.contains(row) else { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func waitForFocus(_ target: PrototypeBrowseFocus) async {
        for _ in 0..<8 {
            guard !Task.isCancelled, confirmedFocus != target else { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func revealCurrentProgram(width: CGFloat) {
        guard let target = playbackReturnTarget,
              let program = model.currentProgram(for: target.channelID) else { return }
        if model.now < guideStart || model.now >= guideStart.addingTimeInterval(21_600) {
            goToNow()
        }
        let timelineWidth = PrototypeLayout.timelineWidth(for: width)
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
        guard let first = model.guideChannels.first else { return }
        railActive = false
        selectedID = first.channel.id
        selectedRowID = first.id
        focusedProgram = nil
        pendingFocus = .channel(first.channel.id, section: first.section)
        proxy.scrollTo(first.id, anchor: .top)
        focused = pendingFocus
    }
}

struct PrototypeGuideSectionLabel: View {
    let section: LiveTVGuideSection
    @Environment(\.themePalette) private var palette
    @ScaledMetric(relativeTo: .caption) private var fontSize = PrototypeLayout.sectionFontSize

    var body: some View {
        Text(section.title)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(palette.secondaryText)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, PrototypeLayout.rowInset)
            .frame(minHeight: 44, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct PrototypeTimeRuler: View {
    let start: Date
    let now: Date
    let width: CGFloat
    let timelineOffset: CGFloat
    let section: LiveTVGuideSection
    @Environment(\.themePalette) private var palette
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 44

    var body: some View {
        HStack(alignment: .center, spacing: PrototypeLayout.columnGap) {
            PrototypeGuideSectionLabel(section: section)
                .frame(width: PrototypeLayout.stationWidth(for: width), alignment: .leading)
            GeometryReader { geometry in
                PrototypeNowLine(start: start, now: now, timelineOffset: timelineOffset)
                HStack(spacing: 0) {
                    ForEach(0..<12, id: \.self) { tick in
                        Text(start.addingTimeInterval(TimeInterval(tick * 1_800)), format: .dateTime.hour().minute())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.leading, PrototypeLayout.rowInset)
                            .frame(width: geometry.size.width / 4, alignment: .leading)
                    }
                }
                .frame(height: height)
                .offset(x: -timelineOffset)
            }
            .frame(height: height)
            .horizontalEdgeFadeMask(
                fadeWidth: PrototypeLayout.horizontalFade,
                leadingStrength: horizontalFade.leading,
                trailingStrength: horizontalFade.trailing
            )
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(palette.primaryText)
    }

    private var horizontalFade: PrototypeScrollFade {
        let viewport = PrototypeLayout.timelineWidth(for: width)
        return PrototypeScrollFade(
            before: timelineOffset, after: viewport * 2 - timelineOffset,
            distance: PrototypeLayout.horizontalFade
        )
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
    var section: LiveTVGuideSection = .channels
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
    var focusChanged: (PrototypeBrowseFocus, Bool) -> Void = { _, _ in }
    var sources: () -> Void = {}
    var guideTime: () -> Void = {}
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = PrototypeLayout.rowHeight
    @State private var compactFade = PrototypeScrollFade()

    var body: some View {
        if width < 650 {
            VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
                HStack(spacing: PrototypeLayout.columnGap) {
                    PrototypeGuideStation(
                        channel: channel, section: section,
                        favorite: favorite, playing: playing, tune: tune, toggleFavorite: toggleFavorite,
                        controls: controls, top: top, height: rowHeight,
                        focusChanged: { focusChanged(channelFocus, $0) },
                        sources: sources, guideTime: programs.isEmpty ? nil : guideTime
                    )
                    .focused(focus, equals: channelFocus)
                    .disabled(railActive && returnTarget != channelFocus)
                    if programs.isEmpty {
                        PrototypeGuideGap(channelName: channel.name, height: rowHeight)
                    }
                }
                if !programs.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: PrototypeLayout.smallGap) {
                            ForEach(programs) { program in
                                Button { open(program) } label: {
                                    PrototypeProgramLabel(program: program, now: now)
                                        .frame(width: 230, alignment: .leading)
                                }
                                .buttonStyle(PrototypeButtonStyle(
                                    surface: .program, focusChanged: { focusChanged(programFocus(program.id), $0) }
                                ))
                                .focusEffectDisabled()
                                .focused(focus, equals: programFocus(program.id))
                                .disabled(railActive && returnTarget != programFocus(program.id))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .horizontalEdgeFadeMask(
                        fadeWidth: PrototypeLayout.horizontalFade,
                        leadingStrength: compactFade.leading,
                        trailingStrength: compactFade.trailing
                    )
                    .onScrollGeometryChange(for: PrototypeScrollFade.self) { geometry in
                        PrototypeScrollFade(
                            before: geometry.contentOffset.x + geometry.contentInsets.leading,
                            after: geometry.contentSize.width
                                - (geometry.contentOffset.x + geometry.containerSize.width),
                            distance: PrototypeLayout.horizontalFade
                        )
                    } action: { _, fade in
                        compactFade = fade
                    }
                }
            }
            .padding(.bottom, PrototypeLayout.gap)
        } else {
            HStack(spacing: PrototypeLayout.columnGap) {
                PrototypeGuideStation(
                    channel: channel, section: section,
                    favorite: favorite, playing: playing, tune: tune, toggleFavorite: toggleFavorite,
                    controls: controls, top: top, height: rowHeight,
                    focusChanged: { focusChanged(channelFocus, $0) },
                    sources: sources, guideTime: programs.isEmpty ? nil : guideTime
                )
                    .frame(width: PrototypeLayout.stationWidth(for: width))
                    .focused(focus, equals: channelFocus)
                    .disabled(railActive && returnTarget != channelFocus)
                if programs.isEmpty {
                    PrototypeGuideGap(channelName: channel.name, height: rowHeight)
                        .frame(maxWidth: .infinity)
                } else {
                    PrototypeSynchronizedTimeline(
                        offset: $timelineOffset,
                        isFocusedRow: focus.wrappedValue?.rowID == channelFocus.rowID,
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
                                            availableWidth: max(0, cellWidth(slot) - PrototypeLayout.rowInset * 2)
                                        )
                                        .padding(.horizontal, min(PrototypeLayout.rowInset, slotWidth(slot) / 4))
                                        .frame(
                                            width: cellWidth(slot),
                                            height: PrototypeLayout.programHeight(in: rowHeight),
                                            alignment: .leading
                                        )
                                        .clipped()
                                    }
                                    .buttonStyle(PrototypeButtonStyle(
                                        padded: false, surface: .program,
                                        focusChanged: { focusChanged(programFocus(program.id), $0) }
                                    ))
                                    .focusEffectDisabled()
                                    .padding(.vertical, PrototypeLayout.programInset)
                                    .padding(.trailing, min(PrototypeLayout.cellGap, slotWidth(slot) / 4))
                                    .frame(width: slotWidth(slot), height: rowHeight)
                                    .clipped()
                                    .focused(focus, equals: programFocus(program.id))
                                    .disabled(
                                        railActive && returnTarget != programFocus(program.id)
                                    )
                                    .contextMenu {
                                        Button("Program details", systemImage: "info.circle") { details(program) }
                                        Button("Watch channel live", systemImage: "play.fill", action: tune)
                                        Button(
                                            favorite ? "Remove from Favorites" : "Add to Favorites",
                                            systemImage: "star", action: toggleFavorite
                                        )
                                        Button("Search channels", systemImage: "magnifyingglass", action: controls)
                                        Button("Sources", systemImage: "antenna.radiowaves.left.and.right", action: sources)
                                        Button("Guide time", systemImage: "calendar", action: guideTime)
                                        Button("Back to top", systemImage: "arrow.up.to.line", action: top)
                                        Button("Now", systemImage: "clock", action: goToNow)
                                    }
                                } else {
                                    PrototypeGuideGap(channelName: channel.name, height: rowHeight)
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

    private var channelFocus: PrototypeBrowseFocus {
        .channel(channel.id, section: section)
    }

    private func programFocus(_ id: String) -> PrototypeBrowseFocus {
        .program(channelID: channel.id, programID: id, section: section)
    }

    private func slotWidth(_ slot: LiveTVGuideSlot) -> CGFloat {
        let seconds = slot.end.timeIntervalSince(slot.start)
        return timelineWidth * seconds / 7_200
    }

    private func cellWidth(_ slot: LiveTVGuideSlot) -> CGFloat {
        slotWidth(slot) - min(PrototypeLayout.cellGap, slotWidth(slot) / 4)
    }

    private var timelineWidth: CGFloat {
        PrototypeLayout.timelineWidth(for: width)
    }

    private func open(_ program: LiveTVPrototypeProgram) {
        if program.start <= now && now < program.end { tune() }
        else { details(program) }
    }
}

private struct PrototypeGuideStation: View {
    let channel: LiveTVPrototypeChannel
    let section: LiveTVGuideSection
    let favorite: Bool
    let playing: Bool
    let tune: () -> Void
    let toggleFavorite: () -> Void
    let controls: () -> Void
    let top: () -> Void
    var height: CGFloat? = nil
    var focusChanged: ((Bool) -> Void)?
    var sources: () -> Void = {}
    var guideTime: (() -> Void)?

    var body: some View {
        Button(action: tune) {
            PrototypeStationMark(
                channel: channel,
                plateSize: CGSize(width: PrototypeLayout.stationColumnWidth, height: height ?? PrototypeLayout.rowHeight),
                cornerRadius: PrototypeLayout.rowRadius
            )
                .clipped()
        }
        .buttonStyle(PrototypeButtonStyle(padded: false, surface: .station, focusChanged: focusChanged))
        .focusEffectDisabled()
        .accessibilityLabel(Text(channel.name))
        .accessibilityValue(Text("Channel \(channel.number)"))
        .accessibilityAddTraits(playing ? .isSelected : [])
        .accessibilityIdentifier("live-tv-channel-\(section.rawValue)-\(channel.number)")
        .contextMenu {
            Button(
                favorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: "star", action: toggleFavorite
            )
            Button("Search channels", systemImage: "magnifyingglass", action: controls)
            Button("Sources", systemImage: "antenna.radiowaves.left.and.right", action: sources)
            if let guideTime {
                Button("Guide time", systemImage: "calendar", action: guideTime)
            }
            Button("Back to top", systemImage: "arrow.up.to.line", action: top)
        }
    }
}

struct PrototypeProgramLabel: View {
    let program: LiveTVPrototypeProgram
    let now: Date
    var availableWidth: CGFloat? = nil
    @ScaledMetric(relativeTo: .subheadline) private var minimumTitleWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var fontSize = PrototypeLayout.guideFontSize

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
            if let availableWidth, availableWidth < minimumTitleWidth {
                Image(systemName: "ellipsis").font(.caption)
            } else {
                Text(program.title).font(.system(size: fontSize, weight: .regular))
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

struct PrototypeGuideGap: View {
    let channelName: String
    let height: CGFloat
    @Environment(\.themePalette) private var palette
    @ScaledMetric(relativeTo: .subheadline) private var fontSize = PrototypeLayout.guideFontSize
    var body: some View {
        Text(channelName)
            .font(.system(size: fontSize)).foregroundStyle(palette.primaryText.opacity(0.8)).lineLimit(2)
            .padding(.horizontal, PrototypeLayout.rowInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .accessibilityHint("No program listing for this time.")
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
        .horizontalEdgeFadeMask(
            fadeWidth: PrototypeLayout.horizontalFade,
            leadingStrength: edgeFade.leading,
            trailingStrength: edgeFade.trailing
        )
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

    private var edgeFade: PrototypeScrollFade {
        PrototypeScrollFade(
            before: currentOffset, after: viewportWidth * 2 - currentOffset,
            distance: PrototypeLayout.horizontalFade
        )
    }
}
#endif
