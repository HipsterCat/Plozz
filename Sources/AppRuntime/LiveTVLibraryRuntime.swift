#if DEBUG
import CoreModels
import CoreNetworking
import FeatureLiveTVCore
import FeaturePlayback
import Foundation
import Observation

@MainActor
private final class LiveTVLibraryAuthority {
    let profileID: String
    let preferencesNamespace: String?
    weak var profiles: ProfilesModel?
    weak var accounts: AccountsProvidersModel?
    var expectedAccounts: String?

    init(profileID: String, profiles: ProfilesModel) {
        self.profileID = profileID
        preferencesNamespace = LiveTVLibraryStorage.preferencesNamespace(profileID: profileID, profiles: profiles)
        self.profiles = profiles
    }

    var isAuthorized: Bool {
        guard let profiles, profiles.activeProfileID == profileID,
              preferencesNamespace == LiveTVLibraryStorage.preferencesNamespace(
                profileID: profileID, profiles: profiles
              ) else { return false }
        return expectedAccounts != nil
            && expectedAccounts == (accounts?.liveTVAuthorizationID ?? "")
    }
}

/// Shared by the active profile's guide and source editor, not by another profile.
@MainActor
@Observable
public final class LiveTVLibraryRuntime {
    public let profileID: String
    public let preferencesNamespace: String?
    public let service: LibraryChannelService
    public let history: LibraryChannelHistorySettings
    public let trackPreferences: LiveChannelTrackPreferences
    public private(set) var isLoading = false
    public private(set) var issue: LibraryChannelError?
    public private(set) var unavailableAccountIDs: Set<String> = []
    public private(set) var refreshRequest = 0
    @ObservationIgnored private let authority: LiveTVLibraryAuthority
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var loadedRefreshRequest: Int?
    private var acceptedAuthorization: String?

    public init(profileID: String, profiles: ProfilesModel) {
        self.profileID = profileID
        let authority = LiveTVLibraryAuthority(profileID: profileID, profiles: profiles)
        self.authority = authority
        preferencesNamespace = authority.preferencesNamespace
        history = LibraryChannelHistorySettings.shared(namespace: authority.preferencesNamespace)
        trackPreferences = LiveChannelTrackPreferences(namespace: authority.preferencesNamespace)
        service = LibraryChannelService(
            profileID: profileID,
            store: LiveTVLibraryStorage.definitions(profileID: profileID, namespace: authority.preferencesNamespace),
            snapshotStore: LiveTVLibraryStorage.snapshots,
            isActive: { authority.isAuthorized }
        )
    }

    public var authorizationID: String? {
        guard authority.isAuthorized, !isLoading else { return nil }
        return acceptedAuthorization
    }

    public func retry() {
        refreshRequest &+= 1
    }

    public func applyPortableChanges() {
        do {
            if try LiveTVLibraryStorage.definitions(
                profileID: profileID, namespace: preferencesNamespace
            ).load() != service.definitions {
                retry()
            }
        } catch {
            acceptedAuthorization = nil
            issue = .storageFailed
            PlozzLog.app.error("Live TV shared library definitions could not be read")
        }
    }

    public func refresh(accounts: AccountsProvidersModel?) async {
        if loadedRefreshRequest == refreshRequest,
           authority.accounts === accounts, authorizationID != nil, service.isLoaded { return }
        let requested = refreshRequest
        let stamp = UUID()
        refreshID = stamp
        isLoading = true
        issue = nil
        unavailableAccountIDs = []
        acceptedAuthorization = nil
        authority.accounts = accounts
        authority.expectedAccounts = nil
        service.setContexts([])
        let expected = accounts?.liveTVAuthorizationID ?? ""
        defer {
            if refreshID == stamp { isLoading = false }
        }
        do {
            try check(stamp, accounts: accounts, expected: expected)
            var contexts: [LibraryChannelProviderContext] = []
            for resolved in accounts?.resolvedActiveAccounts ?? [] {
                guard let provider = resolved.provider as? any LibraryChannelCatalogProviding,
                      provider is any LibraryChannelPlaybackProviding else { continue }
                do {
                    let libraries = try await provider.libraries()
                    try check(stamp, accounts: accounts, expected: expected)
                    contexts.append(LibraryChannelProviderContext(
                        accountID: resolved.account.id,
                        authorizationID: expected,
                        provider: provider,
                        allowedLibraryIDs: Set(libraries.map(\.id))
                    ))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try check(stamp, accounts: accounts, expected: expected)
                    unavailableAccountIDs.insert(resolved.account.id)
                    PlozzLog.app.error("Live TV library discovery failed for an authorized source")
                }
            }
            try check(stamp, accounts: accounts, expected: expected)
            authority.expectedAccounts = expected
            service.setContexts(contexts)
            try await service.load()
            try check(stamp, accounts: accounts, expected: expected)
            acceptedAuthorization = expected + "|" + stamp.uuidString
            loadedRefreshRequest = requested
            issue = service.issue ?? (unavailableAccountIDs.isEmpty ? nil : .sourceUnavailable)
        } catch is CancellationError {
            if refreshID == stamp {
                authority.expectedAccounts = nil
                issue = .authorizationChanged
            }
        } catch {
            guard refreshID == stamp else { return }
            authority.expectedAccounts = nil
            issue = (error as? LibraryChannelError) ?? .storageFailed
            PlozzLog.app.error("Live TV library catalog could not be prepared")
        }
    }

    private func check(_ stamp: UUID, accounts: AccountsProvidersModel?, expected: String) throws {
        try Task.checkCancellation()
        guard refreshID == stamp, let profiles = authority.profiles, profiles.activeProfileID == profileID,
              preferencesNamespace == LiveTVLibraryStorage.preferencesNamespace(
                profileID: profileID, profiles: profiles
              ),
              (accounts?.liveTVAuthorizationID ?? "") == expected else {
            throw CancellationError()
        }
    }
}
#endif
