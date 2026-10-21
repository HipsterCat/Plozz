import CoreModels
import Foundation

@MainActor
public enum HomeLiveTVCatalogProjection {
    public static func snapshot(
        model: LiveTVPrototypeModel, imports: LiveTVPrototypeImportModel,
        profileID: String, authorization: LiveTVSourceAuthorization,
        serverAuthorizationID: String,
        serverProvider: LiveTVServerProviderResolver
    ) -> HomeLiveTVSnapshot {
        guard authorization.profileID == profileID, model.preferencesIssue == nil else { return .empty }
        let hidden = model.effectiveHiddenChannelIDs
        return .build(
            recentIDs: model.recentChannelIDs,
            favoriteIDs: model.homeFavoriteChannelIDs,
            fallbackIDs: model.channels.lazy.filter { !hidden.contains($0.id) }
                .prefix(HomeLiveTVSnapshot.maximumCandidateCount).map(\.id)
        ) { id in
            guard !hidden.contains(id), let channel = model.channel(id: id),
                  let sourceID = channel.configuredSourceID else { return nil }
            let sourceName: String
            let accountID: String?
            if let reference = imports.serverChannelReferences[id] {
                guard reference.sourceID == sourceID,
                      let source = imports.configuration.servers.first(where: {
                          $0.id == sourceID && $0.accountID == reference.accountID && $0.isEnabled
                      }),
                      let provider = serverProvider(source.accountID),
                      provider.accountID == source.accountID,
                      provider.authorizationID == reference.authorizationID else { return nil }
                sourceName = source.name
                accountID = source.accountID
            } else {
                guard channel.source == .iptv, authorization.allowsPlaylist(sourceID),
                      let source = imports.configuration.playlists.first(where: {
                          $0.id == sourceID && $0.isEnabled
                      }) else { return nil }
                sourceName = source.name
                accountID = nil
            }
            return HomeLiveTVChannel(
                route: HomeLiveTVRoute(
                    profileID: profileID, channelID: id, sourceID: sourceID, accountID: accountID,
                    sourceAuthorizationID: authorization.identity,
                    serverAuthorizationID: serverAuthorizationID
                ),
                name: channel.name, sourceName: sourceName, number: channel.number,
                logoURL: channel.logoURL, organizationMetadata: channel.organizationMetadata
            )
        }
    }

    public static func accepts(
        _ route: HomeLiveTVRoute, model: LiveTVPrototypeModel,
        imports: LiveTVPrototypeImportModel, profileID: String,
        authorization: LiveTVSourceAuthorization, serverAuthorizationID: String,
        serverProvider: LiveTVServerProviderResolver
    ) -> Bool {
        guard route.profileID == profileID, authorization.profileID == profileID,
              route.sourceAuthorizationID == authorization.identity,
              route.serverAuthorizationID == serverAuthorizationID,
              !model.effectiveHiddenChannelIDs.contains(route.channelID),
              let channel = model.channel(id: route.channelID),
              channel.configuredSourceID == route.sourceID else { return false }
        if let accountID = route.accountID {
            guard let reference = imports.serverChannelReferences[route.channelID],
                  reference.accountID == accountID, reference.sourceID == route.sourceID,
                  let provider = serverProvider(accountID), provider.accountID == accountID,
                  reference.authorizationID == provider.authorizationID else { return false }
            return imports.configuration.servers.contains {
                $0.id == route.sourceID && $0.accountID == accountID && $0.isEnabled
            }
        }
        return channel.source == .iptv && authorization.allowsPlaylist(route.sourceID)
            && imports.configuration.playlists.contains { $0.id == route.sourceID && $0.isEnabled }
    }
}
