import CoreModels
import CoreUI
import SwiftUI

public struct SyncDataBreakdown: View {
    private let provider: SyncStatusProvider
    @State private var inventory: SyncDataInventory?
    @State private var failed = false
    @State private var refresh = 0

    public init(provider: SyncStatusProvider) {
        self.provider = provider
    }

    public var body: some View {
        let account = provider.make().accountTag
        Group {
            #if os(tvOS)
            SettingsPanel(title: "Sync Data on This Device") {
                SyncDataBreakdownRows(inventory: inventory, failed: failed)
                Button("Refresh Breakdown") { refresh += 1 }
                    .buttonStyle(SettingsFocusButtonStyle())
            }
            #else
            SettingsSectionGroup("Sync Data on This Device") {
                SyncDataBreakdownRows(inventory: inventory, failed: failed)
                Button("Refresh Breakdown") { refresh += 1 }
            }
            #endif
        }
        .task(id: Request(account: account, refresh: refresh)) {
            inventory = nil
            failed = false
            do {
                guard let load = provider.inventory else {
                    failed = true
                    return
                }
                let result = try await load()
                guard !Task.isCancelled else { return }
                inventory = result
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
        }
    }

    private struct Request: Equatable {
        let account: String?
        let refresh: Int
    }
}

private struct SyncDataBreakdownRows: View {
    let inventory: SyncDataInventory?
    let failed: Bool

    var body: some View {
        if let inventory {
            ForEach(inventory.rows) { row in
                LabeledContent {
                    Text("\(row.recordCount) records · \(row.payloadBytes, format: .byteCount(style: .file))")
                        .monospacedDigit()
                } label: {
                    Text(row.category.title)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("cloud-sync-category-\(row.category.rawValue)")
            }
            LabeledContent("Total") {
                Text("\(inventory.recordCount) records · \(inventory.payloadBytes, format: .byteCount(style: .file))")
                    .monospacedDigit()
            }
            Text("\(inventory.pendingUploads) pending uploads · \(inventory.pendingDeletions) pending deletions")
                .font(.footnote)
            Text("\(inventory.pendingUploadBytes, format: .byteCount(style: .file)) of encoded data is pending upload.")
                .font(.footnote)
            Text("Sizes show encoded sync data, not iCloud storage usage. Counts include pending uploads and exclude pending deletions. Refresh to update this snapshot.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Plozz Channels schedules include the library items needed to keep generated channels aligned across devices. Downloaded IPTV guides are not included.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("iCloud Keychain logins and Trakt's shared sign-in records are stored separately and are not included.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if failed {
            Label("Could not load the sync breakdown. Try refreshing.", systemImage: "exclamationmark.triangle")
        } else {
            ProgressView()
        }
    }
}
