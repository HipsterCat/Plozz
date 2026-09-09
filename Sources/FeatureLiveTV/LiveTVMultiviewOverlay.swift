#if DEBUG
import CoreModels
import CoreUI
import FeatureLiveTVCore
import SwiftUI

enum LiveTVMultiviewGeometry {
    static func viewport(in size: CGSize) -> CGRect {
        #if os(tvOS)
        let top: CGFloat = 168
        let bottom: CGFloat = 150
        #else
        let top: CGFloat = 90
        let bottom: CGFloat = 110
        #endif
        return CGRect(x: 0, y: top, width: size.width, height: max(1, size.height - top - bottom))
    }

    static func frame(
        for id: UUID, panes: [UUID], primary: UUID,
        layout: LiveTVMultiviewLayout, corner: LiveTVMultiviewCorner,
        insetSize: LiveTVMultiviewInsetSize, expanded: UUID?, size: CGSize
    ) -> CGRect {
        #if os(tvOS)
        let margin: CGFloat = 48
        #else
        let margin: CGFloat = 16
        #endif
        let viewport = Self.viewport(in: size)
        let area = CGRect(
            x: margin, y: viewport.minY,
            width: max(1, size.width - 2 * margin),
            height: viewport.height
        )
        if expanded != nil { return fitted(in: area) }
        let ordered = [primary] + panes.filter { $0 != primary }
        if ordered.count == 1 { return fitted(in: area) }
        let index = ordered.firstIndex(of: id) ?? 0
        if layout == .sideBySide {
            let horizontal = area.width >= area.height
            let gap: CGFloat = 16
            let slot: CGRect
            if horizontal {
                let width = (area.width - gap) / 2
                slot = CGRect(
                    x: area.minX + CGFloat(index) * (width + gap), y: area.minY,
                    width: width, height: area.height)
            } else {
                let height = (area.height - gap) / 2
                slot = CGRect(
                    x: area.minX, y: area.minY + CGFloat(index) * (height + gap),
                    width: area.width, height: height)
            }
            return fitted(in: slot)
        }
        let main = fitted(in: area)
        guard id != primary else { return main }
        let width = main.width * CGFloat(insetSize.fraction)
        let height = width * 9 / 16
        let left = corner == .topLeading || corner == .bottomLeading
        let atTop = corner == .topLeading || corner == .topTrailing
        return CGRect(
            x: left ? main.minX + 16 : main.maxX - width - 16,
            y: atTop ? main.minY + 16 : main.maxY - height - 16,
            width: width, height: height
        )
    }

    static func focusFrame(
        for id: UUID, panes: [UUID], primary: UUID,
        layout: LiveTVMultiviewLayout, corner: LiveTVMultiviewCorner,
        insetSize: LiveTVMultiviewInsetSize, expanded: UUID?, size: CGSize
    ) -> CGRect {
        let picture = frame(
            for: id, panes: panes, primary: primary, layout: layout, corner: corner,
            insetSize: insetSize, expanded: expanded, size: size
        )
        guard expanded == nil, layout == .corner, id == primary,
              let secondary = panes.first(where: { $0 != primary }) else { return picture }
        let inset = frame(
            for: secondary, panes: panes, primary: primary, layout: layout, corner: corner,
            insetSize: insetSize, expanded: nil, size: size
        )
        // A full-picture focus item surrounds the inset and intercepts its directional entry.
        let gap: CGFloat = 16
        let leading = corner == .topLeading || corner == .bottomLeading
        let x = leading ? inset.maxX + gap : picture.minX
        let right = leading ? picture.maxX : inset.minX - gap
        return CGRect(x: x, y: picture.minY, width: max(1, right - x), height: picture.height)
    }

    private static func fitted(in area: CGRect) -> CGRect {
        let width = min(area.width, area.height * 16 / 9)
        let height = width * 9 / 16
        return CGRect(
            x: area.midX - width / 2, y: area.midY - height / 2,
            width: width, height: height)
    }
}

