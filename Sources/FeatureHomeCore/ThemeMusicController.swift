#if canImport(AVFoundation)
import AVFoundation
import CoreModels
import CoreNetworking
import CoreUI
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Plays a detail page's theme without publishing Now Playing information or
/// claiming remote commands from video and full music playback.
@MainActor
@Observable
public final class ThemeMusicController: ThemeMusicPreviewControlling {
    public private(set) var isPlaying = false
    public private(set) var currentPlaybackID: String?
    public private(set) var isBlocked = false
    public private(set) var isAppActive = true
    public private(set) var isInterrupted = false
    public private(set) var previewOwner: UUID?
    public private(set) var failure: LocalizedStringResource?
    public var isPreviewing: Bool { previewOwner != nil }

    let player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var fadeTimeObserver: Any?
    private var fadeTarget: Float = 0
    private var hasFadedIn = false
    private var hasStartedPlayback = false
    private let fadeInDuration: Double = 5
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var sampleURL: URL?

    public init() {
        #if canImport(UIKit)
        observe(UIApplication.willResignActiveNotification) { controller, _ in controller.setAppActive(false) }
        observe(UIApplication.didBecomeActiveNotification) { controller, _ in controller.setAppActive(true) }
        observe(AVAudioSession.interruptionNotification) { controller, notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            controller.setInterrupted(type == .began)
        }
        #endif
    }

    private var canPlay: Bool { !isBlocked && isAppActive && !isInterrupted }

    public func setAppActive(_ active: Bool) {
        isAppActive = active
        if !active, isPreviewing {
            stop()
        } else if active, canPlay, currentPlaybackID != nil {
            beginPlaybackIfReady()
        } else if !active {
            player.pause()
            isPlaying = false
        }
    }

    func setInterrupted(_ interrupted: Bool) {
        isInterrupted = interrupted
        if interrupted {
            if isPreviewing { stop() }
            player.pause()
            isPlaying = false
        } else if canPlay, currentPlaybackID != nil {
            beginPlaybackIfReady()
        }
    }

