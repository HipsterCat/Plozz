import SwiftUI

public struct DownloadProgressButtonLabel: View {
    private let progress: Double
    private let onLight: Bool

    public init(progress: Double, onLight: Bool) {
        self.progress = progress
        self.onLight = onLight
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                progressBar
                percentage
            }
            .fixedSize(horizontal: true, vertical: true)
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle")
                    percentage
                }
                progressBar
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var percentage: some View {
        Text("\(Int((progress * 100).rounded()))%")
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    private var progressBar: some View {
        ResumeProgressCapsule(
            progress: progress,
            onLight: onLight,
            width: 54,
            height: 5,
            floorsMinimumFill: false
        )
    }
}
