import XCTest
@testable import AppShell

@MainActor
final class RootPresentationCoordinatorTests: XCTestCase {
    func testSetupKeepsOwnershipWhenEveryOtherRootPromptArrives() {
        let model = RootPresentationCoordinator()
        model.update([.sendSetup])
        let others: [RootPresentationCoordinator.Destination] = [
            .accessGate, .serverIdentity, .profileLock, .introduction, .releaseNotes,
            .profileAppearance, .receiveSetup, .syncErasure, .serverAddresses, .newServer
        ]
        for other in others {
            model.update([other, .sendSetup])
            XCTAssertEqual(model.active, .sendSetup)
            XCTAssertTrue(model.isPresented)
        }
    }

    func testUserDismissalWaitsForNativeCompletionBeforeAdvancing() {
        let model = RootPresentationCoordinator()
        model.update([.sendSetup])
        model.dismiss()
        model.update([.releaseNotes, .sendSetup])
        XCTAssertEqual(model.active, .sendSetup)
        XCTAssertFalse(model.isPresented)
        XCTAssertTrue(model.wasDismissedByUser)
        model.didDismiss()
        model.update([.releaseNotes])
        XCTAssertEqual(model.active, .releaseNotes)
        XCTAssertTrue(model.isPresented)
        XCTAssertFalse(model.wasDismissedByUser)
    }

    func testCompletedRequestIsNotTreatedAsUserCancellation() {
        let model = RootPresentationCoordinator()
        model.update([.accessGate, .sendSetup])
        model.update([.sendSetup])
        model.dismiss()
        XCTAssertFalse(model.wasDismissedByUser)
        XCTAssertEqual(model.active, .accessGate)
        model.didDismiss()
        model.update([.sendSetup])
        XCTAssertEqual(model.active, .sendSetup)
    }

    func testWithdrawnQueuedRequestNeverPresents() {
        let model = RootPresentationCoordinator()
        model.update([.releaseNotes, .newServer])
        model.update([.releaseNotes])
        model.dismiss()
        model.didDismiss()
        model.update([])
        XCTAssertNil(model.active)
        XCTAssertFalse(model.isPresented)
        model.update([.sendSetup])
        XCTAssertEqual(model.active, .sendSetup)
    }
}