    private func observe(
        _ name: Notification.Name,
        action: @escaping @MainActor (ThemeMusicController, Notification) -> Void
    ) {
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                if let self { action(self, notification) }
            }
        })
    }

    public func setBlocked(_ blocked: Bool) {
        isBlocked = blocked
        if blocked {
            stop()
        }
    }

    public func play(
        _ theme: ThemeMusic,
        resolvedURL: URL,
        playbackID: String,
        settings: ThemeMusicSettings
    ) {
        guard settings.shouldPlay, canPlay, !isPreviewing else {
            stop(ifPlaying: playbackID)
            return
        }

        if currentPlaybackID == playbackID {
            updateVolume(settings.volume)
            return
        }

        stopPlayback(resetItem: true)
        guard activateSession() else { return }

        let item = AVPlayerItem(url: resolvedURL)
        player.volume = 0
        fadeTarget = settings.volume.gain
        hasFadedIn = false
        hasStartedPlayback = false
        observeEnd(of: item)
        observeStatus(of: item, themeURL: resolvedURL)
        player.replaceCurrentItem(with: item)

        isPlaying = true
        currentPlaybackID = playbackID
        PlozzLog.app.info(
            "Theme music: queued item=\(theme.itemID) volume=\(settings.volume.gain) url=\(PlozzLog.redact(url: resolvedURL))"
        )
    }

    public func stop() {
        guard isPlaying || currentPlaybackID != nil || previewOwner != nil else { return }
        stopPlayback(resetItem: true)
        previewOwner = nil
        if let sampleURL {
            do {
                try FileManager.default.removeItem(at: sampleURL)
            } catch {
                PlozzLog.app.error("Theme music: sample cleanup failed type=\(String(describing: type(of: error)))")
            }
            self.sampleURL = nil
        }
        PlozzLog.app.info("Theme music: stopped")
    }

    public func stop(ifPlaying playbackID: String) {
        guard currentPlaybackID == playbackID else { return }
        stop()
    }

    public func updateVolume(_ volume: ThemeMusicVolume) {
        fadeTarget = volume.gain
        if hasFadedIn || isPreviewing { player.volume = fadeTarget }
    }

    public func stopPreview(owner: UUID) {
        guard previewOwner == owner else { return }
        stop()
    }

    public func preview(
        owner: UUID, volume: ThemeMusicVolume,
        resolve: @MainActor () async throws -> ThemeMusic?,
        authenticatedHTTPResolver: (any AuthenticatedHTTPResourceResolving)?
    ) async {
        guard canPlay else { return }
        stop()
        failure = nil
        previewOwner = owner
        updateVolume(volume)
        do {
            let theme = try await resolve()
            try Task.checkCancellation()
            guard previewOwner == owner, canPlay else { return }
            let url: URL
            if let theme {
                url = try await resolveThemeMusicURL(
                    theme, authenticatedHTTPResolver: authenticatedHTTPResolver
                )
            } else {
                let generated = FileManager.default.temporaryDirectory
                    .appendingPathComponent("plozz-theme-preview-\(UUID().uuidString).wav")
                try ThemeMusicPreviewSample.data().write(to: generated, options: .atomic)
                sampleURL = generated
                url = generated
            }
            try Task.checkCancellation()
            guard previewOwner == owner, canPlay else { return }
            guard activateSession() else {
                stopPreview(owner: owner)
                return
            }
            let item = AVPlayerItem(url: url)
            item.forwardPlaybackEndTime = CMTime(seconds: 15, preferredTimescale: 600)
            hasFadedIn = true
            hasStartedPlayback = false
            player.volume = fadeTarget
            observeEnd(of: item)
            observeStatus(of: item, themeURL: url)
            currentPlaybackID = "preview:\(owner.uuidString)"
            player.replaceCurrentItem(with: item)
        } catch is CancellationError {
            stopPreview(owner: owner)
        } catch {
            guard previewOwner == owner else { return }
            failure = "Couldn't play theme preview. Try again."
            PlozzLog.app.error("Theme music: preview failed type=\(String(describing: type(of: error)))")
            stopPreview(owner: owner)
        }
    }

    private func stopPlayback(resetItem: Bool) {
        removeFadeObserver()
        hasFadedIn = false
        hasStartedPlayback = false
        player.pause()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        if resetItem {
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            currentPlaybackID = nil
        }
    }

    private func beginPlaybackIfReady() {
        guard canPlay, player.currentItem?.status == .readyToPlay else { return }
        if !hasStartedPlayback {
            hasStartedPlayback = true
            if !isPreviewing { installFadeObserver() }
        }
        player.play()
        isPlaying = true
    }

    private func installFadeObserver() {
        removeFadeObserver()
        guard fadeTarget > 0, fadeInDuration > 0 else {
            player.volume = fadeTarget
            hasFadedIn = true
            return
        }

        player.volume = 0
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        fadeTimeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.hasFadedIn else { return }
                let elapsed = time.seconds
                guard elapsed.isFinite else { return }
                if elapsed >= self.fadeInDuration {
                    self.player.volume = self.fadeTarget
                    self.hasFadedIn = true
                    self.removeFadeObserver()
                } else {
                    self.player.volume = self.fadeTarget * Float(
                        max(0, elapsed / self.fadeInDuration)
                    )
                }
            }
        }
    }

    private func removeFadeObserver() {
        guard let fadeTimeObserver else { return }
        player.removeTimeObserver(fadeTimeObserver)
        self.fadeTimeObserver = nil
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleItemDidEnd()
            }
        }
    }

    private func handleItemDidEnd() {
        if isPreviewing, canPlay {
            player.seek(to: .zero)
            player.play()
        } else {
            stop()
        }
    }

    private func observeStatus(of item: AVPlayerItem, themeURL: URL) {
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            MainActor.assumeIsolated {
                guard let self, self.player.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    PlozzLog.app.info(
                        "Theme music: ready url=\(PlozzLog.redact(url: themeURL))"
                    )
                    self.beginPlaybackIfReady()
                case .failed:
                    self.failure = "Couldn't play theme preview. Try again."
                    PlozzLog.app.error(
                        "Theme music: failed url=\(PlozzLog.redact(url: themeURL))"
                    )
                    self.stop()
                default:
                    break
                }
            }
        }
    }

    private func activateSession() -> Bool {
        #if !os(macOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            failure = "Couldn't play theme preview. Try again."
            PlozzLog.app.error(
                "Theme music: audio session activation failed type=\(String(describing: type(of: error)))"
            )
            return false
        }
        #endif
        return true
    }

    isolated deinit {
        for observer in lifecycleObservers { NotificationCenter.default.removeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let fadeTimeObserver { player.removeTimeObserver(fadeTimeObserver) }
        player.pause()
        if let sampleURL {
            do { try FileManager.default.removeItem(at: sampleURL) }
            catch { PlozzLog.app.error("Theme music: sample cleanup failed during teardown") }
        }
    }
}
#endif
