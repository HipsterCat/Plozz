#if canImport(SwiftUI)
import CoreModels
import FeatureHomeCore
import SwiftUI

public struct MediaFolderBrowseView: View {
    private let library: MediaLibrary
    private let provider: any MediaProvider
    private let spoilerSettings: SpoilerSettings
    private let onSelect: (MediaItem) -> Void

    public init(
        library: MediaLibrary,
        provider: any MediaProvider,
        spoilerSettings: SpoilerSettings = .default,
        onSelect: @escaping (MediaItem) -> Void
    ) {
        self.library = library
        self.provider = provider
        self.spoilerSettings = spoilerSettings
        self.onSelect = onSelect
    }

    public var body: some View {
        LibraryBrowseView(
            viewModel: LibraryBrowseViewModel(
                provider: provider,
                containerID: library.id,
                containerKind: library.kind,
                sourceAccountID: library.sourceAccountID
            ),
            title: Text(library.title),
            spoilerSettings: spoilerSettings,
            onSelect: onSelect
        )
    }
}
#endif
