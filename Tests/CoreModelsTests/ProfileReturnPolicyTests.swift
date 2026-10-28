import XCTest
@testable import CoreModels

final class ProfileReturnPolicyTests: XCTestCase {
    func testAutomaticDefaultsPrioritizeAnyLocalOrPlexPIN() throws {
        let first = Profile(id: "first", name: "First")
        var second = Profile(id: "second", name: "Second")
        XCTAssertEqual(ProfileReturnPolicy.automaticPolicy(for: [first]), .never)
        XCTAssertEqual(ProfileReturnPolicy.automaticPolicy(for: [first, second]), .fiveMinutes)
        second.lock = try XCTUnwrap(ProfileLock.make(pin: "1234", iterations: 1))
        XCTAssertEqual(ProfileReturnPolicy.automaticPolicy(for: [second]), .immediately)
        XCTAssertEqual(ProfileReturnPolicy.automaticPolicy(for: [first, second]), .immediately)
        second.lock = nil
        second = second.settingHomeUserBinding(
            .init(homeUserID: "parent", name: "Parent", requiresPIN: true),
            forPlexAccount: "plex"
        )
        XCTAssertEqual(ProfileReturnPolicy.automaticPolicy(for: [first, second]), .immediately)
        XCTAssertEqual(ProfileReturnPolicy.automatic.delay(for: [first, second], automaticallySignIn: false), 0)
    }

    func testExplicitChoiceWinsOverHouseholdDefaultsAndAutomaticSignInWinsOverEveryChoice() throws {
        var locked = Profile(id: "locked", name: "Locked")
        locked.lock = try XCTUnwrap(ProfileLock.make(pin: "1234", iterations: 1))
        let expected: [(ProfileReturnPolicy, TimeInterval?)] = [
            (.automatic, 0), (.immediately, 0), (.oneMinute, 60), (.fiveMinutes, 300),
            (.fifteenMinutes, 900), (.thirtyMinutes, 1_800), (.never, nil)
        ]
        XCTAssertEqual(expected.count, ProfileReturnPolicy.allCases.count)
        for (policy, delay) in expected {
            XCTAssertEqual(policy.delay(for: [locked], automaticallySignIn: false), delay)
            XCTAssertNil(policy.delay(for: [locked], automaticallySignIn: true))
        }
    }

    func testDeviceChoicePersistsWithoutFreezingAutomaticDefaults() throws {
        let suite = "ProfileReturnPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProfileReturnPolicyStore(defaults: defaults)
        XCTAssertEqual(store.load(), .automatic)
        for policy in ProfileReturnPolicy.allCases {
            store.save(policy)
            XCTAssertEqual(ProfileReturnPolicyStore(defaults: defaults).load(), policy)
        }
        store.save(.automatic)
        let first = Profile(id: "first", name: "First")
        let second = Profile(id: "second", name: "Second")
        XCTAssertNil(store.load().delay(for: [first], automaticallySignIn: false))
        XCTAssertEqual(store.load().delay(for: [first, second], automaticallySignIn: false), 300)
        defaults.set("invalid-policy", forKey: ProfileReturnPolicyStore.storageKey)
        XCTAssertEqual(store.load(), .automatic)
    }
}
