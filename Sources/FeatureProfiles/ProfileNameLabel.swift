#if canImport(SwiftUI)
import CoreModels
import PlozzCoreUI
import SwiftUI

public struct ProfileNameLabel: View {
    private let profile: Profile
    private let showsLock: Bool

    public init(profile: Profile, showsLock: Bool? = nil) {
        self.profile = profile
        self.showsLock = showsLock ?? profile.showsPINLock
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(profile.name)
            if showsLock {
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.name)
        .accessibilityValue(showsLock ? Text(ProfileLockCopy.title) : Text(verbatim: ""))
    }
}
#endif
