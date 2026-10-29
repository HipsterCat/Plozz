import CoreModels
import Foundation

/// Publishes only the newest discovery in the caller's current authorization scope.
@MainActor
public final class NavigationLibraryDiscovery {
    private var generation = UUID()

    public init() {}

    public func refresh(
        from accounts: [ResolvedAccount],
        expectedAccountIDs: Set<String> = [],
        navigation: NavigationStyleSettingsModel,
        isCurrent: () -> Bool
    ) async -> HomeAggregator.LibraryDiscovery? {
        let request = UUID()
        generation = request
        await Task.yield()
        guard !Task.isCancelled, request == generation, isCurrent() else { return nil }
        let discovery = await HomeAggregator().libraryDiscovery(
            from: accounts, expectedAccountIDs: expectedAccountIDs
        )
        guard !Task.isCancelled, request == generation, isCurrent() else { return nil }
        navigation.updateContentLibraries(
            discovery.libraries,
            accountIDs: Set(accounts.map(\.account.id)).union(expectedAccountIDs),
            unreachableAccountIDs: discovery.unreachableAccountIDs,
            failures: discovery.failures
        )
        return discovery
    }
}
