#if os(iOS)
import Observation
import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var plozziOSIsOverflowDestination = false
}

@MainActor
@Observable
final class PlozziOSOverflowNavigation {
    private(set) var destinationIndex: Int?
    @ObservationIgnored private(set) weak var navigationController: UINavigationController?

    func update(destinationIndex: Int?, navigationController: UINavigationController) {
        self.navigationController = navigationController
        self.destinationIndex = destinationIndex
    }

    func returnToMore() {
        guard destinationIndex != nil else { return }
        navigationController?.popToRootViewController(animated: true)
    }
}
#endif
