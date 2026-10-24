#if os(iOS)
import CoreModels
import Observation
import SwiftUI
import UIKit

public enum PlayerMenuDestination: String, Identifiable {
    case subtitleSearch, subtitleAdvanced, audioSync, speed, zoom, quality, versions, multiview
    public var id: Self { self }
}

/// A native menu's dismissal completion, not a timer, releases sheet requests.
@MainActor @Observable
public final class PlayerMenuPresentation {
    public private(set) var isPresented = false
    public private(set) var destination: PlayerMenuDestination?
    public private(set) var generation: UInt64 = 0
    private var pending: PlayerMenuDestination?
    public var isBusy: Bool { isPresented || pending != nil || destination != nil }

    public init() {}

    public func setPresented(_ presented: Bool) {
        isPresented = presented
        if !presented, let pending {
            self.pending = nil
            destination = pending
        }
    }

    public func request(_ destination: PlayerMenuDestination, generation: UInt64) {
        guard generation == self.generation else { return }
        if isPresented { pending = destination }
        else { self.destination = destination }
    }

    public func takeDestination() -> PlayerMenuDestination? {
        guard !isPresented else { return nil }
        defer { destination = nil }
        return destination
    }

    public func reset() {
        generation &+= 1
        pending = nil
        destination = nil
        isPresented = false
    }
}

public struct PlayerMoreMenuAvailability {
    public var maximumSpeed: Double?
    public var video: Bool
    public var videoModel: PlayerVideoZoomModel?
    public var quality: Bool
    public var versions: Bool
    public var multiview: Bool

    public init(
        maximumSpeed: Double? = nil, video: Bool = true, videoModel: PlayerVideoZoomModel? = nil, quality: Bool = false,
        versions: Bool = false, multiview: Bool = false
    ) {
        self.maximumSpeed = maximumSpeed
        self.video = video
        self.videoModel = videoModel
        self.quality = quality
        self.versions = versions
        self.multiview = multiview
    }
}

@MainActor
public struct PlayerMoreMenuActions {
    public var isCurrent: () -> Bool = { true }
    public var selectAudio: (Int) -> Void = { _ in }
    public var selectSubtitle: (Int) -> Void = { _ in }
    public var setDialogueEnhancement: (Bool) -> Void = { _ in }
    public var setSpeed: (Double) -> Void = { _ in }
    public var request: (PlayerMenuDestination) -> Void = { _ in }
    public init() {}
}

@MainActor
public enum PlayerMoreMenu {
    public static let speedPresets: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    public static func hasOptions(_ model: PlayerControlsModel, availability: PlayerMoreMenuAvailability) -> Bool {
        !model.subtitleOptions.isEmpty || model.subtitleDownload.canSearch || !model.audioOptions.isEmpty
            || model.engineCapabilities.contains(.dialogEnhance) || model.engineCapabilities.contains(.audioDelay)
            || (availability.maximumSpeed != nil && model.engineCapabilities.contains(.playbackSpeed))
            || (availability.video && model.engineCapabilities.contains(.videoZoom))
            || availability.quality || availability.versions || availability.multiview
    }

