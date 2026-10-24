#if canImport(SwiftUI)
import Observation
import SwiftUI

@MainActor
@Observable
public final class LiveTVSettingsSources {
    @ObservationIgnored private let makeContent: (AnyView) -> AnyView

    public init(content: @escaping (AnyView) -> AnyView) {
        makeContent = content
    }

    public func content(preferences: AnyView) -> AnyView { makeContent(preferences) }
}
#endif
