#if canImport(SwiftUI) && canImport(AVFoundation)
import CoreModels
import CoreNetworking
import CoreUI
import SwiftUI

private struct ThemeMusicControllerKey: EnvironmentKey {
    static let defaultValue: ThemeMusicController? = nil
}

private struct ThemeMusicSettingsKey: EnvironmentKey {
    static let defaultValue = ThemeMusicSettings.default
}

private struct ThemeMusicDetailAllowedKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    var themeMusicDetailAllowed: Bool {
        get { self[ThemeMusicDetailAllowedKey.self] }
        set { self[ThemeMusicDetailAllowedKey.self] = newValue }
    }

    var themeMusicController: ThemeMusicController? {
        get { self[ThemeMusicControllerKey.self] }
        set { self[ThemeMusicControllerKey.self] = newValue }
    }

    var themeMusicSettings: ThemeMusicSettings {
        get { self[ThemeMusicSettingsKey.self] }
        set { self[ThemeMusicSettingsKey.self] = newValue }
    }

}

private struct ThemeMusicPlaybackTaskID: Equatable {
    let playbackID: String?
    let settings: ThemeMusicSettings
    let isBlocked: Bool
    let isPreviewing: Bool
    let isAllowed: Bool
    let isAppActive: Bool
}

private struct ThemeMusicPlaybackModifier: ViewModifier {
    let playbackID: String?
    let resolve: () async -> ThemeMusic?
    let isActive: Bool

    @Environment(\.themeMusicController) private var controller
    @Environment(\.themeMusicSettings) private var settings
    @Environment(\.themeMusicAuthenticatedHTTPResolver) private var authenticatedHTTPResolver
    @Environment(\.themeMusicDetailAllowed) private var detailAllowed
    @State private var resolutionGeneration: UInt64 = 0

    private var taskID: ThemeMusicPlaybackTaskID {
        ThemeMusicPlaybackTaskID(
            playbackID: playbackID,
            settings: settings,
            isBlocked: controller?.isBlocked ?? true,
            isPreviewing: controller?.isPreviewing ?? false,
            isAllowed: detailAllowed && isActive,
            isAppActive: controller?.isAppActive ?? false
        )
    }

    func body(content: Content) -> some View {
        content
            .task(id: taskID) {
                resolutionGeneration &+= 1
                let generation = resolutionGeneration
                guard let controller else { return }
                guard !controller.isPreviewing else { return }
                guard isActive, detailAllowed else {
                    if let playbackID { controller.stop(ifPlaying: playbackID) }
                    return
                }
                guard let playbackID else {
                    controller.stop()
                    return
                }
                guard settings.shouldPlay, !controller.isBlocked, detailAllowed, isActive else {
                    controller.stop(ifPlaying: playbackID)
                    return
                }
                guard controller.isAppActive else { return }
                if controller.currentPlaybackID != playbackID {
                    controller.stop()
                }
                if controller.currentPlaybackID == playbackID {
                    controller.updateVolume(settings.volume)
                    return
                }
                guard let theme = await resolve(),
                      !Task.isCancelled,
                      generation == resolutionGeneration else {
                    return
                }
                do {
                    let resolvedURL = try await resolveThemeMusicURL(
                        theme,
                        authenticatedHTTPResolver: authenticatedHTTPResolver
                    )
                    guard !Task.isCancelled,
                          generation == resolutionGeneration,
                          !controller.isBlocked else {
                        return
                    }
                    controller.play(
                        theme,
                        resolvedURL: resolvedURL,
                        playbackID: playbackID,
                        settings: settings
                    )
                } catch {
                    guard !Task.isCancelled,
                          generation == resolutionGeneration else {
                        return
                    }
                    controller.stop(ifPlaying: playbackID)
                    PlozzLog.app.error(
                        "Theme music: source resolution failed item=\(theme.itemID) error=\(String(describing: error))"
                    )
                }
            }
            .onDisappear {
                resolutionGeneration &+= 1
                guard let playbackID else { return }
                controller?.stop(ifPlaying: playbackID)
            }
    }
}

private struct ThemeMusicScope: ViewModifier {
    let controller: ThemeMusicController
    let model: ThemeMusicSettingsModel
    let background: HeroBackgroundSettings
    let isBlocked: Bool
    let detailAllowed: Bool
    let authenticatedHTTPResolver: any AuthenticatedHTTPResourceResolving
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .environment(\.themeMusicController, controller)
            .environment(\.themeMusicPreviewController, controller)
            .environment(\.themeMusicSettings, model.settings)
            .environment(\.themeMusicAuthenticatedHTTPResolver, authenticatedHTTPResolver)
            .environment(\.themeMusicDetailAllowed, detailAllowed)
            .onChange(of: background.themeMusicEnabled, initial: true) { _, enabled in
                if model.settings.isEnabled != enabled { model.settings.isEnabled = enabled }
                if !enabled { controller.stop() }
            }
            .onChange(of: ObjectIdentifier(model)) {
                controller.stop()
                model.settings.isEnabled = background.themeMusicEnabled
            }
            .onChange(of: isBlocked, initial: true) { _, blocked in
                controller.setBlocked(blocked)
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                controller.setAppActive(phase == .active)
            }
            .onDisappear { controller.stop() }
    }
}

enum ThemeMusicSourceResolutionError: Error, Equatable {
    case missingAuthenticatedResolver
    case unsupportedSource
}

@MainActor
func resolveThemeMusicURL(
    _ theme: ThemeMusic,
    authenticatedHTTPResolver: (any AuthenticatedHTTPResourceResolving)?
) async throws -> URL {
    switch theme.playbackSource {
    case .publicURL(let source):
        return source.url
    case .authenticatedHTTP(let locator):
        guard let authenticatedHTTPResolver else {
            throw ThemeMusicSourceResolutionError.missingAuthenticatedResolver
        }
        return try await authenticatedHTTPResolver.resolve(locator)
    case .networkFile, .dlnaResource:
        throw ThemeMusicSourceResolutionError.unsupportedSource
    }
}

public extension View {
    func themeMusicScope(
        controller: ThemeMusicController,
        model: ThemeMusicSettingsModel,
        background: HeroBackgroundSettings,
        isBlocked: Bool,
        detailAllowed: Bool = true,
        authenticatedHTTPResolver: any AuthenticatedHTTPResourceResolving
    ) -> some View {
        modifier(ThemeMusicScope(
            controller: controller, model: model, background: background,
            isBlocked: isBlocked, detailAllowed: detailAllowed,
            authenticatedHTTPResolver: authenticatedHTTPResolver
        ))
    }

    func themeMusicPlayback(
        playbackID: String?,
        isActive: Bool = true,
        resolve: @escaping () async -> ThemeMusic?
    ) -> some View {
        modifier(
            ThemeMusicPlaybackModifier(
                playbackID: playbackID,
                resolve: resolve,
                isActive: isActive
            )
        )
    }
}
#endif
