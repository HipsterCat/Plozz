import CoreModels
import SwiftUI

public struct LibraryCollectionLoadingView: View {
    private let progress: LibraryCollectionProgress?
    private let onRetry: () -> Void

    public init(progress: LibraryCollectionProgress?, onRetry: @escaping () -> Void) {
        self.progress = progress
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let progress {
                ProgressView(value: Double(progress.checked), total: Double(max(1, progress.total))) {
                    Text("Checking collections...")
                } currentValueLabel: {
                    Text("\(progress.checked) of \(progress.total) checked")
                }
            } else {
                Text("Collection loading was interrupted.")
                Button("Try Again", action: onRetry)
            }
        }
        .frame(maxWidth: 400)
        .accessibilityIdentifier("library-collection-loading")
    }
}