struct LiveTVMultiviewOverlay: View {
    let coordinator: LiveTVMultiviewCoordinator
    let channels: [LiveTVPrototypeChannel]
    let favoriteIDs: Set<String>
    let exit: () -> Void
    let returnToGuide: () -> Void
    var pickerVisibilityChanged: (Bool) -> Void = { _ in }
    @State private var picker: ChannelPickerDestination?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum ChannelPickerDestination: Identifiable {
        case add
        case replace(UUID)

        var id: String {
            switch self {
            case .add: "add"
            case .replace(let id): id.uuidString
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ZStack(alignment: .topLeading) {
                    LiveTVMultiviewPaneViewport(
                        coordinator: coordinator, size: geometry.size,
                        replace: { picker = .replace($0) }
                    )
                    VStack(spacing: 16) {
                        LiveTVMultiviewHeader(exit: exit)
                        Spacer(minLength: 0)
                        LiveTVMultiviewToolbar(
                            coordinator: coordinator,
                            add: { picker = .add },
                            replace: { picker = .replace(coordinator.audiblePaneID) }
                        )
                    }
                    #if os(tvOS)
                    .padding(48)
                    #else
                    .padding(16)
                    #endif
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: coordinator.layout)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: coordinator.primaryPaneID)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: coordinator.corner)
                .disabled(picker != nil)
                .accessibilityHidden(picker != nil)
                if let destination = picker {
                    channelPicker(destination)
                        .background(.black)
                        .ignoresSafeArea()
                }
            }
        }
        .alert(
            "Multiview",
            isPresented: Binding(
                get: { coordinator.issue != nil },
                set: { if !$0 { coordinator.dismissIssue() } }
            )
        ) {
            Button("OK", role: .cancel) { coordinator.dismissIssue() }
        } message: {
            if let issue = coordinator.issue { Text(issue) }
        }
        .onChange(of: picker != nil, initial: true) { _, visible in
            pickerVisibilityChanged(visible)
        }
        .onDisappear { pickerVisibilityChanged(false) }
        #if os(tvOS)
        .onExitCommand {
            if picker != nil {
                picker = nil
            } else if coordinator.expandedPaneID != nil {
                coordinator.collapse()
            } else {
                returnToGuide()
            }
        }
        #endif
    }

    private func channelPicker(_ destination: ChannelPickerDestination) -> some View {
        LiveTVMultiviewChannelPicker(
            channels: channels, favoriteIDs: favoriteIDs,
            selectedIDs: Set(coordinator.panes.compactMap { $0.channel?.id }),
            cancel: { picker = nil }
        ) { channel in
            switch destination {
            case .add: coordinator.add(channel)
            case .replace(let id): coordinator.replace(id, with: channel)
            }
            picker = nil
        }
    }
}

private struct LiveTVMultiviewPaneViewport: View {
    let coordinator: LiveTVMultiviewCoordinator
    let size: CGSize
    let replace: (UUID) -> Void

    var body: some View {
        let viewport = LiveTVMultiviewGeometry.viewport(in: size)
        ZStack(alignment: .topLeading) {
            ForEach(coordinator.panes) { pane in
                let frame = LiveTVMultiviewGeometry.frame(
                    for: pane.id, panes: coordinator.panes.map(\.id),
                    primary: coordinator.primaryPaneID, layout: coordinator.layout,
                    corner: coordinator.corner, insetSize: coordinator.insetSize,
                    expanded: coordinator.expandedPaneID, size: size
                )
                let focusFrame = LiveTVMultiviewGeometry.focusFrame(
                    for: pane.id, panes: coordinator.panes.map(\.id),
                    primary: coordinator.primaryPaneID, layout: coordinator.layout,
                    corner: coordinator.corner, insetSize: coordinator.insetSize,
                    expanded: coordinator.expandedPaneID, size: size
                )
                let visible = coordinator.expandedPaneID == nil || coordinator.expandedPaneID == pane.id
                LiveTVMultiviewPaneControl(
                    pane: pane, audible: coordinator.audiblePaneID == pane.id,
                    focusFrame: focusFrame.offsetBy(dx: -frame.minX, dy: -frame.minY),
                    isInteractive: visible,
                    listen: { coordinator.selectAudio(pane.id) },
                    promote: { coordinator.promote(pane.id) },
                    replace: { replace(pane.id) },
                    retry: { coordinator.retry(pane.id) }
                )
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX - viewport.minX, y: frame.midY - viewport.minY)
                .zIndex(pane.id == coordinator.primaryPaneID ? 0 : 1)
                .opacity(visible ? 1 : 0)
                .disabled(!visible)
                .accessibilityHidden(!visible)
            }
        }
        // Bridge Done's horizontal gap without absorbing the header or toolbar into this focus section.
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        #if os(tvOS)
        .focusSection()
        #endif
        .position(x: viewport.midX, y: viewport.midY)
    }
}

