import Foundation

public protocol LiveTVSourcesStoring: Sendable {
    func load() throws -> LiveTVSourcesConfiguration
    func save(_ configuration: LiveTVSourcesConfiguration) throws
}

public enum LiveTVSourcesStoreError: Error, Equatable, Sendable, LocalizedError {
    case loadFailed, invalidStoredValue, unsupportedVersion, saveFailed

    public var errorDescription: String? {
        switch self {
        case .loadFailed: "Your Live TV sources couldn't be loaded. Your saved sources have not been changed."
        case .invalidStoredValue: "Your saved Live TV sources couldn't be read. They have not been replaced."
        case .unsupportedVersion: "These Live TV sources were saved by a newer version of Plozz."
        case .saveFailed: "Your Live TV sources couldn't be saved. Try again."
        }
    }
}

/// Playlist and guide addresses may include query credentials. Never persist them in UserDefaults.
public final class LiveTVSourcesStore: LiveTVSourcesStoring, @unchecked Sendable {
    public static let baseKey = "com.plozz.liveTV.sources"
    private let secureStore: any SecureStoring
    private let key: String
    private let namespace: String?
    private let diagnostics: LiveTVSourceDiagnostics
    private let lock = NSLock()

    public init(
        secureStore: any SecureStoring, namespace: String? = nil,
        diagnostics: LiveTVSourceDiagnostics = .shared
    ) {
        self.secureStore = secureStore
        self.namespace = namespace
        self.diagnostics = diagnostics
        key = SettingsKey.scoped(Self.baseKey, namespace: namespace)
    }

    public func load() throws -> LiveTVSourcesConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return try loadLocked()
    }

    public func save(_ configuration: LiveTVSourcesConfiguration) throws {
        var completed = false
        var failure: (any Error)?
        defer {
            if !completed {
                diagnostics.record(
                    .sourceSaveFailed, identities: [.namespace: namespace ?? "default"], error: failure
                )
            }
        }
        try configuration.validate()
        let value: String
        do {
            let data = try JSONEncoder().encode(configuration)
            guard let string = String(data: data, encoding: .utf8) else {
                throw LiveTVSourcesStoreError.saveFailed
            }
            value = string
        } catch {
            throw LiveTVSourcesStoreError.saveFailed
        }
        lock.lock()
        defer { lock.unlock() }
        // Refuse a write even when a caller skipped load or the secure store became unreadable.
        _ = try loadLocked()
        do {
            try secureStore.setString(value, for: key)
            diagnostics.configuration(configuration, namespace: namespace, event: .sourceSave)
            completed = true
        } catch {
            failure = error
            throw LiveTVSourcesStoreError.saveFailed
        }
    }

    private func loadLocked() throws -> LiveTVSourcesConfiguration {
        let value: String?
        do {
            value = try secureStore.readString(for: key)
        } catch {
            diagnostics.record(
                .sourceReadFailed, identities: [.namespace: namespace ?? "default"],
                reason: .storage, error: error, deduplicate: true
            )
            throw LiveTVSourcesStoreError.loadFailed
        }
        guard let value else {
            diagnostics.record(
                .sourceMissing, identities: [.namespace: namespace ?? "default"],
                flags: [.defaultNamespace: namespace == nil], deduplicate: true
            )
            return .empty
        }
        do {
            let configuration = try JSONDecoder().decode(
                LiveTVSourcesConfiguration.self, from: Data(value.utf8)
            )
            try configuration.validate()
            diagnostics.configuration(configuration, namespace: namespace)
            return configuration
        } catch LiveTVSourcesStoreError.unsupportedVersion {
            diagnostics.record(
                .sourceReadFailed, identities: [.namespace: namespace ?? "default"],
                reason: .invalidConfiguration, deduplicate: true
            )
            throw LiveTVSourcesStoreError.unsupportedVersion
        } catch {
            diagnostics.record(
                .sourceReadFailed, identities: [.namespace: namespace ?? "default"],
                reason: .invalidConfiguration, error: error, deduplicate: true
            )
            throw LiveTVSourcesStoreError.invalidStoredValue
        }
    }
}
