#if canImport(SwiftUI)
import SwiftUI

private struct SeasonRequestContextKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    /// Invalidates view-local coverage when the request server or actor changes,
    /// without coupling provider-independent feature views to Seerr.
    public var seasonRequestContextID: String {
        get { self[SeasonRequestContextKey.self] }
        set { self[SeasonRequestContextKey.self] = newValue }
    }
}
#endif
