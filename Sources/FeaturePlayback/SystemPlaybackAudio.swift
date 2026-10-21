#if os(tvOS)
import AVFoundation
import CoreNetworking
import Foundation
import Observation
import SwiftUI

enum SystemPlaybackAudioSetting: Int, CaseIterable {
    case enhanceDialogue = -101
    case reduceLoudSounds = -100

    var title: LocalizedStringResource {
        switch self {
        case .reduceLoudSounds: "Reduce Loud Sounds"
        case .enhanceDialogue: "Enhance Dialogue"
        }
    }

    var availabilityKey: String {
        switch self {
        case .reduceLoudSounds: "lateNightModeIsAvailable"
        case .enhanceDialogue: "enhanceDialogIsAvailable"
        }
    }

    var enabledKey: String {
        switch self {
        case .reduceLoudSounds: "latenightmode"
        case .enhanceDialogue: "enhancedialog"
        }
    }

    func notification(enabled: Bool) -> Notification.Name {
        switch (self, enabled) {
        case (.reduceLoudSounds, true): .init("com.apple.TVPAudioVideoSettings.enableLateNightMode")
        case (.reduceLoudSounds, false): .init("com.apple.TVPAudioVideoSettings.disableLateNightMode")
        case (.enhanceDialogue, true): .init("com.apple.TVPAudioVideoSettings.enableEnhanceDialog")
        case (.enhanceDialogue, false): .init("com.apple.TVPAudioVideoSettings.disableEnhanceDialog")
        }
    }
}

enum SystemDialogueLevel: Int {
    case off = 0, enhance = 1, enhanceMore = 2, isolate = 3

    // Isolate has an additional Accessibility gate. Preserve its reported state,
    // but don't offer it without a verified availability signal for that mode.
    static let choices: [Self] = [.enhanceMore, .enhance, .off]

    var title: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .enhance: "Enhance"
        case .enhanceMore: "Enhance More"
        case .isolate: "Isolate"
        }
    }

    static func effective(enabled: Bool, rawValue: Int?) -> Self {
        guard enabled else { return .off }
        guard let rawValue, let level = Self(rawValue: rawValue), level != .off else {
            return .enhance
        }
        return level
    }

    var command: (name: Notification.Name, object: String?) {
        if self == .off {
            return (SystemPlaybackAudioSetting.enhanceDialogue.notification(enabled: false), nil)
        }
        return (.init("com.apple.TVPAudioVideoSettings.setEnhanceDialogueLevel"), String(rawValue))
    }
}

struct SystemPlaybackAudioState: Equatable {
    var values: [SystemPlaybackAudioSetting: Bool]
    var dialogueLevel: SystemDialogueLevel? = nil
}

@MainActor
protocol SystemPlaybackAudioControlling {
    func read() -> SystemPlaybackAudioState
    func setEnabled(_ enabled: Bool, for setting: SystemPlaybackAudioSetting) throws
    func setDialogueLevel(_ level: SystemDialogueLevel) throws
}

extension SystemPlaybackAudioControlling {
    func setDialogueLevel(_ level: SystemDialogueLevel) throws {
        throw SystemPlaybackAudio.Failure.unavailable
    }
}

/// Undocumented tvOS integration: the system owns availability, processing and
/// persistence. Never write the preference domain or mirror it in profile state.
@MainActor
struct SystemPlaybackAudioPreferences: SystemPlaybackAudioControlling {
    private let domain = "com.apple.preferences-sounds" as CFString

    private var notificationCenter: NotificationCenter? {
        (NSClassFromString("NSDistributedNotificationCenter") as? NotificationCenter.Type)?.default
    }

    func read() -> SystemPlaybackAudioState {
        CFPreferencesAppSynchronize(domain)
        let values = Self.availableValues(canPost: notificationCenter != nil) { key in
            CFPreferencesGetAppBooleanValue(key as CFString, domain, nil)
        }
        let offersLevels = values[.enhanceDialogue] != nil
            && CFPreferencesGetAppBooleanValue("enhanceDialogueLevelsIsAvailable" as CFString, domain, nil)
        let level = offersLevels ? SystemDialogueLevel.effective(
            enabled: values[.enhanceDialogue] == true,
            rawValue: CFPreferencesCopyAppValue("enhancedialoguelevel" as CFString, domain) as? Int
        ) : nil
        return SystemPlaybackAudioState(values: values, dialogueLevel: level)
    }

    static func availableValues(
        canPost: Bool, readBoolean: (String) -> Bool
    ) -> [SystemPlaybackAudioSetting: Bool] {
        guard canPost else { return [:] }
        var values: [SystemPlaybackAudioSetting: Bool] = [:]
        for setting in SystemPlaybackAudioSetting.allCases where readBoolean(setting.availabilityKey) {
            values[setting] = readBoolean(setting.enabledKey)
        }
        return values
    }