private struct LiveTVMultiviewHeader: View {
    let exit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Multiview").font(.title2.weight(.semibold))
                Text("Select a picture to listen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            LiveTVMultiviewAction(title: "Done", symbol: "xmark", action: exit)
                .accessibilityIdentifier("live-multiview-done")
        }
        .foregroundStyle(.white)
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

private struct LiveTVMultiviewPaneControl: View {
    let pane: LiveTVMultiviewPane
    let audible: Bool
    let focusFrame: CGRect
    let isInteractive: Bool
    let listen: () -> Void
    let promote: () -> Void
    let replace: () -> Void
    let retry: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.themePalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ZStack(alignment: .top) {
            #if os(tvOS)
            pictureLabel
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            #endif
            pictureControl
            .disabled(!isInteractive || (pane.preparation.current == nil && pane.preparation.failure != nil))
            .accessibilityLabel(pane.channel?.name ?? String(localized: "Channel"))
            .accessibilityValue(audible ? String(localized: "Audio on") : String(localized: "Muted"))
            .accessibilityIdentifier("live-multiview-pane-\(pane.id.uuidString)")
            .contextMenu {
                Button("Listen", systemImage: "speaker.wave.2", action: listen)
                Button("Make main picture", systemImage: "rectangle.inset.filled", action: promote)
                Button("Replace channel", systemImage: "arrow.triangle.2.circlepath", action: replace)
            }
            #if os(tvOS)
            .frame(width: focusFrame.width, height: focusFrame.height)
            .position(x: focusFrame.midX, y: focusFrame.midY)
            #endif

            if let failure = pane.preparation.failure {
                LiveTVMultiviewFailure(
                    message: failure.userDescription,
                    hasCurrentPicture: pane.preparation.current != nil,
                    retry: retry, replace: replace
                )
                .disabled(pane.preparation.isPreparing)
            }
        }
        .overlay {
            if focused {
                PrototypeFocusOutline(cornerRadius: 10)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(audible ? palette.accent : .white.opacity(0.15), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var pictureControl: some View {
        #if os(tvOS)
        Color.clear
            .accessibilityElement(children: .ignore)
            .focusableCard(
                isFocused: $focused, cornerRadius: 10,
                isEnabled: isEnabled && isInteractive
                    && (pane.preparation.current != nil || pane.preparation.failure == nil),
                action: listen
            )
        #else
        Button(action: listen) { pictureLabel }
            .buttonStyle(.plain)
        #endif
    }

    private var pictureLabel: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(.clear).contentShape(Rectangle())
            HStack(spacing: 10) {
                if audible { Image(systemName: "speaker.wave.2.fill") }
                Text(pane.channel?.name ?? String(localized: "Channel"))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if pane.preparation.isPreparing { ProgressView().tint(.white) }
            }
            .font(.caption.weight(.semibold))
            .padding(14)
            .background(.black.opacity(0.7))
        }
    }
}

private struct LiveTVMultiviewFailure: View {
    let message: LocalizedStringResource
    let hasCurrentPicture: Bool
    let retry: () -> Void
    let replace: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 12) {
                Text(message).font(.callout).multilineTextAlignment(.center)
                actions
            }
            actions
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: hasCurrentPicture ? nil : .infinity)
        .background(.black.opacity(0.78))
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                LiveTVMultiviewAction(title: "Retry", symbol: "arrow.clockwise", action: retry)
                LiveTVMultiviewAction(title: "Replace", symbol: "arrow.triangle.2.circlepath", action: replace)
            }
            HStack {
                Button("Retry", systemImage: "arrow.clockwise", action: retry)
                Button("Replace", systemImage: "arrow.triangle.2.circlepath", action: replace)
            }
            .labelStyle(.iconOnly)
        }
    }
}

