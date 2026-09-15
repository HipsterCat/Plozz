import XCTest
@testable import FeaturePlayback

final class RemoteClickInterpreterTests: XCTestCase {
    func testControllerSnapshotCanPrecedeOrFollowNativePress() {
        XCTAssertTrue(matchesInput(pressUptime: 100, inputUnixTime: 1_000_099.98))
        XCTAssertTrue(matchesInput(pressUptime: 100, inputUnixTime: 1_000_100.08))
    }

    func testTimestampConversionAccountsForDelayedNativeDelivery() {
        XCTAssertTrue(RemoteClickInterpreter.matchesInput(
            pressUptime: 100, inputUnixTime: 1_000_100.02, nowUptime: 100.5, nowUnixTime: 1_000_100.5))
    }

    func testStaleOrInvalidControllerEventsCannotSupplyClickPosition() {
        XCTAssertFalse(matchesInput(pressUptime: 100, inputUnixTime: 1_000_099))
        XCTAssertFalse(matchesInput(pressUptime: 100, inputUnixTime: 1_000_101))
        XCTAssertFalse(matchesInput(pressUptime: 0, inputUnixTime: 0))
        XCTAssertFalse(matchesInput(pressUptime: -1, inputUnixTime: 1_000_100))
        XCTAssertFalse(matchesInput(pressUptime: .nan, inputUnixTime: 1_000_100))
        XCTAssertFalse(matchesInput(pressUptime: 100, inputUnixTime: 100))
    }

    private func matchesInput(pressUptime: Double, inputUnixTime: Double) -> Bool {
        RemoteClickInterpreter.matchesInput(
            pressUptime: pressUptime, inputUnixTime: inputUnixTime,
            nowUptime: 100, nowUnixTime: 1_000_100)
    }

    func testPhysicalEdgeClicksSkipWithoutSelecting() {
        for (x, expected) in [(-0.95 as Float, RemoteClickInterpreter.Action.skipBackward),
                               (0.99, .skipForward)] {
            var click = RemoteClickInterpreter()
            click.touchBegan()
            click.selectBegan(position: .init(x: x, y: -0.3))
            XCTAssertEqual(click.takeAction(), expected)
            XCTAssertTrue(click.suppressesPan)
        }
    }

    func testCenterAndVerticalEdgesRemainSelect() {
        for position in [
            RemoteClickInterpreter.Position(x: 0, y: 0),
            .init(x: 0.69, y: 0),
            .init(x: -0.69, y: 0),
            .init(x: 0.8, y: 0.9),
            .init(x: -0.8, y: -0.9),
            .init(x: 0.8, y: 0.8)
        ] {
            var click = RemoteClickInterpreter()
            click.selectBegan(position: position)
            XCTAssertEqual(click.takeAction(), .select)
        }
    }

    func testThresholdIsInclusiveAndConfigurable() {
        var click = RemoteClickInterpreter(edgeThreshold: 0.8)
        click.selectBegan(position: .init(x: 0.79, y: 0))
        XCTAssertEqual(click.takeAction(), .select)
        click.selectBegan(position: .init(x: -0.8, y: 0))
        XCTAssertEqual(click.takeAction(), .skipBackward)
        click.selectBegan(position: .init(x: 0.8, y: 0))
        XCTAssertEqual(click.takeAction(), .skipForward)
    }

    func testUnknownRemoteAndInvalidPositionsRemainSelect() {
        for position: RemoteClickInterpreter.Position? in [
            nil, .init(x: .nan, y: 0), .init(x: .infinity, y: 0), .init(x: 1, y: .nan)
        ] {
            var click = RemoteClickInterpreter()
            click.selectBegan(position: position)
            XCTAssertEqual(click.takeAction(), .select)
        }
    }

    func testClickSuppressesLiftMovementButNotNextSwipe() {
        var click = RemoteClickInterpreter()
        click.touchBegan()
        XCTAssertFalse(click.suppressesPan)
        click.selectBegan(position: .init(x: 1, y: 0))
        XCTAssertTrue(click.suppressesPan)
        XCTAssertEqual(click.takeAction(), .skipForward)
        XCTAssertTrue(click.suppressesPan)
        click.touchBegan()
        XCTAssertFalse(click.suppressesPan)
    }

    func testRepeatedClicksWithFingerDownEachProduceOneSkip() {
        var click = RemoteClickInterpreter()
        click.touchBegan()
        for _ in 0..<3 {
            click.selectBegan(position: .init(x: -0.95, y: -0.3))
            XCTAssertEqual(click.takeAction(), .skipBackward)
            XCTAssertTrue(click.suppressesPan)
        }
    }

    func testUnknownSelectDoesNotReusePreviousEdgePosition() {
        var click = RemoteClickInterpreter()
        click.selectBegan(position: .init(x: 1, y: 0))
        XCTAssertEqual(click.takeAction(), .skipForward)
        click.selectBegan(position: nil)
        XCTAssertEqual(click.takeAction(), .select)
    }
}
