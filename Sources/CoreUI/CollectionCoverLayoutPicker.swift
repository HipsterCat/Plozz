#if canImport(SwiftUI)
import CoreModels
import SwiftUI

public struct CollectionCoverLayoutPicker: View {
    @Binding private var selection: CollectionCoverLayout

    public init(selection: Binding<CollectionCoverLayout>) {
        _selection = selection
    }

    public var body: some View {
        Picker("Covers", selection: $selection) {
            ForEach(CollectionCoverLayout.allCases, id: \.self) { layout in
                Text(layout.title).tag(layout)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("collection-cover-layout")
    }
}
#endif
