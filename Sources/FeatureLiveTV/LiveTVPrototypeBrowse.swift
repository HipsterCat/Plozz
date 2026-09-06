#if DEBUG
import CoreUI
import FeatureLiveTVCore
import SwiftUI

struct PrototypeBrowser: View {
    let model: LiveTVPrototypeModel
    let guide: Bool
    @Binding var selectedID: String?
    @Binding var railActive: Bool
    let topRequest: Int
    @Binding var guideOffset: TimeInterval
    let tune: (String) -> Void
    let details: (LiveTVPrototypeProgram) -> Void
    let openControls: () -> Void
    let browseChannels: () -> Void
    @State private var scrollID: String?
    @State private var pendingFocus: String?
    @FocusState private var focusedID: String?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: PrototypeLayout.gap) {
                if guide && model.scenario != .noGuide && model.scenario != .failedGuide {
                    PrototypeGuideControls(
                        start: guideStart, offset: $guideOffset, controls: openControls,
                        top: { pendingFocus = model.visibleChannels.first?.id; scrollID = pendingFocus }
                    )
                    if geometry.size.width >= 650 {
                        PrototypeTimeRuler(start: guideStart, now: model.now, width: geometry.size.width)
                    }
                }
                if model.visibleChannels.isEmpty {
                    ContentUnavailableView {
                        Label("No matching channels", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Try another search or clear your filters.")
                    } actions: {
                        Button("Clear filters") { model.resetFilters() }
                            .buttonStyle(PrototypeButtonStyle())
                    }
                } else if guide && (model.scenario == .noGuide || model.scenario == .failedGuide) {
                    ContentUnavailableView {
                        Label("Channels are still ready to watch", systemImage: "tv")
                    } description: {
                        Text("No program guide is connected. You can still watch, search and favorite channels, or browse by category.")
                    } actions: {
                        Button("Browse channels", action: browseChannels)
                            .buttonStyle(PrototypeButtonStyle())
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: PrototypeLayout.smallGap) {
                                ForEach(model.visibleChannels) { channel in
                                    if guide {
                                        PrototypeGuideRow(
                                            channel: channel,
                                            programs: model.programs(for: channel.id, from: guideStart, hours: 2),
                                            start: guideStart, now: model.now,
                                            width: geometry.size.width,
                                            tune: { tune(channel.id) }, details: details,
                                            controls: openControls,
                                            top: { goToTop(proxy) },
                                            goToNow: { guideOffset = 0 }
                                        )
                                        .id(channel.id)
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
                                        .focused($focusedID, equals: channel.id)
                                        .disabled(railActive && selectedID != channel.id)
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
                                        .onAppear {
                                            if pendingFocus == channel.id {
                                                focusedID = channel.id
                                                pendingFocus = nil
                                            }
                                        }
                                    }
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.vertical, PrototypeLayout.smallGap)
                        }
                        .scrollPosition(id: $scrollID, anchor: .top)
                        .onChange(of: topRequest) { _, _ in goToTop(proxy) }
                        .onChange(of: model.visibleChannels) { _, channels in
                            if !channels.contains(where: { $0.id == selectedID }) {
                                selectedID = channels.first?.id
                                scrollID = selectedID
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: focusedID) { _, id in
            if let id {
                selectedID = id
                railActive = false
            }
        }
    }

    private var guideStart: Date {
        Date(timeIntervalSince1970: floor(model.now.timeIntervalSince1970 / 1_800) * 1_800 + guideOffset)
    }

    private func goToTop(_ proxy: ScrollViewProxy) {
        guard let first = model.visibleChannels.first else { return }
        railActive = false
        selectedID = first.id
        pendingFocus = first.id
        proxy.scrollTo(first.id, anchor: .top)
        focusedID = first.id
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
    let controls: () -> Void
    let top: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(start, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.subheadline.monospacedDigit())
                Spacer()
                PrototypeGuidePaging(offset: $offset)
                Button("Controls", systemImage: "slider.horizontal.3", action: controls)
                Button("Top", systemImage: "arrow.up.to.line", action: top)
            }
            HStack {
                PrototypeGuidePaging(offset: $offset)
                Spacer()
                Button("Controls", systemImage: "slider.horizontal.3", action: controls)
                    .labelStyle(.iconOnly)
            }
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
            Button("Later", systemImage: "chevron.right") { offset = min(86_400, offset + 7_200) }
                .labelStyle(.iconOnly).disabled(offset >= 86_400)
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
    let programs: [LiveTVPrototypeProgram]
    let start: Date
    let now: Date
    let width: CGFloat
    let tune: () -> Void
    let details: (LiveTVPrototypeProgram) -> Void
    let controls: () -> Void
    let top: () -> Void
    let goToNow: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        if width < 650 {
            VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
                PrototypeGuideStation(channel: channel, tune: tune)
                ForEach(programs) { program in
                    Button { details(program) } label: {
                        PrototypeProgramLabel(program: program, now: now)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PrototypeButtonStyle())
                }
                if programs.isEmpty { PrototypeGuideGap() }
            }
            .padding(.bottom, PrototypeLayout.gap)
        } else {
            HStack(spacing: PrototypeLayout.smallGap) {
                PrototypeGuideStation(channel: channel, tune: tune)
                    .frame(width: width > 1_100 ? 300 : 210)
                HStack(spacing: 0) {
                    if programs.isEmpty {
                        PrototypeGuideGap().frame(maxWidth: .infinity)
                    } else {
                        ForEach(programs) { program in
                            Button { details(program) } label: {
                                PrototypeProgramLabel(program: program, now: now)
                                    .frame(maxWidth: .infinity, minHeight: PrototypeLayout.rowHeight, alignment: .leading)
                                    .padding(.horizontal, PrototypeLayout.smallGap)
                            }
                            .buttonStyle(PrototypeButtonStyle(
                                selected: program.start <= now && now < program.end, padded: false
                            ))
                            .frame(width: programWidth(program))
                            .contextMenu {
                                Button("Watch channel live", systemImage: "play.fill", action: tune)
                                Button("Browse controls", systemImage: "slider.horizontal.3", action: controls)
                                Button("Back to top", systemImage: "arrow.up.to.line", action: top)
                                Button("Now", systemImage: "clock", action: goToNow)
                            }
                        }
                    }
                }
            }
        }
    }

    private func programWidth(_ program: LiveTVPrototypeProgram) -> CGFloat {
        let seconds = min(program.end, start.addingTimeInterval(7_200)).timeIntervalSince(max(program.start, start))
        let stationWidth: CGFloat = width > 1_100 ? 300 : 210
        return max(0, width - stationWidth - PrototypeLayout.smallGap) * seconds / 7_200
    }
}

private struct PrototypeGuideStation: View {
    let channel: LiveTVPrototypeChannel
    let tune: () -> Void

    var body: some View {
        Button(action: tune) {
            HStack(spacing: PrototypeLayout.smallGap) {
                PrototypeStationMark(channel: channel, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(channel.number, format: .number.grouping(.never)).font(.caption).opacity(0.7)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: PrototypeLayout.rowHeight)
            .padding(.horizontal, PrototypeLayout.smallGap)
        }
        .buttonStyle(PrototypeButtonStyle(padded: false))
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
    @Environment(\.themePalette) private var palette
    var body: some View {
        Text("Program information unavailable")
            .font(.subheadline).foregroundStyle(palette.secondaryText)
            .frame(maxWidth: .infinity, minHeight: PrototypeLayout.rowHeight)
            .background(palette.fillSubtle, in: RoundedRectangle(cornerRadius: PrototypeLayout.radius))
    }
}
#endif
