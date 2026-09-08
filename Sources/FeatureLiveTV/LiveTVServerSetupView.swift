#if DEBUG
import CoreModels
import CoreUI
import FeatureLiveTVCore
import SwiftUI

struct LiveTVServerSetupView: View {
    let sources: LiveTVSourceManagementModel
    let choices: [LiveTVServerChoice]
    let connectServer: (() -> Void)?
    @State private var probe: LiveTVServerProbeModel
    @State private var saveFailed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    init(
        sources: LiveTVSourceManagementModel,
        choices: [LiveTVServerChoice],
        resolver: LiveTVServerProviderResolver?,
        connectServer: (() -> Void)? = nil
    ) {
        self.sources = sources
        self.choices = choices
        self.connectServer = connectServer
        _probe = State(initialValue: LiveTVServerProbeModel(resolver: resolver))
    }

    var body: some View {
        List {
            if choices.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No connected Live TV servers",
                        systemImage: "server.rack",
                        description: Text("Connect Jellyfin, Emby or Plex, and enable that account for this profile. Only this profile's accounts appear here.")
                    )
                    if let connectServer {
                        Button("Connect a server", systemImage: "plus", action: connectServer)
                    } else {
                        Text("You can connect a server in Settings.")
                    }
                }
            } else {
                Section {
                    ForEach(choices) { choice in
                        Button {
                            saveFailed = false
                            probe.beginCheck(choice)
                        } label: {
                            HStack(spacing: 20) {
                                Image(systemName: "server.rack").accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(choice.name).font(.headline)
                                    Text(choice.kind.rawValue).font(.caption)
                                    if !choice.userName.isEmpty {
                                        Text(choice.userName).font(.caption).privacySensitive()
                                    }
                                }
                                Spacer()
                                if sources.configuration.servers.contains(where: { $0.accountID == choice.id && $0.isEnabled }) {
                                    Text("Added").font(.caption)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Choose a server")
                } footer: {
                    Text("Checking reads the server's Live TV setup. It does not open a tuner or interrupt another viewer.")
                }
            }

            if let choice = probe.choice {
                Section {
                    if probe.isChecking {
                        ProgressView("Checking Live TV")
                    } else if let failure = probe.failure {
                        Label {
                            Text(failure.userDescription)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    } else if let availability = probe.availability {
                        LiveTVServerAvailabilitySummary(availability: availability)
                    }
                    if saveFailed {
                        Text("The source couldn't be saved. Your previous setup is unchanged.")
                    }
                    Button(action: {
                        if probe.isChecking {
                            probe.cancelCheck()
                        } else if probe.canAdd {
                            do {
                                try sources.addServer(probe.checkedChoice())
                                dismiss()
                            } catch {
                                saveFailed = true
                            }
                        } else {
                            saveFailed = false
                            probe.beginCheck(choice)
                        }
                    }) {
                        if probe.isChecking {
                            Text("Cancel check")
                        } else if probe.canAdd {
                            Text(probe.availability?.status == .unsupportedPlaybackMode ? "Add guide only" : "Add channels")
                        } else {
                            Text("Check again")
                        }
                    }
                } header: {
                    Text(choice.name)
                }
            }

            if !choices.isEmpty, let connectServer {
                Section {
                    Button("Connect another server", systemImage: "plus", action: connectServer)
                }
            }
        }
        #if os(iOS)
        .settingsPageSurface()
        #else
        .listStyle(.plain)
        .background { SettingsPageBackground() }
        #endif
        .navigationTitle("Media server")
        .task(id: probe.pendingRequest) {
            if let request = probe.pendingRequest { await probe.perform(request) }
        }
        .onDisappear { probe.cancelCheck() }
    }
}

struct LiveTVServerAvailabilitySummary: View {
    let availability: ServerLiveTVAvailability
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(palette.secondaryText)
            if availability.hasChannels {
                Text("\(availability.channelCount) channels").font(.caption)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var title: LocalizedStringResource {
        switch availability.status {
        case .available:
            availability.hasChannels ? "Your channels are ready" : "No channels returned"
        case .notConfigured: "Live TV isn't set up on this server"
        case .noChannels: "No channels returned"
        case .permissionDenied: "Live TV access isn't allowed"
        case .serviceUnavailable: "The Live TV service is unavailable"
        case .unsupportedAPI: "This Live TV API isn't supported"
        case .unsupportedPlaybackMode: "Guide available, playback not supported"
        }
    }

    private var detail: LocalizedStringResource {
        switch availability.status {
        case .available:
            "Add this source alongside your other channels. Browsing also works when the server has no guide listings."
        case .notConfigured:
            "Set up Live TV in the server's web dashboard, then check again. Tuner and subscription requirements depend on the server."
        case .noChannels:
            "Check the server's Live TV setup and this account's channel permissions, then try again."
        case .permissionDenied:
            "Ask the server administrator to allow Live TV for this account. Plozz won't use another user's credentials."
        case .serviceUnavailable:
            "Check that the server and its Live TV service are online, then try again."
        case .unsupportedAPI:
            "Plozz can't read this server's Live TV interface. You can add a separate IPTV playlist instead."
        case .unsupportedPlaybackMode:
            "You can browse this server's channels and guide, but Plozz can't play this tuner mode yet."
        }
    }
}
#endif
