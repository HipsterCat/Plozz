import CoreUI
import FeatureSettings
import SwiftUI

struct SyncErasureRemoteFixture: View {
    @State private var count = 0
    @State private var recovering = false
    @State private var showReview = false

    var body: some View {
        NavigationStack {
            VStack {
                Text(verbatim: "Erasures: \(count)").accessibilityIdentifier("fixture-erasure-count")
                Button("Review Erasure") { showReview = true }
            }
        }
        .plozzSheet(isPresented: $showReview) {
            SyncEraseDataView(
                profileID: "fixture",
                isAllowed: !ProcessInfo.processInfo.arguments.contains("--sync-erasure-denied"),
                status: SyncStatusProvider {
                    .init(summary: "Off", isSyncing: false, isRecovering: recovering)
                },
                erase: { count += 1; recovering = true }
            )
        }
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.themePalette, .dark)
    }
}
