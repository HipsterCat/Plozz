import CoreModels
import Foundation
import Observation

public struct LiveTVSourcesCatalogAuthority: Equatable, Sendable {
    public let configuration: LiveTVSourcesConfiguration
    public let authorization: LiveTVSourceAuthorization

    public init(configuration: LiveTVSourcesConfiguration, authorization: LiveTVSourceAuthorization) {
        var sources = configuration
        // Sync receipts are bookkeeping, not source settings or profile authority.
        sources.syncCheckpoint = nil
        self.configuration = sources
        self.authorization = authorization
    }
}

/// Retain once per Sources presentation/profile. Cache and transport are injected
/// shared instances; this controller creates neither a connection nor a network actor.
@MainActor
@Observable
public final class LiveTVSourcesCatalog {
    public enum Issue: Equatable {
        case configuration, authorization, catalog
        case enrollment(LiveTVServerImportError)

        public var message: LocalizedStringResource {
            switch self {
            case .configuration: "Your saved Live TV sources couldn't be read."
            case .authorization: "Profile access changed. Reopen Sources to continue."
            case .catalog: "Channel and guide data couldn't be loaded. Retry to refresh it."
            case .enrollment(let failure): failure.userDescription
            }
        }
    }

    public let imports: LiveTVPrototypeImportModel
    public let catalog: LiveTVPrototypeModel
    public private(set) var isLoading = false
    /// Page-wide failures. Individual source failures remain on `imports`.
    public private(set) var issue: Issue?
    public var isCurrent: Bool { admission.isCurrent }
    /// Display-only state. Operations still revalidate `isCurrent` against the
    /// durable source configuration before publishing, scanning or mutating.
    public var isPresentationCurrent: Bool {
        admission.snapshot != nil && admission.presentationIsAuthorized()
    }
    public var profileID: String { admission.profileID }

    @ObservationIgnored private let admission: LiveTVSourcesCatalogAdmission
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let prepareSources: @MainActor () async -> LiveTVServerImportError?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRequest = 0
    @ObservationIgnored private var activeRefresh = false

    /// `authority` must return nil while locked/inactive and must reflect current
    /// source configuration and local approvals, not a captured authorization snapshot.
    public init(
        profileID: String,
        cache: LiveTVIndexedCache,
        loader: any LiveTVSourceLoading,
        preferencesStore: any LiveTVPreferencesStoring,
        authority: @escaping @MainActor () throws -> LiveTVSourcesCatalogAuthority?,
        presentationIsAuthorized: @escaping @MainActor () -> Bool = { true },
        serverProviderResolver: @escaping LiveTVServerProviderResolver = { _ in nil },
        prepareSources: @escaping @MainActor () async -> LiveTVServerImportError? = { nil },
        clock: @escaping @MainActor () -> Date = Date.init
    ) {
        let admission = LiveTVSourcesCatalogAdmission(
            profileID: profileID, authority: authority,
            presentationIsAuthorized: presentationIsAuthorized
        )
        self.admission = admission
        self.clock = clock
        self.prepareSources = prepareSources
        catalog = LiveTVPrototypeModel(now: clock(), channels: [], preferencesStore: preferencesStore)
        imports = LiveTVPrototypeImportModel(
            loader: loader, serverProviderResolver: serverProviderResolver, cache: cache,
            catalogIsAuthorized: { admission.isClearing || admission.isCurrent }
        )
    }

    deinit { refreshTask?.cancel() }

    /// Prepares newly authorized sources, then hydrates their cached catalog without a guide refresh.
    public func restore() async { await load(refresh: false) }

    public func refresh() async { await load(refresh: true) }

    public func refresh(sourceID: String) async { await load(refresh: true, sourceID: sourceID) }

