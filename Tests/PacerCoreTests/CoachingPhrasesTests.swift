import XCTest
@testable import PacerCore

final class CoachingPhrasesTests: XCTestCase {
    func testEveryCategoryHasVarietyAndDoesNotRepeatWithinACycle() {
        var phrases = CoachingPhrases()
        XCTAssertGreaterThanOrEqual(CoachingPhrases.library.values.reduce(0) { $0 + $1.count }, 100)
        for cue in PaceEngine.Cue.allCases {
            let library = CoachingPhrases.library[cue]!
            XCTAssertGreaterThanOrEqual(library.count, 15)
            XCTAssertEqual(Set(library).count, library.count)
            let cycle = (0..<library.count).map { _ in phrases.next(for: cue) }
            XCTAssertEqual(Set(cycle), Set(library))
            XCTAssertNotEqual(phrases.next(for: cue), cycle.last)
        }
    }

    func testCoachingNeverSpeaksMoreOftenThanEveryThirtySeconds() {
        for cue in PaceEngine.Cue.allCases { XCTAssertGreaterThanOrEqual(cue.interval, 30) }
    }
}
