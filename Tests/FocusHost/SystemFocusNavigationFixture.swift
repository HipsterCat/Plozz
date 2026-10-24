import CoreModels
import PlozzCoreUI
import FeatureHomeCore
import HeroUI
import SwiftUI
import UIKit

struct SystemFocusNavigationFixture: View {
    @Namespace private var scope
    @FocusState private var heroFocused: Bool
    @State private var rows: [[MediaItem]] = []
    @State private var receded = false
    @State private var selection = ""
    @State private var featuredController = HeroTrailerController()
    @State private var featuredCoordinator = FeaturedTrailerCoordinator()

    private var featured: Bool {
        ProcessInfo.processInfo.arguments.contains("--featured-rails")
    }

    private var style: CardStyle {
        ProcessInfo.processInfo.arguments.contains("--borderless") ? .borderless : .framed
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 40) {
                        Button("Hero navigation") {}
                            .accessibilityIdentifier("navigation-hero")
                            .focused($heroFocused)
                            .prefersDefaultFocus(true, in: scope)
                        Button("Hero more info") {}
                    }
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
                    .padding(.horizontal, 80)
                    .offset(y: receded ? -40 : 0)
                    .id("hero")

                    LazyVStack(spacing: 60) {
                        ForEach(rows.indices, id: \.self) { row in
                            if featured {
                                FeaturedMediaRow(
                                    title: Text("Row \(row)"), items: rows[row],
                                    scope: ObjectIdentifier(featuredController),
                                    coordinator: featuredCoordinator, controller: featuredController,
                                    settings: .default, resolver: { _ in nil }, isActive: true,
                                    onSeeAll: {}, onSelect: { selection = $0.title }
                                )
                            } else {
                                MediaRowView(
                                    title: Text(row == 0 ? "Continue Watching" : "Row \(row)"),
                                    items: rows[row], style: .landscape,
                                    playsOnSelect: row == 0
                                ) { selection = $0.title }
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
                .focusScope(scope)
            }
            .scrollClipDisabled()
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 120 } action: { _, value in
                withAnimation(.smooth(duration: 0.9)) { receded = value }
            }
            .onChange(of: heroFocused) { _, value in
                if value {
                    withAnimation(.smooth(duration: 0.9)) {
                        receded = false
                        proxy.scrollTo("hero", anchor: .top)
                    }
                }
            }
        }
        .environment(\.plozzCardFocusStyle, .system)
        .environment(\.plozzCardStyle, style)
        .environment(\.plozzNavigationContentInset, featured ? 64 : 0)
        .environment(\.plozzPinnedSidebarActive, featured)
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing) {
                Text(rows.isEmpty ? "Loading navigation fixture" : "Navigation fixture ready")
                    .accessibilityIdentifier("navigation-fixture-status")
                if featured {
                    Text("Preview candidate: \(featuredCandidateTitle)")
                        .accessibilityIdentifier("featured-preview-status")
                }
                if !selection.isEmpty {
                    Text("Selected \(selection)")
                }
            }
            .font(.caption2)
            .allowsHitTesting(false)
        }
        .task { await loadRows() }
        .onDisappear { featuredCoordinator.stop() }
    }

    private var featuredCandidateTitle: String {
        rows.joined().first { $0.stablePresentationID == featuredCoordinator.activeItemID }?.title ?? "None"
    }

    @MainActor
    private func loadRows() async {
        guard rows.isEmpty else { return }
        let store = MetadataProviderSettingsStore()
        var settings = store.load()
        settings.preferOnlineArtwork = false
        store.save(settings)
        let bright = ProcessInfo.processInfo.arguments.contains("--white-artwork")
        let url = URL(string: "https://navigation-fixture.example.test/\(bright ? "white" : "blue").png")!
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180)).image {
            (bright ? UIColor.white : .systemBlue).setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        }
        let data = image.pngData()!
        guard let cache = ArtworkSession.shared.configuration.urlCache else {
            preconditionFailure("The navigation fixture requires its isolated artwork cache.")
        }
        for variant in ArtworkImageVariant.allCases {
            let requestURL = variant.requestURL(for: url)
            let response = HTTPURLResponse(
                url: requestURL, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "image/png", "Cache-Control": "max-age=3600"]
            )!
            cache.storeCachedResponse(
                CachedURLResponse(response: response, data: data), for: URLRequest(url: requestURL)
            )
            guard await ArtworkImageCache.shared.image(for: url, variant: variant) != nil else {
                preconditionFailure("The navigation fixture artwork did not decode.")
            }
        }
        rows = (0..<3).map { row in
            (0..<8).map { index in
                MediaItem(
                    id: "navigation-\(row)-\(index)", title: "Row \(row) Item \(index)",
                    kind: .movie, posterURL: url, backdropURL: url, allowsTitleBasedMetadataMatching: false
                )
            }
        }
    }
}
