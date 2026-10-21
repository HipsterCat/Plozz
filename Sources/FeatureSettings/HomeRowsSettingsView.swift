#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreUI

/// The shared section editor adapts existing row feeds without changing their identities.
public struct HomeRowsSettingsView: View {
    public let libraries: [AggregatedLibrary]
    public let accounts: [ResolvedAccount]
    public let visibility: HomeLibraryVisibilityModel
    @Environment(HeroSettingsModel.self) private var hero
    @Environment(HeroBackgroundSettingsModel.self) private var heroBackground
    @Environment(CardStyleSettingsModel.self) private var cards
    @State private var inventory: HomeSectionCatalogModel
    @State private var reorderSession: HomeSectionReorderSession?
    @State private var isLifting = false
    @State private var reloadRevision = 0
    @State private var editError: AppError?

    public init(
        libraries: [AggregatedLibrary], accounts: [ResolvedAccount],
        visibility: HomeLibraryVisibilityModel
    ) {
        self.init(libraries: libraries, accounts: accounts, visibility: visibility, inventory: HomeSectionCatalogModel())
    }

    init(
        libraries: [AggregatedLibrary], accounts: [ResolvedAccount],
        visibility: HomeLibraryVisibilityModel, inventory: HomeSectionCatalogModel
    ) {
        self.libraries = libraries
        self.accounts = accounts
        self.visibility = visibility
        _inventory = State(initialValue: inventory)
    }

    private var requestID: HomeSectionCatalogModel.RequestID {
        HomeSectionCatalogModel.requestID(libraries: libraries, accounts: accounts, visibility: visibility)
    }

    private var isReordering: Bool { reorderSession != nil }

    private var currentCatalog: HomeSectionCatalog {
        inventory.currentCatalog(libraries: libraries, accounts: accounts, visibility: visibility)
    }

