import XCTest
@testable import CoreModels

final class AppLinksTests: XCTestCase {
    func testDiscordUsesStablePublicShortlink() {
        XCTAssertEqual(AppLinks.discord.absoluteString, "https://plozz.app/discord")
    }
}
