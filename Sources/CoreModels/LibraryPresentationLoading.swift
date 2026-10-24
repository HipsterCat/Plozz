import Foundation

public struct LibraryPresentationDiscovery: Sendable {
    public let libraries: [AggregatedLibrary]
    public let failures: [String: AppError]

    public init(libraries: [AggregatedLibrary], failures: [String: AppError]) {
        self.libraries = libraries
        self.failures = failures
    }
}

public struct LibraryPresentationRecommendations: Sendable {
    public let state: LoadState<[LibrarySection]>
    public let diagnostic: LibraryLoadDiagnostic?

    public init(state: LoadState<[LibrarySection]>, diagnostic: LibraryLoadDiagnostic?) {
        self.state = state
        self.diagnostic = diagnostic
    }
}

/// Settings consumes the same library discovery and recommendation pipeline as browsing.
@MainActor
public protocol LibraryPresentationLoading: Sendable {
    func libraries(accounts: [ResolvedAccount]) async -> LibraryPresentationDiscovery
    func recommendations(
        library: AggregatedLibrary, account: ResolvedAccount
    ) async -> LibraryPresentationRecommendations
}