private struct LiveTVMultiviewToolbar: View {
    let coordinator: LiveTVMultiviewCoordinator
    let add: () -> Void
    let replace: () -> Void
    @FocusState private var layoutFocused: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                if coordinator.canAdd {
                    LiveTVMultiviewAction(title: "Add channel", symbol: "plus", action: add)
                        .accessibilityIdentifier("live-multiview-add")
                }
                Menu {
                    ForEach(LiveTVMultiviewLayout.allCases, id: \.self) { layout in
                        Button {
                            coordinator.layout = layout
                        } label: {
                            Label(layout.title, systemImage: coordinator.layout == layout ? "checkmark" : "rectangle")
                        }
                    }
                    if coordinator.layout == .corner {
                        Section("Position") {
                            ForEach(LiveTVMultiviewCorner.allCases, id: \.self) { corner in
                                Button(corner.title) { coordinator.corner = corner }
                            }
                        }
                        Section("Size") {
                            ForEach(LiveTVMultiviewInsetSize.allCases, id: \.self) { size in
                                Button(size.title) { coordinator.insetSize = size }
                            }
                        }
                    }
                } label: {
                    Label("Layout", systemImage: "rectangle.split.2x1")
                }
                .focused($layoutFocused)
                .plozzActionButton(role: .secondary)
                .accessibilityIdentifier("live-multiview-layout")
                if coordinator.panes.count > 1 {
                    Menu {
                        ForEach(coordinator.panes) { pane in
                            Button {
                                coordinator.selectAudio(pane.id)
                            } label: {
                                Label(
                                    pane.channel?.name ?? String(localized: "Channel"),
                                    systemImage: coordinator.audiblePaneID == pane.id ? "checkmark" : "speaker"
                                )
                            }
                            .disabled(pane.preparation.current == nil)
                            .accessibilityLabel(pane.channel?.name ?? String(localized: "Channel"))
                            .accessibilityIdentifier("live-multiview-listen-\(pane.id.uuidString)")
                        }
                    } label: {
                        Label("Audio", systemImage: "speaker.wave.2")
                    }
                    .plozzActionButton(role: .secondary)
                    .accessibilityIdentifier("live-multiview-audio")
                }
                LiveTVMultiviewAction(title: "Replace", symbol: "arrow.triangle.2.circlepath", action: replace)
                    .accessibilityIdentifier("live-multiview-replace")
                if coordinator.panes.count > 1, coordinator.audiblePaneID != coordinator.primaryPaneID {
                    LiveTVMultiviewAction(title: "Make main", symbol: "rectangle.inset.filled") {
                        coordinator.promote(coordinator.audiblePaneID)
                    }
                    .accessibilityIdentifier("live-multiview-promote")
                }
                if coordinator.expandedPaneID != nil {
                    LiveTVMultiviewAction(title: "Show both", symbol: "rectangle.split.2x1") {
                        coordinator.collapse()
                    }
                    .accessibilityIdentifier("live-multiview-collapse")
                } else {
                    LiveTVMultiviewAction(title: "Expand", symbol: "arrow.up.left.and.arrow.down.right") {
                        coordinator.expand(coordinator.audiblePaneID)
                    }
                    .accessibilityIdentifier("live-multiview-expand")
                }
                if coordinator.panes.count > 1 {
                    LiveTVMultiviewAction(title: "Remove", symbol: "minus.circle") {
                        coordinator.remove(coordinator.audiblePaneID)
                    }
                    .accessibilityIdentifier("live-multiview-remove")
                }
            }
            .padding(8)
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white)
    }
}

private struct LiveTVMultiviewAction: View {
    let title: LocalizedStringResource
    let symbol: String
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol) }
            .focused($focused)
            .plozzActionButton(role: .secondary)
    }
}

