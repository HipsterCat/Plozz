#if canImport(SwiftUI)
import CoreModels
import SwiftUI

extension EnvironmentValues {
    @Entry public var libraryPresentationLoader: (any LibraryPresentationLoading)? = nil
}
#endif
