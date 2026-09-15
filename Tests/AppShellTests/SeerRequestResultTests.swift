#if canImport(SwiftUI)
import XCTest
import CoreModels
import SeerService
@testable import AppShell

final class SeerRequestResultTests: XCTestCase {
    func testStaleMappingSurfacesRelinkInsteadOfAdministratorRequest() {
        let result = seerRequestResult(.failure(.mappingNeedsRelink), actingName: nil)
        XCTAssertNil(result.status)
        XCTAssertEqual(result.failureTitle, "Relink Seerr User")
        XCTAssertEqual(
            result.failureMessage,
            .copy(SeerRequestFailure.mappingNeedsRelink.userMessage)
        )
        XCTAssertFalse(result.isSuccess)
    }
}
#endif