private struct LiveTVMultiviewChannelPicker: View {
    let channels: [LiveTVPrototypeChannel]
    let favoriteIDs: Set<String>
    let selectedIDs: Set<String>
    let cancel: () -> Void
    let select: (LiveTVPrototypeChannel) -> Void
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var category: String?

    private var results: [LiveTVPrototypeChannel] {
        channels.filter { channel in
            (!favoritesOnly || favoriteIDs.contains(channel.id))
                && (category == nil || category == channel.category)
                && (query.isEmpty || channel.name.localizedStandardContains(query)
                    || channel.category.localizedStandardContains(query)
                    || String(channel.number).localizedStandardContains(query))
        }
    }

    var body: some View {
        #if os(tvOS)
        PrototypeNativeSearch(
            query: $query, restoresGuideFocus: false, isPresented: true,
            close: cancel, editing: {}
        ) { close in
            LiveTVMultiviewSearchResults(
                channels: results, categories: Array(Set(channels.map(\.category))).sorted(),
                selectedIDs: selectedIDs, query: query,
                favoritesOnly: $favoritesOnly, category: $category,
                cancel: close, select: select
            )
        }
        #else
        NavigationStack {
            channelList
                .searchable(text: $query, prompt: "Search channels")
                .navigationTitle("Choose channel")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel, action: cancel)
                    }
                }
        }
        #endif
    }

    private var channelList: some View {
        List {
            Section {
                Toggle("Favorites only", isOn: $favoritesOnly)
                    .toggleStyle(SettingsSwitchToggleStyle())
                Picker("Category", selection: $category) {
                    Text("All categories").tag(String?.none)
                    ForEach(Array(Set(channels.map(\.category))).sorted(), id: \.self) { value in
                        Text(value).tag(Optional(value))
                    }
                }
                .pickerStyle(.menu)
            }
            Section {
                ForEach(results) { channel in
                    LiveTVMultiviewChannelRow(
                        channel: channel, isSelected: selectedIDs.contains(channel.id),
                        select: { select(channel) }
                    )
                }
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}

#if os(tvOS)
private struct LiveTVMultiviewSearchResults: View {
    let channels: [LiveTVPrototypeChannel]
    let categories: [String]
    let selectedIDs: Set<String>
    let query: String
    @Binding var favoritesOnly: Bool
    @Binding var category: String?
    let cancel: () -> Void
    let select: (LiveTVPrototypeChannel) -> Void

    var body: some View {
        VStack(spacing: 16) {
            PrototypeSearchFocusBoundary {
                HStack {
                    Text("Choose channel").font(.title2.weight(.semibold))
                    Spacer()
                    LiveTVMultiviewAction(title: "Cancel", symbol: "xmark", action: cancel)
                }
            }
            ScrollView {
                LazyVStack(spacing: 16) {
                    PrototypeSearchFocusBoundary {
                        Toggle("Favorites only", isOn: $favoritesOnly)
                            .toggleStyle(SettingsSwitchToggleStyle())
                    }
                    PrototypeSearchFocusBoundary {
                        Picker("Category", selection: $category) {
                            Text("All categories").tag(String?.none)
                            ForEach(categories, id: \.self) { value in
                                Text(value).tag(Optional(value))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(channels) { channel in
                        // Native Search needs the same row-sized UIKit boundary as the guide.
                        PrototypeSearchFocusBoundary {
                            LiveTVMultiviewChannelRow(
                                channel: channel, isSelected: selectedIDs.contains(channel.id),
                                select: { select(channel) }
                            )
                            .buttonStyle(PrototypeButtonStyle(surface: .guide))
                            .focusEffectDisabled()
                        }
                    }
                    if channels.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 48)
    }
}
#endif

private struct LiveTVMultiviewChannelRow: View {
    let channel: LiveTVPrototypeChannel
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 16) {
                ChannelLogoArtwork(
                    name: channel.name, logoURL: channel.logoURL,
                    size: CGSize(width: 72, height: 48), cornerRadius: 8
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                    Text(channel.category).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(channel.name)
        .accessibilityValue(channel.category)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("live-multiview-channel-\(channel.id)")
    }
}
#endif
