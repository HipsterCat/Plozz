#if os(tvOS)
import UIKit

/// Controls that use horizontal input without moving focus must opt out of
/// passive page-edge navigation.
@MainActor
public protocol HorizontalNavigationInputOwning: UIFocusEnvironment {
    var ownsHorizontalNavigationInput: Bool { get }
}
#endif
