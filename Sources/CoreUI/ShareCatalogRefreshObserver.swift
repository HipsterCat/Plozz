#if canImport(SwiftUI)
import CoreModels
import SwiftUI

/// Observes catalog changes without subscribing the entire grid to scan ticks.
public struct ShareCatalogRefreshObserver: View {
    private let shareID: String
    private let status: ShareScanStatusModel?
    private let onRefresh: () async -> Void
    @State private var pendingChange: Date?

    public init(
        shareID: String,
        status: ShareScanStatusModel?,
        onRefresh: @escaping () async -> Void
    ) {
        self.shareID = shareID
        self.status = status
        self.onRefresh = onRefresh
    }

    public var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: status?.byShare[shareID]?.lastChangeAt) { _, change in
                if let change { pendingChange = change }
            }
            .onChange(of: status?.byShare[shareID]?.lastScanAt) { _, completion in
                // Even an unchanged scan restores the inventory proof required
                // to replace physical folders with their catalog titles.
                if let completion { pendingChange = completion }
            }
            .task(id: pendingChange) {
                guard pendingChange != nil else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await onRefresh()
            }
            .accessibilityHidden(true)
    }
}
#endif
