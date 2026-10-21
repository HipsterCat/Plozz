#if os(tvOS)
import CoreModels
import CoreNetworking
import FeatureHomeCore
import UIKit

final class NativeLibraryTraversalProbe: UIView {
    var snapshot: (() -> LibraryTraversalSnapshot?)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityIdentifier = "library-traversal-diagnostics"
        accessibilityLabel = accessibilityIdentifier // l10n:content — opt-in diagnostic identifier
        accessibilityTraits = .staticText
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { nil }

    override var accessibilityValue: String? { // l10n:content — opt-in JSON diagnostic payload
        get {
            guard let snapshot = snapshot?() else { return nil }
            do {
                return String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
            } catch {
                PlozzLog.app.error("Could not encode Library traversal diagnostics")
                return nil
            }
        }
        set {}
    }
}
#endif
