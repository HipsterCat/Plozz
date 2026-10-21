import CoreModels
@testable import TopShelfKit
import XCTest

final class TopShelfPublisherTests: XCTestCase {
    func testDisabledSnapshotIsEmptyWithoutResolvingArtwork() async throws {
        let snapshot = await TopShelfPublisher.makeSnapshot(
            continueWatching: items("resume", count: 30), latest: items("latest", count: 30),
            settings: .init(isEnabled: false, continueWatchingItems: 20, recentlyAddedItems: 20),
            resolveArtwork: { _ in
                XCTFail("Disabled Top Shelf must not resolve artwork")
                return nil
            }
        )
        XCTAssertTrue(try XCTUnwrap(snapshot).sections.isEmpty)
    }

    @MainActor
    func testDisablingClearsWithoutHomeAndRejectsSuspendedPublicationAfterReenable() async throws {
        var saved: [TopShelfSnapshot] = []
        let publication = TopShelfPublication { saved.append($0) }
        publication.settingsDidChange(.init(isEnabled: false))
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(try XCTUnwrap(saved.last).sections.isEmpty)
        publication.settingsDidChange(.default)

        let started = expectation(description: "Old artwork suspended")
        var resume: CheckedContinuation<TopShelfSnapshot?, Never>?
        let old = Task {
            await publication.publish {
                await withCheckedContinuation {
                    resume = $0
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 5)
        publication.settingsDidChange(.init(isEnabled: false))
        XCTAssertEqual(saved.count, 2)
        XCTAssertTrue(try XCTUnwrap(saved.last).sections.isEmpty)
        publication.settingsDidChange(.default)
        await publication.publish {
            TopShelfSnapshot(sections: [.init(id: "new", title: "New", items: [])])
        }
        resume?.resume(returning: TopShelfSnapshot(sections: [.init(id: "old", title: "Old", items: [])]))
        await old.value
        XCTAssertEqual(saved.count, 3)
        XCTAssertEqual(saved.last?.sections.map(\.id), ["new"])
    }

    @MainActor
    func testNewerPublicationWinsAndCancelledPublicationCannotSave() async {
        var saved: [TopShelfSnapshot] = []
        let publication = TopShelfPublication { saved.append($0) }
        let started = expectation(description: "Old artwork suspended")
        var resume: CheckedContinuation<TopShelfSnapshot?, Never>?
        let old = Task {
            await publication.publish {
                await withCheckedContinuation {
                    resume = $0
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 5)
        await publication.publish {
            TopShelfSnapshot(sections: [.init(id: "new", title: "New", items: [])])
        }
        resume?.resume(returning: TopShelfSnapshot(sections: [.init(id: "old", title: "Old", items: [])]))
        await old.value
        let cancelled = Task {
            await publication.publish {
                withUnsafeCurrentTask { $0?.cancel() }
                return TopShelfSnapshot(sections: [])
            }
        }
        await cancelled.value
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.last?.sections.map(\.id), ["new"])
    }

    func testDefaultSnapshotHasFourItemsInEachSection() async throws {
        let snapshot = await TopShelfPublisher.makeSnapshot(
            continueWatching: items("resume", count: 30),
            latest: items("latest", count: 30),
            locale: Locale(identifier: "en_US")
        )
        let sections = try XCTUnwrap(snapshot).sections
        XCTAssertEqual(sections.map(\.id), ["continue", "latest"])
        XCTAssertEqual(sections.map(\.title), ["Continue Watching", "Recently Added"])
        XCTAssertEqual(sections.map { $0.items.count }, [4, 4])
    }

    func testIndependentLimitsPreserveOrderAndAccountIdentity() async throws {
        for (resumeCount, recentCount) in [(1, 20), (20, 1), (7, 12)] {
            let resume = items("resume", count: 30)
            let latest = items("latest", count: 30)
            let snapshot = await TopShelfPublisher.makeSnapshot(
                continueWatching: resume, latest: latest,
                settings: .init(continueWatchingItems: resumeCount, recentlyAddedItems: recentCount)
            )
            let sections = try XCTUnwrap(snapshot).sections
            XCTAssertEqual(sections[0].items.map(\.id), Array(resume.prefix(resumeCount)).map(\.id))
            XCTAssertEqual(sections[1].items.map(\.id), Array(latest.prefix(recentCount)).map(\.id))
            for item in sections.flatMap(\.items) {
                XCTAssertEqual(item.accountID, "account-\(item.id)")
                XCTAssertEqual(item.shelfIdentifier, "account-\(item.id):\(item.id)")
            }
        }
    }

    func testShortFeedsAreNotPaddedAndEmptySectionsAreOmitted() async throws {
        let short = await TopShelfPublisher.makeSnapshot(
            continueWatching: [], latest: items("latest", count: 2),
            settings: .init(continueWatchingItems: 20, recentlyAddedItems: 20)
        )
        XCTAssertEqual(try XCTUnwrap(short).sections.map(\.id), ["latest"])
        XCTAssertEqual(short?.sections.first?.items.count, 2)
        let empty = await TopShelfPublisher.makeSnapshot(continueWatching: [], latest: [])
        XCTAssertTrue(try XCTUnwrap(empty).sections.isEmpty)
    }

    func testCancelledPublishDoesNotProduceAPartialSnapshot() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await TopShelfPublisher.makeSnapshot(
                continueWatching: self.items("resume", count: 30),
                latest: self.items("latest", count: 30)
            )
        }
        let snapshot = await task.value
        XCTAssertNil(snapshot)
    }

    private func items(_ prefix: String, count: Int) -> [MediaItem] {
        (0..<count).map { index in
            let id = "\(prefix)-\(index)"
            return MediaItem(
                id: id, title: id, kind: .movie,
                posterURL: URL(string: "https://example.com/\(id).jpg"),
                sourceAccountID: "account-\(id)"
            )
        }
    }
}
