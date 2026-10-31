import Foundation
import XCTest
@testable import PacerCore

final class RunHistoryTests: XCTestCase {
    func testHistorySurvivesReloadWithGraphAndNewestFirst() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        XCTAssertTrue(try RunHistory.load(from: file).isEmpty)
        let older = SavedRun(id: UUID(), date: Date(timeIntervalSince1970: 100),
                             elapsedSeconds: 300, distanceMetres: 1000, samples: [])
        let newer = SavedRun(id: UUID(), date: Date(timeIntervalSince1970: 200),
                             elapsedSeconds: 1200, distanceMetres: 2000,
                             samples: [PaceSample(id: 0, elapsedSeconds: 10,
                                                  secondsPerKilometre: 600, segment: 2, isWarmUp: true)])
        try RunHistory.save([older, newer], to: file)
        let loaded = try RunHistory.load(from: file)
        XCTAssertEqual(loaded.map(\.id), [newer.id, older.id])
        XCTAssertEqual(loaded[0].samples[0].segment, 2)
        XCTAssertTrue(loaded[0].samples[0].isWarmUp)
        XCTAssertEqual(loaded[0].samples[0].secondsPerKilometre, 600)
        XCTAssertEqual(loaded[0].elapsedSeconds, 1200)
        XCTAssertEqual(loaded[0].averagePace, 600)
        let pace = RunHistory.averagePace(seconds: loaded.reduce(0) { $0 + $1.elapsedSeconds },
                                         metres: loaded.reduce(0) { $0 + $1.distanceMetres })
        XCTAssertEqual(pace, 500) // Distance-weighted, rather than the mean of 300 and 600.
    }

    func testUnavailablePaceAndUnreadableHistory() throws {
        XCTAssertNil(RunHistory.averagePace(seconds: 20, metres: 0))
        XCTAssertNil(RunHistory.averagePace(seconds: 0, metres: 10))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("invalid history".utf8).write(to: file)
        XCTAssertThrowsError(try RunHistory.load(from: file))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "invalid history")
    }
}
