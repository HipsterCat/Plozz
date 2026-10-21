#if os(iOS)
import CoreModels
import XCTest
@testable import AppShelliOS

@MainActor
final class DeviceSetupPresentationTests: XCTestCase {
    func testClosingOldOfferDoesNotDiscardNewerRequest() {
        let app = PlozziOSAppModel()
        let old = SyncPairingRendezvous(
            serviceName: "ABCD", publicKeyData: Data([1]), deviceName: "TV", deviceID: "tv", ttlSeconds: 180
        )
        var new = old
        new.publicKeyData = Data([2])
        app.pendingSyncSetupOffer = new
        app.declineSyncSetupOffer(old)
        XCTAssertEqual(app.pendingSyncSetupOffer, new)
        app.declineSyncSetupOffer(new)
        XCTAssertNil(app.pendingSyncSetupOffer)
    }
}
#endif
