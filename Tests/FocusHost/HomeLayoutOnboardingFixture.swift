import CoreModels
import CoreUI
import SwiftUI
@testable import AppShell

struct HomeLayoutOnboardingFixture: View {
    @State private var hero: HeroSettingsModel
    @State private var completed = false
    private let store: HeroSettingsStore

    init() {
        let store = HeroSettingsStore(namespace: "home-layout-onboarding-fixture")
        self.store = store
        if !ProcessInfo.processInfo.arguments.contains("--restore-home-layout") {
            var initial = HeroSettings.default
            if ProcessInfo.processInfo.arguments.contains("--selected-showcase") {
                initial.style = .followsFocus
            }
            store.save(initial)
        }
        _hero = State(initialValue: HeroSettingsModel(store: store))
    }

    var body: some View {
        Group {
            if completed {
                Text("Saved layout: \(store.load().style.rawValue)")
                    .accessibilityIdentifier("saved-home-layout")
            } else {
                SelectHomeLayoutView(hero: hero, onContinue: { completed = true })
            }
        }
        .environment(\.themePalette, .dark)
        .environment(\.colorScheme, .dark)
    }
}
