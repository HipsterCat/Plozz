#if os(iOS)
import CoreModels
import CoreUI
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlayerMoreMenuPresentationTests: XCTestCase {
    func testOneMenuOffersDirectTracksAndKeepsSearchOutsideAdvanced() throws {
        let model = controls()
        var selectedAudio: Int?
        var selectedSubtitle: Int?
        var requested: PlayerMenuDestination?
        var actions = PlayerMoreMenuActions()
        actions.selectAudio = { selectedAudio = $0 }
        actions.selectSubtitle = { selectedSubtitle = $0 }
        actions.request = { requested = $0 }
        let menu = PlayerMoreMenu.make(
            model: model, availability: .init(maximumSpeed: 2, quality: true, versions: true),
            locale: .init(identifier: "en"), actions: actions
        )
        XCTAssertEqual(visible(menu).map(\.title), ["Subtitles", "Audio", "Playback Speed", "Video", "Quality", "Version"])
        let subtitles = try submenu("Subtitles", in: menu)
        let subtitleRows = visible(subtitles).compactMap { $0 as? UIAction }
        XCTAssertEqual(subtitleRows.map(\.title), ["Off", "English (SDH)", "Search & Download…", "Advanced…"])
        XCTAssertEqual(subtitleRows[0].state, .on)
        perform(subtitleRows[1])
        XCTAssertEqual(selectedSubtitle, 9)
        perform(subtitleRows[2])
        XCTAssertEqual(requested, .subtitleSearch)
        perform(subtitleRows[3])
        XCTAssertEqual(requested, .subtitleAdvanced)
        let audio = try submenu("Audio", in: menu)
        XCTAssertFalse(visible(audio).contains { $0 is UIMenu }, "Tracks must not need a second nested menu.")
        let audioRows = visible(audio).compactMap { $0 as? UIAction }
        XCTAssertEqual(audioRows.map(\.title), ["English (Opus 5.1)", "French (AAC Stereo)"])
        perform(audioRows[1])
        XCTAssertEqual(selectedAudio, 42)
    }

    func testUnavailableFeaturesAreOmittedAndSpeedPresetsRespectEngineMaximum() throws {
        let model = controls()
        model.subtitleDownload.canSearch = false
        model.subtitleAppearance.primaryIsBurnedIn = true
        var chosenSpeed: Double?
        var destination: PlayerMenuDestination?
        var actions = PlayerMoreMenuActions()
        actions.setSpeed = { chosenSpeed = $0 }
        actions.request = { destination = $0 }
        let menu = PlayerMoreMenu.make(
            model: model, availability: .init(maximumSpeed: 1.5, video: false),
            locale: .init(identifier: "en"), actions: actions
        )
        XCTAssertEqual(visible(menu).map(\.title), ["Subtitles", "Audio", "Playback Speed"])
        XCTAssertEqual(visible(try submenu("Subtitles", in: menu)).map(\.title), ["Off", "English (SDH)"])
        let speeds = visible(try submenu("Playback Speed", in: menu)).compactMap { $0 as? UIAction }
        XCTAssertEqual(speeds.map(\.title), ["0.5×", "0.75×", "1×", "1.25×", "1.5×", "Custom…"])
        XCTAssertEqual(speeds[2].state, .on)
        perform(speeds[3])
        XCTAssertEqual(chosenSpeed, 1.25)
        perform(speeds[5])
        XCTAssertEqual(destination, .speed)
        XCTAssertEqual(chosenSpeed, 1.25, "Opening fine control must not change speed.")
        model.engineCapabilities = []
        XCTAssertFalse(visible(PlayerMoreMenu.make(
            model: model, availability: .init(maximumSpeed: 2),
            actions: .init()
        )).contains { $0.title == "Playback Speed" })
    }

    func testLiveVideoUsesTheRealZoomOwnerAndMultiviewIsDeferred() throws {
        let model = controls()
        let zoom = PlayerVideoZoomModel()
        var requested: PlayerMenuDestination?
        var actions = PlayerMoreMenuActions()
        actions.request = { requested = $0 }
        let menu = PlayerMoreMenu.make(
            model: model, availability: .init(videoModel: zoom, multiview: true),
            locale: .init(identifier: "en"), actions: actions
        )
        XCTAssertFalse(visible(menu).contains { $0.title == "Playback Speed" })
        let video = try submenu("Video", in: menu)
        let choices = video.children.compactMap { $0 as? UIAction }
        perform(choices[1])
        XCTAssertEqual(zoom.settings.mode, .fill)
        XCTAssertEqual(model.videoZoom.settings.mode, .fit)
        perform(choices[3])
        XCTAssertEqual(requested, .zoom)
        perform(try XCTUnwrap(visible(menu).first { $0.title == "Multiview" } as? UIAction))
        XCTAssertEqual(requested, .multiview)
    }

    func testPresentationWaitsForDismissalAndResetRejectsStaleRequests() {
        let presentation = PlayerMenuPresentation()
        presentation.setPresented(true)
        let generation = presentation.generation
        presentation.request(.subtitleSearch, generation: generation)
        XCTAssertTrue(presentation.isBusy)
        XCTAssertNil(presentation.destination)
        XCTAssertNil(presentation.takeDestination())
        presentation.setPresented(false)
        XCTAssertTrue(presentation.isBusy)
        XCTAssertEqual(presentation.takeDestination(), .subtitleSearch)
        XCTAssertFalse(presentation.isBusy)
        presentation.setPresented(true)
        presentation.request(.subtitleAdvanced, generation: generation)
        presentation.reset()
        presentation.setPresented(false)
        presentation.request(.quality, generation: generation)
        XCTAssertNil(presentation.takeDestination())
        XCTAssertFalse(presentation.isBusy)
    }

    func testNativeMenuOpensSheetOnlyAfterDismissalAndOldActionsCannotMutateNewContext() async throws {
        let state = FixtureState(controls: controls())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: Fixture(state: state))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            state.presentation.reset()
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await waitUntil { self.button(in: host.view) != nil }
        let button = try XCTUnwrap(button(in: host.view))
        XCTAssertEqual(button.accessibilityIdentifier, "player-playback-options")
        button.performPrimaryAction()
        try await waitUntil { button.presentedMenu != nil }
        let menu = try XCTUnwrap(button.presentedMenu)
        let audio = try submenu("Audio", in: menu)
        let oldAudio = try XCTUnwrap(visible(audio).first as? UIAction)
        let video = try submenu("Video", in: menu)
        let oldZoom = try XCTUnwrap(video.children.compactMap { $0 as? UIAction }.first)
        let subtitles = try submenu("Subtitles", in: menu)
        perform(try XCTUnwrap(visible(subtitles).first { $0.title == "Advanced…" } as? UIAction))
        XCTAssertNil(state.sheet)
        XCTAssertNil(state.presentation.destination)
        XCTAssertTrue(state.presentation.isPresented)
        let interaction = try XCTUnwrap(button.contextMenuInteraction)
        interaction.dismissMenu()
        try await waitUntil {
            state.sheet == .subtitleAdvanced && !state.presentation.isPresented
                && button.presentedMenu == nil && host.presentedViewController != nil
        }
        XCTAssertNotNil(host.presentedViewController)
        state.sheet = nil
        try await waitUntil { host.presentedViewController == nil }
        state.controls.videoZoom.settings.mode = .fill
        state.presentation.reset()
        perform(oldAudio)
        perform(oldZoom)
        XCTAssertEqual(state.audioSelections, [])
        XCTAssertEqual(state.controls.videoZoom.settings.mode, .fill)
    }

    private func controls() -> PlayerControlsModel {
        let model = PlayerControlsModel()
        model.audioOptions = [
            .init(id: 17, title: Text(verbatim: "English (Opus 5.1)"), isSelected: true, nativeTitle: "English (Opus 5.1)"),
            .init(id: 42, title: Text(verbatim: "French (AAC Stereo)"), isSelected: false, nativeTitle: "French (AAC Stereo)")
        ]
        model.subtitleOptions = [
            .init(id: -1, title: Text("Off"), isSelected: true, nativeTitle: "Off"),
            .init(id: 9, title: Text(verbatim: "English (SDH)"), isSelected: false, nativeTitle: "English (SDH)")
        ]
        model.subtitleDownload.canSearch = true
        model.engineCapabilities = [.playbackSpeed, .videoZoom]
        return model
    }

    private func visible(_ menu: UIMenu) -> [UIMenuElement] {
        menu.children.flatMap { child in
            if let group = child as? UIMenu, group.options.contains(.displayInline) { return visible(group) }
            return [child]
        }
    }

    private func submenu(_ title: String, in menu: UIMenu) throws -> UIMenu {
        try XCTUnwrap(visible(menu).first { $0.title == title } as? UIMenu)
    }

    private func perform(_ action: UIAction) {
        let button = UIButton(type: .system)
        button.addAction(action, for: .primaryActionTriggered)
        button.sendActions(for: .primaryActionTriggered)
    }

    private func button(in view: UIView) -> PlayerOptionsMenuControl? {
        if let button = view as? PlayerOptionsMenuControl { return button }
        return view.subviews.lazy.compactMap { self.button(in: $0) }.first
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition())
    }

    @MainActor @Observable
    final class FixtureState {
        let controls: PlayerControlsModel
        let presentation = PlayerMenuPresentation()
        var sheet: PlayerMenuDestination?
        var audioSelections: [Int] = []
        init(controls: PlayerControlsModel) { self.controls = controls }
    }

    private struct Fixture: View {
        @Bindable var state: FixtureState

        var body: some View {
            var actions = PlayerMoreMenuActions()
            actions.selectAudio = { state.audioSelections.append($0) }
            return PlayerMoreMenuButton(
                model: state.controls, availability: .init(maximumSpeed: 2),
                presentation: state.presentation, actions: actions
            )
            .environment(\.locale, .init(identifier: "en"))
            .task(id: state.presentation.destination) {
                if let destination = state.presentation.takeDestination() { state.sheet = destination }
            }
            .plozzSheet(item: $state.sheet) { destination in
                Text(verbatim: destination.rawValue).accessibilityIdentifier("more-menu-sheet-fixture")
            }
        }
    }
}
#endif
