import CoreModels
import XCTest

final class MediaChapterTests: XCTestCase {
    func testNormalizationRejectsInvalidPositionsAndKeepsFirstDuplicate() {
        let chapters = MediaChapter.normalized([
            .init(start: 30, title: "  Middle \n"),
            .init(start: 0, title: " "),
            .init(start: 30, title: "Duplicate"),
            .init(start: -1), .init(start: .nan), .init(start: .infinity),
            .init(start: 60), .init(start: 61)
        ], duration: 60)
        XCTAssertEqual(chapters.map(\.start), [0, 30])
        XCTAssertNil(chapters[0].title)
        XCTAssertEqual(chapters[1].title, "Middle")
        XCTAssertEqual(Set(chapters.map(\.id)).count, chapters.count)
    }

    func testUnknownDurationDoesNotDiscardRealChaptersOrInventAny() {
        for duration in [nil, 0, -1, .nan, .infinity] as [TimeInterval?] {
            XCTAssertEqual(MediaChapter.normalized([.init(start: 20)], duration: duration).map(\.start), [20])
            XCTAssertTrue(MediaChapter.normalized([], duration: duration).isEmpty)
        }
    }

    func testCurrentChapterChangesAtExactBoundaryAndEndsAtVideoEnd() {
        let chapters = MediaChapter.normalized([.init(start: 10), .init(start: 30)], duration: 60)
        for time in [-1, 0, 9.999, 60, .nan, .infinity] {
            XCTAssertNil(MediaChapter.currentID(in: chapters, at: time, duration: 60))
        }
        XCTAssertEqual(MediaChapter.currentID(in: chapters, at: 10, duration: 60), 10)
        XCTAssertEqual(MediaChapter.currentID(in: chapters, at: 29.999, duration: 60), 10)
        XCTAssertEqual(MediaChapter.currentID(in: chapters, at: 30, duration: 60), 30)
        XCTAssertEqual(MediaChapter.currentID(in: chapters, at: 59.999, duration: 60), 30)
        XCTAssertEqual(MediaChapter.currentID(in: chapters, at: 90, duration: 0), 30)
        XCTAssertNil(MediaChapter.currentID(in: [], at: 20, duration: 60))
    }
}
