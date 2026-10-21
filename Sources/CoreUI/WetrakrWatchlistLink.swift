#if canImport(SwiftUI)
import SwiftUI
import CoreModels

public struct WetrakrWatchlistLink: View {
    private let url: URL
    @State private var showsCode = false

    public init(url: URL) { self.url = url }

    public var body: some View {
        if RuntimeFeatureFlags.buildDefault.isEnabled(.wetrakr) {
            link
        }
    }

    private var link: some View {
        #if os(tvOS)
        Button("View on WeTrakr") { showsCode = true }
            .sheet(isPresented: $showsCode) {
                VStack(spacing: 24) {
                    Text("View on WeTrakr").font(.title2)
                    QRCodeView(url.absoluteString)
                        .frame(width: 280, height: 280)
                        .padding(20)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    Text(verbatim: url.absoluteString).font(.callout)
                    Button("Done") { showsCode = false }
                }
                .padding(40)
            }
        #else
        Link("View on WeTrakr", destination: url)
        #endif
    }
}
#endif
