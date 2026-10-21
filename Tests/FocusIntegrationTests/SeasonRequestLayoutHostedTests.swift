#if os(tvOS)
import CoreModels
import CoreUI
import SwiftUI
import UIKit
import XCTest
@testable import FeatureHome

@MainActor
final class SeasonRequestLayoutHostedTests: XCTestCase {
    func testNativeDetailRequestMenuFitsBesideTrailerAndWatchlist() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let availability = MediaRequestAvailability(status: .processing, seasons: [
            .init(number: 1, title: "Season 1", status: .processing,
                  premiereDate: MediaItem.calendarDayReleaseDate(from: "2099-10-20"))
        ])
        let presentation = SeasonRequestPresentation(availability: availability)
        let bounds = RequestActionBounds()
        let row = HStack(spacing: 24) {
            SeasonRequestMenu(
                availability: availability, requestAllTitle: "Request All Seasons", onRequest: { _ in }
            ) { Label(presentation.title, systemImage: presentation.systemImage) }
                .menuStyle(.button)
                .modifier(HeroActionButtonStyle(prominent: false))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("actions")) } action: { bounds.request = $0 }
            Button {} label: { Label("Trailer", systemImage: "film.fill") }
                .modifier(HeroActionButtonStyle(prominent: false))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("actions")) } action: { bounds.trailer = $0 }
            Button {} label: { Image(systemName: "bookmark") }
                .modifier(HeroActionButtonStyle(prominent: false, circular: true))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("actions")) } action: { bounds.watchlist = $0 }
        }
        .fixedSize()
        .frame(width: 1_280, alignment: .leading)
        .coordinateSpace(name: "actions")
        .padding(60)
        .background(.black)
        .environment(\.locale, Locale(identifier: "en"))
        .preferredColorScheme(.dark)
        let host = UIHostingController(rootView: row)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        window.rootViewController = host
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        XCTAssertGreaterThan(bounds.request.width, 400)
        XCTAssertGreaterThanOrEqual(bounds.trailer.minX, bounds.request.maxX + 23)
        XCTAssertGreaterThanOrEqual(bounds.watchlist.minX, bounds.trailer.maxX + 23)
        XCTAssertLessThanOrEqual(bounds.watchlist.maxX, 1_280)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "tv-detail-native-release-wait-menu"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class RequestActionBounds {
    var request = CGRect.zero
    var trailer = CGRect.zero
    var watchlist = CGRect.zero
}
#endif
