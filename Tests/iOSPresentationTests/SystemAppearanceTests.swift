#if os(iOS)
@testable import AppShelliOS
import CoreModels
import CoreUI
import Observation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SystemAppearanceTests: XCTestCase {
    func testSystemFollowsDeviceAndExplicitThemesRemainPinnedWithSheetOpen() async throws {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let originalStyle = scene.traitOverrides.contains(UITraitUserInterfaceStyle.self)
            ? scene.traitOverrides.userInterfaceStyle : nil
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let state = AppearanceState()
        window.rootViewController = UIHostingController(rootView: AppearanceFixture(state: state))
        defer {
            window.isHidden = true
            window.rootViewController = nil
            if let originalStyle {
                scene.traitOverrides.userInterfaceStyle = originalStyle
            } else {
                scene.traitOverrides.remove(UITraitUserInterfaceStyle.self)
            }
            previous?.makeKeyAndVisible()
        }
        scene.traitOverrides.userInterfaceStyle = .light
        window.makeKeyAndVisible()
        try await waitUntil { state.rootScheme == .light && state.rootPalette == .light }
        XCTAssertEqual(window.overrideUserInterfaceStyle, .unspecified)

        scene.traitOverrides.userInterfaceStyle = .dark
        try await waitUntil { state.rootScheme == .dark && state.rootPalette == .dark }
        state.showSheet = true
        try await waitUntil { state.sheetScheme == .dark }
        state.path = [1]
        try await waitUntil { state.destinationIdentity != nil }
        let identity = state.destinationIdentity

        for theme in [AppTheme.system, .light, .dark, .pureBlack, .system] {
            state.theme = theme
            for style in [UIUserInterfaceStyle.light, .dark, .light] {
                scene.traitOverrides.userInterfaceStyle = style
                let scheme = theme.preferredColorScheme ?? (style == .light ? .light : .dark)
                let palette = ThemePalette.palette(for: theme, systemColorScheme: scheme)
                let expectedStyle: UIUserInterfaceStyle = theme.preferredColorScheme.map {
                    $0 == .light ? .light : .dark
                } ?? .unspecified
                try await waitUntil {
                    state.rootScheme == scheme && state.rootPalette == palette
                        && state.sheetScheme == scheme && state.sheetPalette == palette
                        && window.overrideUserInterfaceStyle == expectedStyle
                        && window.traitCollection.userInterfaceStyle == (scheme == .light ? .light : .dark)
                }
                XCTAssertEqual(window.overrideUserInterfaceStyle, expectedStyle)
                XCTAssertEqual(window.traitCollection.userInterfaceStyle, scheme == .light ? .light : .dark)
                XCTAssertEqual(state.path, [1], "Changing appearance must not reset sheet navigation.")
                XCTAssertEqual(state.destinationIdentity, identity, "Keep the pushed view alive.")
            }
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Appearance must update without relaunching or dismissing the sheet.")
    }
}

@MainActor
@Observable
private final class AppearanceState {
    var theme = AppTheme.system
    var showSheet = false
    var path: [Int] = []
    var rootScheme: ColorScheme?
    var rootPalette: ThemePalette?
    var sheetScheme: ColorScheme?
    var sheetPalette: ThemePalette?
    var destinationIdentity: UUID?
}

private struct AppearanceFixture: View {
    @Environment(\.colorScheme) private var systemScheme
    @Bindable var state: AppearanceState

    private var palette: ThemePalette {
        ThemePalette.palette(for: state.theme, systemColorScheme: systemScheme)
    }

    var body: some View {
        AppearanceProbe(state: state, isSheet: false)
            .plozzSheet(isPresented: $state.showSheet) {
                NavigationStack(path: $state.path) {
                    Text(verbatim: "Settings")
                        .navigationDestination(for: Int.self) { _ in
                            AppearanceDestination(state: state)
                        }
                }
                .background(AppearanceProbe(state: state, isSheet: true))
            }
            .environment(\.colorScheme, palette.isLight ? .light : .dark)
            .environment(\.themePalette, palette)
            .syncsWindowInterfaceStyle(state.theme.preferredColorScheme)
    }
}

private struct AppearanceProbe: View {
    let state: AppearanceState
    let isSheet: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.themePalette) private var palette

    var body: some View {
        Color.clear
            .onChange(of: scheme, initial: true) { _, value in
                if isSheet { state.sheetScheme = value } else { state.rootScheme = value }
            }
            .onChange(of: palette, initial: true) { _, value in
                if isSheet { state.sheetPalette = value } else { state.rootPalette = value }
            }
    }
}

private struct AppearanceDestination: View {
    let state: AppearanceState
    @State private var identity = UUID()

    var body: some View {
        Text(verbatim: "Appearance")
            .onAppear { state.destinationIdentity = identity }
    }
}
#endif