    public var body: some View {
        HomeEditorPage(title: Text("Customize Home")) {
            #if os(tvOS)
            HStack(spacing: SettingsFormMetrics.controlSpacing) {
                SettingsPageHeader("Customize Home")
                reorderButton
            }
            editorControls
                .padding(.vertical, SettingsFormMetrics.navigationRowSpacing)
            #elseif os(iOS)
            VStack(alignment: .leading, spacing: 12) {
                editorControls
                Divider()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home-row-preset-header")
            #endif
            HomeEditorLink {
                HomeHeroSettingsView(libraries: libraries, accounts: accounts, visibility: visibility)
                    .environment(hero)
                    .environment(heroBackground)
            } label: {
                HomeEditorRowLabel(
                    title: heroTitle, subtitle: heroSummary, titleSymbol: "pin.fill"
                )
            }
            .accessibilityIdentifier("home-section-hero")
            .disabled(isReordering)

            let catalog = reorderSession?.catalog ?? currentCatalog
            let arrangement = reorderSession?.visibility ?? visibility.visibility
            let sections = catalog.sections(in: arrangement)
            let choices = catalog.editableChoices(in: arrangement)
            if isReordering {
                let byID = Dictionary(choices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                LiftableReorderList(
                    sections: .init(enabled: sections.enabled, disabled: []),
                    disabledSectionTitle: "Hidden", disabledPlaceholder: "No hidden rows",
                    isLifting: $isLifting, allowsHiding: false,
                    onRemove: { id in
                        do {
                            try reorderSession?.remove(id, savingTo: visibility)
                            editError = nil
                        } catch { editError = (error as? AppError) ?? .invalidResponse }
                    },
                    row: { id in
                        let choice = byID[id]
                        return .init(
                            title: choice?.homeEditorTitle ?? Text("Section"),
                            symbolName: "rectangle.grid.1x2",
                            providerKind: choice?.library?.providerKind ?? choice?.serverRow?.providerKind,
                            mediaShareTransport: choice?.library?.transportKind,
                            subtitle: choice?.homeEditorSource,
                            providerMarkInSubtitle: true
                        )
                    },
                    onChange: { order in
                        do {
                            try reorderSession?.move(order.enabled, savingTo: visibility)
                            editError = nil
                        } catch { editError = (error as? AppError) ?? .invalidResponse }
                    }
                )
                .accessibilityIdentifier("home-section-reorder-list")
            } else {
                ForEach(sections.enabled, id: \.self) { id in
                    if let choice = choices.first(where: { $0.id == id }) {
                        HomeEditorLink {
                            HomeSectionSettingsView(
                                choice: choice, inventory: inventory, visibility: visibility,
                                libraries: libraries, accounts: accounts
                            )
                            .environment(cards)
                        } label: {
                            HomeSectionChoiceLabel(choice: choice)
                        }
                        .accessibilityIdentifier("home-section-\(id.presentationID)")
                        .contextMenu {
                            Button("Remove section", systemImage: "minus.circle", role: .destructive) {
                                do {
                                    try visibility.setHomeSectionVisible(false, id: id, catalog: currentCatalog)
                                    editError = nil
                                } catch { editError = (error as? AppError) ?? .invalidResponse }
                            }
                        }
                    }
                }
            }
            addSectionButton(identifier: "home-section-add-bottom")
            if editError != nil {
                InlineErrorMessage(Text("Couldn't update this section. Try again."))
            }
            HomeCatalogStatus(inventory: inventory, accounts: accounts, libraries: libraries) {
                reloadRevision += 1
            }
            .disabled(isReordering)
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SettingsPageLink {
                    addSectionDestination
                } label: {
                    Label("Add section", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .disabled(isReordering)
                .accessibilityIdentifier("home-section-add")
                reorderButton
            }
        }
        #endif
        .task(id: HomeSectionCatalogModel.loadID(
            libraries: libraries, accounts: accounts, visibility: visibility, revision: reloadRevision
        )) {
            await inventory.load(libraries: libraries, accounts: accounts, visibility: visibility)
        }
        .onChange(of: requestID) { _, _ in
            reorderSession = nil
            isLifting = false
            editError = nil
        }
    }

    private var editorControls: some View {
        #if os(tvOS)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { controls }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { controls }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        #else
        controls
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    private var controls: some View {
        Group {
            HomeRowPresetPicker(visibility: visibility)
                .id(ObjectIdentifier(visibility))
                .disabled(isReordering)
            #if os(tvOS)
            addSectionButton(identifier: "home-section-add")
            #endif
        }
    }

    private var reorderButton: some View {
        Button {
            if isReordering {
                reorderSession = nil
            } else {
                reorderSession = HomeSectionReorderSession(catalog: currentCatalog, visibility: visibility.visibility)
            }
            isLifting = false
        } label: {
            if isReordering { Text("Done").fixedSize(horizontal: false, vertical: true) }
            else { Text("Reorder").fixedSize(horizontal: false, vertical: true) }
        }
        .disabled(isLifting || (!isReordering && currentCatalog.sections(in: visibility.visibility).enabled.count < 2))
        .accessibilityIdentifier("home-section-reorder")
        #if os(tvOS)
        .plozzActionButton(role: .secondary)
        #endif
    }

    private func addSectionButton(identifier: String) -> some View {
        SettingsPageLink {
            addSectionDestination
        } label: {
            Text("Add section").fixedSize(horizontal: false, vertical: true)
        }
        .plozzActionButton(role: .secondary)
        .disabled(isReordering)
        .accessibilityIdentifier(identifier)
    }

    private var addSectionDestination: some View {
        HomeAddSectionView(
            inventory: inventory, visibility: visibility, libraries: libraries, accounts: accounts
        )
    }

    private var heroTitle: Text {
        #if os(tvOS)
        hero.settings.style == .followsFocus ? Text("Home layout: Showcase") : Text("Home layout: Hero")
        #else
        Text("Hero")
        #endif
    }

    private var heroSummary: Text? {
        #if os(tvOS)
        if hero.settings.style == .followsFocus { return nil }
        #endif
        if !hero.settings.isEnabled { return Text("Off") }
        return nil
    }
}

/// Keep the rows under the user's hands stable while optional discovery finishes.
@MainActor
struct HomeSectionReorderSession {
    let catalog: HomeSectionCatalog
    private(set) var visibility: HomeLibraryVisibility

    init(catalog: HomeSectionCatalog, visibility: HomeLibraryVisibility) {
        self.catalog = catalog
        self.visibility = visibility
    }

    mutating func move(_ order: [HomeRowID], savingTo model: HomeLibraryVisibilityModel) throws {
        let updated = try catalog.reordering(order, in: visibility)
        save(updated, to: model)
    }

    mutating func remove(_ id: HomeRowID, savingTo model: HomeLibraryVisibilityModel) throws {
        let updated = try catalog.settingVisible(false, id: id, in: visibility)
        save(updated, to: model)
    }

    private mutating func save(_ updated: HomeLibraryVisibility, to model: HomeLibraryVisibilityModel) {
        guard updated != visibility else { return }
        model.applyRows(catalog.sections(in: updated), choices: catalog.availableChoices(in: updated))
        visibility = model.visibility
    }
}
#endif
