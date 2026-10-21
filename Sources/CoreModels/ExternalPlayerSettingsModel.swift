import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class ExternalPlayerSettingsModel {
    public static let shared = ExternalPlayerSettingsModel()
    public static let storageKey = "com.plozz.deviceExternalPlayer"

    public var settings: ExternalPlayerSettings {
        didSet { persist() }
    }
    public private(set) var error: ExternalPlayerError?
    private let defaults: UserDefaults
    private static let logger = Logger(subsystem: "com.plozz.app", category: "settings")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = .init()
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                settings = try JSONDecoder().decode(ExternalPlayerSettings.self, from: data)
            } catch {
                self.error = .settingsPersistence
                Self.logger.error("Unable to restore device external-player settings.")
            }
        }
    }

    /// Preserve the active viewer's existing choice once; later profile changes
    /// and imported settings must never replace the device's explicit selection.
    public func migrateIfNeeded(from legacy: ExternalPlayerSettings) {
        guard defaults.object(forKey: Self.storageKey) == nil else { return }
        settings = legacy
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.storageKey)
            error = nil
        } catch {
            self.error = .settingsPersistence
            Self.logger.error("Unable to save device external-player settings.")
        }
    }
}