    func setEnabled(_ enabled: Bool, for setting: SystemPlaybackAudioSetting) throws {
        guard let center = notificationCenter, read().values[setting] != nil else {
            throw SystemPlaybackAudio.Failure.unavailable
        }
        center.post(name: setting.notification(enabled: enabled), object: nil)
    }

    func setDialogueLevel(_ level: SystemDialogueLevel) throws {
        guard SystemDialogueLevel.choices.contains(level), let center = notificationCenter,
              read().dialogueLevel != nil else {
            throw SystemPlaybackAudio.Failure.unavailable
        }
        let command = level.command
        center.post(name: command.name, object: command.object)
    }
}

@MainActor @Observable
final class SystemPlaybackAudio {
    enum Failure: Error {
        case unavailable
        case unconfirmed
    }

    static let shared = SystemPlaybackAudio(backend: SystemPlaybackAudioPreferences())

    private let backend: any SystemPlaybackAudioControlling
    private(set) var state: SystemPlaybackAudioState
    private(set) var pending: Set<SystemPlaybackAudioSetting> = []
    var failure: Failure?

    init(backend: any SystemPlaybackAudioControlling) {
        self.backend = backend
        state = backend.read()
    }

    var values: [SystemPlaybackAudioSetting: Bool] { state.values }
    var dialogueLevel: SystemDialogueLevel? { state.dialogueLevel }

    var availableSettings: [SystemPlaybackAudioSetting] {
        SystemPlaybackAudioSetting.allCases.filter { values[$0] != nil }
    }

    func refresh() {
        let latest = backend.read()
        if latest != state { state = latest }
    }

    func setEnabled(_ enabled: Bool, for setting: SystemPlaybackAudioSetting) async {
        await apply(setting, isSupported: { $0.values[setting] != nil },
                    isConfirmed: { $0.values[setting] == enabled }) {
            try backend.setEnabled(enabled, for: setting)
        }
    }

    func setDialogueLevel(_ level: SystemDialogueLevel) async {
        await apply(.enhanceDialogue, isSupported: {
            $0.dialogueLevel != nil && SystemDialogueLevel.choices.contains(level)
        }, isConfirmed: {
            $0.dialogueLevel == level && $0.values[.enhanceDialogue] == (level != .off)
        }) {
            try backend.setDialogueLevel(level)
        }
    }

    private func apply(
        _ setting: SystemPlaybackAudioSetting,
        isSupported: (SystemPlaybackAudioState) -> Bool,
        isConfirmed: (SystemPlaybackAudioState) -> Bool,
        send: () throws -> Void
    ) async {
        guard !pending.contains(setting) else { return }
        failure = nil
        refresh()
        guard isSupported(state) else {
            report(.unavailable)
            return
        }
        guard !isConfirmed(state) else { return }
        pending.insert(setting)
        defer { pending.remove(setting) }
        do {
            try Task.checkCancellation()
            try send()
            // Posting is not acknowledgement. Keep the real checkmark until the
            // system confirms, including when the output changes during the wait.
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(100))
                refresh()
                guard isSupported(state) else {
                    report(.unavailable)
                    return
                }
                if isConfirmed(state) { return }
            }
            report(.unconfirmed)
        } catch is CancellationError {
            refresh()
            PlozzLog.playback.debug("System audio setting confirmation was cancelled.")
        } catch {
            report(.unavailable)
        }
    }

    private func report(_ failure: Failure) {
        self.failure = failure
        PlozzLog.playback.error("System audio setting change failed: \(String(describing: failure))")
    }
}

/// Refresh only while transport controls are visible. The system does not offer
/// a public preference-change notification for changes made in Control Center.
private struct SystemPlaybackAudioObservation: ViewModifier {
    let audio: SystemPlaybackAudio
    let isVisible: Bool
    @Environment(\.scenePhase) private var scenePhase

    private var isActive: Bool { isVisible && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
                if isActive { audio.refresh() }
            }
            .task(id: isActive) {
                guard isActive else { return }
                do {
                    while !Task.isCancelled {
                        audio.refresh()
                        try await Task.sleep(for: .seconds(1))
                    }
                } catch is CancellationError {
                    // SwiftUI cancels the visible-controls lifetime.
                } catch {
                    PlozzLog.playback.error("System audio setting refresh timer failed.")
                }
            }
    }
}

extension View {
    func observingSystemPlaybackAudio(_ audio: SystemPlaybackAudio, isVisible: Bool) -> some View {
        modifier(SystemPlaybackAudioObservation(audio: audio, isVisible: isVisible))
    }
}
#endif
