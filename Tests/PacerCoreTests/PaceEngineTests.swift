import XCTest
@testable import PacerCore

final class PaceEngineTests: XCTestCase {
    private func feed(_ engine: inout PaceEngine, speed: Double,
                      from: Int = 0, through: Int = 10, target: Double = 360) -> [PaceEngine.Cue] {
        (from...through).compactMap {
            engine.ingest(speed: speed, at: Double($0), targetPace: target)
        }
    }

    func testOnTargetPaceAndDistance() {
        var engine = PaceEngine()
        XCTAssertTrue(feed(&engine, speed: 1000 / 360).isEmpty)
        XCTAssertEqual(engine.paceSecondsPerKilometre!, 360, accuracy: 0.001)
        XCTAssertEqual(engine.distanceMetres, 1000 / 36, accuracy: 0.001)
    }

    func testDirectionsAndCooldown() {
        var slow = PaceEngine()
        XCTAssertEqual(feed(&slow, speed: 2, through: 39), [.speedUp])
        XCTAssertEqual(feed(&slow, speed: 2, from: 40, through: 40), [.speedUp])
        var fast = PaceEngine()
        XCTAssertEqual(feed(&fast, speed: 4), [.slowDown])
    }

    func testWarmupAndStationary() {
        var engine = PaceEngine()
        XCTAssertTrue(feed(&engine, speed: 0, through: 9).isEmpty)
        XCTAssertNil(engine.paceSecondsPerKilometre)
        XCTAssertEqual(engine.ingest(speed: 0, at: 10, targetPace: 360), .speedUp)
        XCTAssertNil(engine.paceSecondsPerKilometre)
    }

    func testToleranceAvoidsNudgesNearTarget() {
        for pace in [345.0, 375.0] {
            var engine = PaceEngine()
            XCTAssertTrue(feed(&engine, speed: 1000 / pace, through: 45).isEmpty)
        }
    }

    func testSingleBadReadingIsSmoothed() {
        var engine = PaceEngine()
        _ = feed(&engine, speed: 1000 / 360)
        XCTAssertNil(engine.ingest(speed: 4, at: 11, targetPace: 360))
        XCTAssertEqual(engine.paceSecondsPerKilometre!, 353, accuracy: 1)
    }

    func testOutageDoesNotAddDistanceOrUseStalePace() {
        var engine = PaceEngine()
        _ = feed(&engine, speed: 3)
        let distance = engine.distanceMetres
        XCTAssertNil(engine.ingest(speed: 3, at: 30, targetPace: 360))
        XCTAssertEqual(engine.distanceMetres, distance)
        XCTAssertNil(engine.paceSecondsPerKilometre)
        _ = feed(&engine, speed: 3, from: 31, through: 40)
        XCTAssertNotNil(engine.paceSecondsPerKilometre)
        engine.loseSignal()
        XCTAssertNil(engine.paceSecondsPerKilometre)
        XCTAssertGreaterThan(engine.distanceMetres, distance)
    }

    func testInvalidAndOutOfOrderSamplesAreIgnored() {
        var engine = PaceEngine()
        for speed in [-1.0, 9.0, .nan, .infinity] {
            XCTAssertNil(engine.ingest(speed: speed, at: 0, targetPace: 360))
        }
        _ = feed(&engine, speed: 3)
        let distance = engine.distanceMetres
        XCTAssertNil(engine.ingest(speed: 3, at: 5, targetPace: 360))
        XCTAssertNil(engine.ingest(speed: 3, at: 10.5, targetPace: 360))
        XCTAssertEqual(engine.distanceMetres, distance)
    }

    func testTargetCanChangeDuringARunWithoutRestarting() {
        var engine = PaceEngine()
        XCTAssertTrue(feed(&engine, speed: 3, target: 1000 / 3).isEmpty)
        let distance = engine.distanceMetres
        XCTAssertEqual(engine.ingest(speed: 3, at: 11, targetPace: 250), .speedUp)
        XCTAssertEqual(engine.distanceMetres, distance + 3, accuracy: 0.001)
        XCTAssertEqual(engine.paceSecondsPerKilometre!, 1000 / 3, accuracy: 0.001)
        // Another target change must respect the original 30-second cue cooldown.
        XCTAssertTrue(feed(&engine, speed: 3, from: 12, through: 40, target: 400).isEmpty)
        XCTAssertEqual(engine.ingest(speed: 3, at: 41, targetPace: 400), .slowDown)
    }
}
