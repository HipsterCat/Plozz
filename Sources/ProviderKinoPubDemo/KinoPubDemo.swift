import CoreModels
import Foundation
import os

/// Entry point for the kino.pub look-and-feel demo.
///
/// On this branch the demo is the **default** for Debug builds, because a build
/// launched from the Home screen of a real Apple TV or iPhone has no launch
/// environment to read — tapping an icon is how it will actually be looked at.
/// Set `PLOZZ_KINOPUB_DEMO=0` to run the same build as ordinary Plozz.
///
/// Release builds never enable it.
public enum KinoPubDemo {
    /// The one account the demo runs as. Declared here so the provider can key
    /// its mapping on it without importing the store that hands it out.
    public static let accountID = "kinopub-demo"

    public static var isEnabled: Bool {
        #if DEBUG
            ProcessInfo.processInfo.environment["PLOZZ_KINOPUB_DEMO"] != "0"
        #else
            false
        #endif
    }

    /// Points the managed provider kinds at the offline catalogue.
    ///
    /// Registered under the existing kinds on purpose: adding a `ProviderKind`
    /// case would force every exhaustive switch in the app to grow a branch for
    /// a provider that only exists in a demo build.
    public static func install(into registry: ProviderRegistry) {
        for kind in [ProviderKind.jellyfin, .emby, .plex] {
            registry.register(kind) { context in
                KinoPubDemoProvider(session: context.session, accountID: context.accountID)
            }
        }
    }

    public static func makeRegistry() -> ProviderRegistry {
        let registry = ProviderRegistry()
        install(into: registry)
        return registry
    }

    /// Walks the synthesised season/episode graph and prints what it found.
    ///
    /// The package's test scheme cannot be run on this machine (the full graph
    /// build wedges on unrelated modules), and a tvOS simulator takes no remote
    /// input from the command line — so this is how the graph gets checked
    /// against the real code path. `PLOZZ_KINOPUB_DEMO_SELFCHECK=1`.
    private static let log = Logger(subsystem: "com.thatcube.Plozz", category: "kinopub-demo")

    public static func runSelfCheckIfRequested(session: UserSession) async {
        #if DEBUG
            guard ProcessInfo.processInfo.environment["PLOZZ_KINOPUB_DEMO_SELFCHECK"] == "1"
            else { return }

            let provider = KinoPubDemoProvider(session: session, accountID: accountID)
            let catalog = KinoPubDemoCatalog.bundled
            let series = catalog.items.filter { $0.mediaKind == .series }
            log.info("titles=\(catalog.items.count) series=\(series.count)")

            for raw in series.prefix(3) {
                let seasons = (try? await provider.children(of: raw.id)) ?? []
                var counts: [Int] = []
                for season in seasons {
                    counts.append(((try? await provider.children(of: season.id)) ?? []).count)
                }
                let resolved = (try? await provider.item(id: seasons.first?.id ?? "")) != nil
                log.info("\(raw.title, privacy: .public): seasons=\(seasons.count) episodes=\(counts) seasonResolvesByID=\(resolved)")
            }
        #endif
    }
}
