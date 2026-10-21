#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct ProfileNameLabel: View {
    private let profile: Profile

    public init(profile: Profile) {
        self.profile = profile
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(profile.name)
            if profile.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.name)
        .accessibilityValue(profile.isLocked ? Text(ProfileLockCopy.title) : Text(verbatim: ""))
    }
}
#endif
