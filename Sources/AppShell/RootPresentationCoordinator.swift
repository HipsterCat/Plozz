import Observation

/// One native presenter. Pending requests cannot replace its current owner.
@MainActor
@Observable
final class RootPresentationCoordinator {
    enum Destination: Hashable {
        case accessGate, serverIdentity, profileLock, introduction, releaseNotes
        case profileAppearance, sendSetup, receiveSetup, syncErasure, serverAddresses, newServer
    }

    private(set) var active: Destination?
    private(set) var isPresented = false
    private(set) var wasDismissedByUser = false

    func update(_ requests: [Destination]) {
        if let active {
            if !requests.contains(active), isPresented {
                isPresented = false
            }
        } else if let next = requests.first {
            active = next
            isPresented = true
            wasDismissedByUser = false
        }
    }

    func dismiss() {
        guard isPresented else { return }
        wasDismissedByUser = true
        isPresented = false
    }

    func didDismiss() {
        active = nil
    }
}