    public static func make(
        model: PlayerControlsModel, availability: PlayerMoreMenuAvailability,
        locale: Locale = .current, actions: PlayerMoreMenuActions
    ) -> UIMenu {
        func localized(_ resource: LocalizedStringResource) -> String {
            var resource = resource
            resource.locale = locale
            return String(localized: resource) // l10n:content - native menu boundary.
        }
        func destination(_ title: LocalizedStringResource, icon: String, _ value: PlayerMenuDestination) -> UIAction {
            UIAction(title: localized(title), image: UIImage(systemName: icon)) { _ in actions.request(value) }
        }
        var items: [UIMenuElement] = []
        if !model.subtitleOptions.isEmpty || model.subtitleDownload.canSearch {
            let tracks = model.subtitleOptions.map { option in
                UIAction(title: option.nativeTitle, state: option.isSelected ? .on : .off) { _ in
                    actions.selectSubtitle(option.id)
                }
            }
            var subtitles: [UIMenuElement] = []
            if !tracks.isEmpty {
                subtitles.append(UIMenu(options: [.displayInline, .singleSelection], children: tracks))
            }
            var more: [UIMenuElement] = []
            if model.subtitleDownload.canSearch {
                more.append(destination("Search & Download…", icon: "magnifyingglass", .subtitleSearch))
            }
            if (model.subtitleStyleAdjustable && model.secondarySubtitleImagePrimaryFormat == nil)
                || model.subtitleDelayAdjustable || !model.secondarySubtitleOptions.isEmpty {
                more.append(destination("Advanced…", icon: "slider.horizontal.3", .subtitleAdvanced))
            }
            if !more.isEmpty { subtitles.append(UIMenu(options: .displayInline, children: more)) }
            items.append(UIMenu(title: localized("Subtitles"), image: UIImage(systemName: "captions.bubble"), children: subtitles))
        }
        if !model.audioOptions.isEmpty || model.engineCapabilities.contains(.dialogEnhance)
            || model.engineCapabilities.contains(.audioDelay) {
            let menu = PlayerAudioMenu.make(
                options: model.audioOptions,
                dialogueEnhancement: model.engineCapabilities.contains(.dialogEnhance) ? model.dialogEnhanceEnabled : nil,
                locale: locale, onSelect: actions.selectAudio, onSetDialogueEnhancement: actions.setDialogueEnhancement
            )
            var audio = menu.children
            if model.engineCapabilities.contains(.audioDelay) {
                audio.append(UIMenu(options: .displayInline, children: [
                    destination("Audio Sync…", icon: "arrow.left.and.right", .audioSync)
                ]))
            }
            items.append(UIMenu(title: menu.title, image: UIImage(systemName: "speaker.wave.2"), children: audio))
        }
        if let maximum = availability.maximumSpeed, model.engineCapabilities.contains(.playbackSpeed) {
            var speeds: [UIMenuElement] = speedPresets.filter { $0 <= maximum }.map { speed in
                let title = speed.formatted(.number.locale(locale).precision(.fractionLength(0...2))) + "×" // l10n:content - numeric rate.
                return UIAction(title: title, state: abs(model.playbackSpeed - speed) < 0.001 ? .on : .off) { _ in
                    actions.setSpeed(speed)
                }
            }
            let custom = destination("Custom…", icon: "slider.horizontal.3", .speed)
            custom.state = speedPresets.contains { $0 <= maximum && abs(model.playbackSpeed - $0) < 0.001 } ? .off : .on
            speeds.append(custom)
            items.append(UIMenu(title: localized("Playback Speed"), image: UIImage(systemName: "speedometer"),
                                options: .singleSelection, children: speeds))
        }
        var secondary: [UIMenuElement] = []
        if availability.video, model.engineCapabilities.contains(.videoZoom) {
            let zoom = PlayerZoomMenu.make(model: availability.videoModel ?? model.videoZoom, locale: locale, isCurrent: actions.isCurrent) {
                actions.request(.zoom)
            }
            secondary.append(UIMenu(title: localized("Video"), image: zoom.image,
                                    options: zoom.options, children: zoom.children))
        }
        if availability.quality { secondary.append(destination("Quality", icon: "slider.horizontal.3", .quality)) }
        if availability.versions { secondary.append(destination("Version", icon: "rectangle.stack", .versions)) }
        if availability.multiview { secondary.append(destination("Multiview", icon: "rectangle.split.2x2", .multiview)) }
        if !secondary.isEmpty { items.append(UIMenu(options: .displayInline, children: secondary)) }
        return UIMenu(children: items)
    }
}

public struct PlayerMoreMenuButton: View {
    public let model: PlayerControlsModel
    public let availability: PlayerMoreMenuAvailability
    public let presentation: PlayerMenuPresentation
    public var accessibilityIdentifier: String
    public let actions: PlayerMoreMenuActions
    @Environment(\.locale) private var locale

    public init(
        model: PlayerControlsModel, availability: PlayerMoreMenuAvailability,
        presentation: PlayerMenuPresentation, accessibilityIdentifier: String = "player-playback-options",
        actions: PlayerMoreMenuActions
    ) {
        self.model = model
        self.availability = availability
        self.presentation = presentation
        self.accessibilityIdentifier = accessibilityIdentifier
        self.actions = actions
    }

    public var body: some View {
        if PlayerMoreMenu.hasOptions(model, availability: availability) {
            PlayerOptionsMenuButton(
                accessibilityIdentifier: accessibilityIdentifier,
                makeMenu: {
                    let generation = presentation.generation
                    let isCurrent = { presentation.generation == generation && actions.isCurrent() }
                    var guarded = PlayerMoreMenuActions()
                    guarded.isCurrent = isCurrent
                    guarded.selectAudio = { if isCurrent() { actions.selectAudio($0) } }
                    guarded.selectSubtitle = { if isCurrent() { actions.selectSubtitle($0) } }
                    guarded.setDialogueEnhancement = { if isCurrent() { actions.setDialogueEnhancement($0) } }
                    guarded.setSpeed = { if isCurrent() { actions.setSpeed($0) } }
                    guarded.request = { if isCurrent() { presentation.request($0, generation: generation) } }
                    return PlayerMoreMenu.make(model: model, availability: availability, locale: locale, actions: guarded)
                },
                onPresentationChange: { presentation.setPresented($0) }
            )
            .frame(width: 44, height: 44)
            .id(presentation.generation)
        }
    }
}
#endif