    public func requestRefresh() {
        if refreshTask != nil, isLoading, isCurrent { return }
        refreshTask?.cancel()
        refreshRequest &+= 1
        let request = refreshRequest
        refreshTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.refresh()
            if self.refreshRequest == request { self.refreshTask = nil }
        }
    }

    /// Call synchronously on profile lock/switch or authority changes, before scheduling a reload.
    public func invalidate() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshRequest &+= 1
        revision &+= 1
        isLoading = false
        admission.snapshot = nil
        clearCatalog()
    }

    private func load(refresh: Bool, sourceID: String? = nil) async {
        guard !Task.isCancelled else { return }
        let authority: LiveTVSourcesCatalogAuthority
        do {
            guard let current = try admission.authority(),
                  current.authorization.profileID == admission.profileID else {
                recordAdmissionFailure(stage: .initial)
                invalidate()
                issue = .authorization
                return
            }
            try current.configuration.validate()
            authority = current
        } catch {
            recordAdmissionFailure(stage: .configuration)
            invalidate()
            issue = .configuration
            return
        }
        if isLoading, admission.snapshot == authority, activeRefresh || !refresh { return }
        if admission.snapshot != authority || isLoading {
            revision &+= 1
            guard clearCatalog() else {
                admission.snapshot = nil
                isLoading = false
                return
            }
        }
        admission.snapshot = authority
        revision &+= 1
        let request = revision
        isLoading = true
        activeRefresh = refresh
        let previousEnrollmentFailure: LiveTVServerImportError?
        if case .enrollment(let failure) = issue { previousEnrollmentFailure = failure }
        else { previousEnrollmentFailure = nil }
        issue = nil
        defer { if revision == request { isLoading = false } }
        do {
            let enrollmentFailure = sourceID == nil ? await prepareSources() : previousEnrollmentFailure
            guard revision == request, !Task.isCancelled else { return }
            guard let prepared = try admission.authority(),
                  prepared.authorization.profileID == admission.profileID else {
                recordAdmissionFailure(stage: .prepared)
                invalidate()
                issue = .authorization
                return
            }
            try prepared.configuration.validate()
            admission.snapshot = prepared
            catalog.synchronizeClock(to: clock())
            try imports.applyConfiguration(
                prepared.authorization.filtering(prepared.configuration), into: catalog
            )
            if refresh {
                if let sourceID {
                    try await imports.reloadSource(sourceID, into: catalog)
                } else {
                    await imports.reload(into: catalog)
                }
            } else {
                await imports.restoreCachedCatalog(into: catalog, now: catalog.now)
                guard revision == request, !Task.isCancelled else { return }
                if admission.isCurrent { await imports.restoreCachedServerCatalogs(into: catalog) }
            }
            guard revision == request else { return }
            guard !Task.isCancelled, admission.isCurrent else {
                let authorizationChanged = !admission.isCurrent
                if authorizationChanged { recordAdmissionFailure(stage: .completed) }
                invalidate()
                if authorizationChanged { issue = .authorization }
                return
            }
            if let enrollmentFailure {
                issue = .enrollment(enrollmentFailure)
            } else if imports.unattributedFailure != nil {
                issue = .catalog
            }
        } catch {
            guard revision == request else { return }
            if (Task.isCancelled || error is CancellationError), admission.isCurrent { return }
            let failure: Issue = admission.isCurrent ? .catalog : .authorization
            if failure == .authorization { recordAdmissionFailure(stage: .error) }
            invalidate()
            issue = failure
        }
    }

    private func recordAdmissionFailure(stage: LiveTVSourceDiagnostics.Stage) {
        var flags: [LiveTVSourceDiagnostics.Flag: Bool] = [
            .hasSnapshot: admission.snapshot != nil, .authorized: admission.presentationIsAuthorized()
        ]
        let state: String
        do {
            if let current = try admission.authority() {
                flags[.present] = true
                flags[.profileMatches] = current.authorization.profileID == admission.profileID
                flags[.sameConfiguration] = current.configuration == admission.snapshot?.configuration
                flags[.sameAuthority] = current.authorization == admission.snapshot?.authorization
                state = "authorityPresent=true profileMatches=\(current.authorization.profileID == admission.profileID)"
                    + " configurationMatches=\(current.configuration == admission.snapshot?.configuration)"
                    + " authorizationMatches=\(current.authorization == admission.snapshot?.authorization)"
            } else {
                flags[.present] = false
                state = "authorityPresent=false"
            }
        } catch {
            flags[.failed] = true
            state = "authorityReadFailed=true"
        }
        LiveTVSourceDiagnostics.shared.record(
            .sourcesRejected, identities: [.profile: admission.profileID], flags: flags,
            reason: .authorizationChanged, stage: stage
        )
        HandoffDiagnostics.emit(
            "SOURCES event=rejected stage=\(stage.rawValue) snapshotPresent=\(admission.snapshot != nil)"
            + " presentationAuthorized=\(admission.presentationIsAuthorized()) \(state)"
        )
    }

    @discardableResult
    private func clearCatalog() -> Bool {
        admission.isClearing = true
        defer { admission.isClearing = false }
        do {
            try imports.applyConfiguration(.empty, into: catalog)
            return true
        } catch {
            issue = .catalog
            return false
        }
    }
}

@MainActor
@Observable
private final class LiveTVSourcesCatalogAdmission {
    let profileID: String
    let authority: @MainActor () throws -> LiveTVSourcesCatalogAuthority?
    let presentationIsAuthorized: @MainActor () -> Bool
    var snapshot: LiveTVSourcesCatalogAuthority?
    var isClearing = false

    init(
        profileID: String,
        authority: @escaping @MainActor () throws -> LiveTVSourcesCatalogAuthority?,
        presentationIsAuthorized: @escaping @MainActor () -> Bool
    ) {
        self.profileID = profileID
        self.authority = authority
        self.presentationIsAuthorized = presentationIsAuthorized
    }

    var isCurrent: Bool {
        guard let snapshot else { return false }
        do {
            guard let current = try authority(), current.authorization.profileID == profileID else { return false }
            return current == snapshot
        } catch {
            return false
        }
    }
}
