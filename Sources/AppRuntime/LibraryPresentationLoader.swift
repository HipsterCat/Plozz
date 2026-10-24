import CoreModels
import FeatureHomeCore

public struct LibraryPresentationLoader: LibraryPresentationLoading {
    private let settings: LibraryPresentationSettingsModel
    private let namespace: String?

    public init(settings: LibraryPresentationSettingsModel, namespace: String?) {
        self.settings = settings
        self.namespace = namespace
    }

    public func libraries(accounts: [ResolvedAccount]) async -> LibraryPresentationDiscovery {
        let discovery = await HomeAggregator().libraryDiscovery(from: accounts)
        return .init(libraries: discovery.libraries, failures: discovery.failures)
    }

    public func recommendations(
        library: AggregatedLibrary, account: ResolvedAccount
    ) async -> LibraryPresentationRecommendations {
        let model = LibraryBrowseViewModel(
            provider: account.provider, containerID: library.library.id, containerKind: library.library.kind,
            sourceAccountID: account.account.id, settingsNamespace: namespace, presentation: settings
        )
        await model.loadRecommendations()
        return .init(state: model.recommendationState, diagnostic: model.recommendationDiagnostic)
    }
}
