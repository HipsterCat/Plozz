import XCTest
@testable import CoreModels

final class SeerRequestIdentityTests: XCTestCase {
    private func identity(_ value: String) throws -> SeerServerIdentity {
        try XCTUnwrap(SeerServerIdentity(baseURL: XCTUnwrap(URL(string: value))))
    }

    func testEquivalentEndpointsHaveOneIdentity() throws {
        XCTAssertEqual(
            try identity("HTTPS://REQUESTS.EXAMPLE.COM:443/seerr/"),
            try identity("https://requests.example.com/seerr")
        )
        XCTAssertEqual(
            try identity("http://REQUESTS.EXAMPLE.COM:80/"),
            try identity("http://requests.example.com")
        )
    }

    func testDifferentOriginsAndProxyPathsRemainDistinct() throws {
        let original = try identity("https://requests.example.com/seerr")
        for address in [
            "http://requests.example.com/seerr",
            "https://other.example.com/seerr",
            "https://requests.example.com:5055/seerr",
            "https://requests.example.com/other",
            "https://requests.example.com/Seerr",
            "https://requests.example.com/seerr//"
        ] {
            XCTAssertNotEqual(original, try identity(address), address)
        }
        XCTAssertNotEqual(
            try identity("https://requests.example.com/a%2Fb"),
            try identity("https://requests.example.com/a/b")
        )
    }

    func testIdentityIgnoresNonRoutingFragmentAndRoundTrips() throws {
        let server = try identity("https://requests.example.com/seerr/#token")
        XCTAssertEqual(server.canonicalURL, "https://requests.example.com/seerr")
        XCTAssertEqual(
            try JSONDecoder().decode(SeerServerIdentity.self, from: JSONEncoder().encode(server)),
            server
        )
    }

    func testUnusualPathsKeepIdentityAcrossPersistence() throws {
        for address in [
            "https://requests.example.com/seerr//",
            "https://requests.example.com/seerr///",
            "https://requests.example.com/a%2Fb"
        ] {
            let server = try identity(address)
            XCTAssertEqual(
                try JSONDecoder().decode(SeerServerIdentity.self, from: JSONEncoder().encode(server)),
                server
            )
        }
    }

    func testIdentityRefusesCredentialsAndQueryRouting() throws {
        for address in [
            "https://name:password@requests.example.com/seerr",
            "https://requests.example.com/seerr?api_key=secret",
            "https://requests.example.com/seerr?tenant=other"
        ] {
            XCTAssertNil(SeerServerIdentity(baseURL: try XCTUnwrap(URL(string: address))))
        }
    }

    func testInvalidIdentityCannotBeConstructedOrDecoded() throws {
        XCTAssertNil(SeerServerIdentity(baseURL: try XCTUnwrap(URL(string: "file:///seerr"))))
        XCTAssertNil(SeerServerIdentity(baseURL: try XCTUnwrap(URL(string: "/seerr"))))
        XCTAssertNil(SeerServerIdentity(baseURL: try XCTUnwrap(URL(string: "http://host:65536"))))
        XCTAssertThrowsError(
            try JSONDecoder().decode(SeerServerIdentity.self, from: Data(#""file:///seerr""#.utf8))
        )
    }

    func testMappingMustMatchCurrentEndpoint() throws {
        let server = try identity("https://requests.example.com")
        let mapped = SeerRequestIdentity.user(id: 7, server: server)
        XCTAssertFalse(mapped.requiresRelink(to: server))
        XCTAssertTrue(mapped.requiresRelink(to: try identity("https://other.example.com")))
        XCTAssertTrue(mapped.requiresRelink(to: nil))
        XCTAssertEqual(mapped.userID, 7)
    }

    func testLegacyUserNeverBecomesAdministrator() throws {
        let server = try identity("https://requests.example.com")
        let legacy = SeerRequestIdentity.user(id: 7, server: nil)
        XCTAssertTrue(legacy.requiresRelink(to: server))
        XCTAssertTrue(legacy.requiresRelink(to: nil))
        XCTAssertEqual(legacy.userID, 7)
        XCTAssertNotEqual(legacy, .admin)
        XCTAssertFalse(SeerRequestIdentity.admin.requiresRelink(to: server))
        XCTAssertNil(SeerRequestIdentity.admin.userID)
        XCTAssertTrue(SeerRequestIdentity.user(id: 0, server: server).requiresRelink(to: server))
    }
}
