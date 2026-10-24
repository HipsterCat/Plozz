import CoreModels
import XCTest

final class LibraryChannelArtworkMoodTests: XCTestCase {
    func testAutomaticCategoryDeterminesMoodWithoutUsingTheDisplayName() {
        let cases: [(String, LibraryChannelArtworkMood)] = [
            ("v1/movies", .cinematic), ("v1/tv", .neutral), ("v1/animation", .playful),
            ("v1/kids", .playful), ("v1/family", .playful), ("v1/genre/documentary", .calm),
            ("v1/genre/nature", .calm), ("v1/genre/comedy", .playful), ("v1/genre/action", .intense),
            ("v1/genre/horror", .mysterious), ("v1/genre/science fiction", .imaginative),
            ("v1/genre/romance", .warm), ("v1/decade/1980", .warm),
            ("v1/studio/studio ghibli", .cinematic), ("v1/director/example", .cinematic)
        ]
        for (key, expected) in cases {
            for name in ["Renamed channel", "映画", "Horror", "Nature"] {
                XCTAssertEqual(
                    LibraryChannelArtworkMood(automaticKey: key, recipe: .init(name: name)), expected, key
                )
            }
        }
    }

    func testCustomGenresUseStableRulesRatherThanProviderOrder() {
        for genres in [[" ANIMATION ", "Comedy"], ["comedy", "animation"], ["Animation", "Animation"]] {
            XCTAssertEqual(
                LibraryChannelArtworkMood(automaticKey: nil, recipe: .init(genres: genres)), .playful
            )
        }
        for genres in [["Horror", "Comedy"], ["Comedy", "Horror"], ["Unrecognized category"]] {
            XCTAssertEqual(
                LibraryChannelArtworkMood(automaticKey: nil, recipe: .init(genres: genres)), .neutral
            )
        }
    }

    func testUnknownMetadataDoesNotGuessFromTheChannelName() {
        XCTAssertEqual(LibraryChannelArtworkMood(
            automaticKey: "v1/genre/unknown", recipe: .init(name: "Comedy", includesEpisodes: false)
        ), .neutral)
        XCTAssertEqual(LibraryChannelArtworkMood(
            automaticKey: nil, recipe: .init(name: "Nature")
        ), .neutral)
        XCTAssertEqual(LibraryChannelArtworkMood(
            automaticKey: nil, recipe: .init(includesEpisodes: false)
        ), .cinematic)
    }
}
