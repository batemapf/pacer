import XCTest
@testable import PacerCore

final class PaceEngineTests: XCTestCase {
    private func feed(_ engine: inout PaceEngine, speed: Double,
                      from: Int = 0, through: Int = 10, target: Double = 360, coaching: Bool = true) -> [PaceEngine.Cue] {
        (from...through).compactMap {
            engine.ingest(speed: speed, at: Double($0), targetPace: target, coachingAvailable: coaching)
        }
    }

    func testConfiguredWarmUpTracksWithoutConsumingCooldown() {
        var engine = PaceEngine(warmUpEndsAt: 60)
        XCTAssertTrue(feed(&engine, speed: 2, through: 59).isEmpty)
        XCTAssertEqual(engine.distanceMetres, 118, accuracy: 0.001)
        XCTAssertEqual(engine.paceSecondsPerKilometre!, 500, accuracy: 0.001)
        XCTAssertEqual(engine.ingest(speed: 2, at: 60, targetPace: 360), .speedUpMore)
        XCTAssertTrue(feed(&engine, speed: 2, from: 61, through: 89).isEmpty)
        XCTAssertEqual(engine.ingest(speed: 2, at: 90, targetPace: 360), .speedUpMore)
    }

    func testWarmUpCompletionWaitsForSignalAndAvailableCoaching() {
        var engine = PaceEngine(warmUpEndsAt: 60)
        XCTAssertTrue(feed(&engine, speed: 3, through: 10).isEmpty)
        engine.loseSignal()
        XCTAssertTrue(feed(&engine, speed: 3, from: 60, through: 69).isEmpty)
        XCTAssertNil(engine.ingest(speed: 3, at: 70, targetPace: 360, coachingAvailable: false))
        XCTAssertEqual(engine.ingest(speed: 3, at: 71, targetPace: 360), .slowDown)
    }

    func testWarmUpStillRequiresGPSSettlingAndResetsForNewRun() {
        var engine = PaceEngine(warmUpEndsAt: 5)
        XCTAssertTrue(feed(&engine, speed: 0, through: 9).isEmpty)
        XCTAssertEqual(engine.ingest(speed: 0, at: 10, targetPace: 360), .speedUpMore)
        engine = PaceEngine(warmUpEndsAt: 60)
        XCTAssertTrue(feed(&engine, speed: 0, through: 59).isEmpty)
        XCTAssertEqual(engine.ingest(speed: 0, at: 60, targetPace: 360), .speedUpMore)
    }

    func testWarmUpReportUsesSelectedUnitAndDirection() {
        XCTAssertEqual(DistanceUnit.kilometres.paceDifferenceText(pace: 400, target: 360),
                       "You are 40 seconds per kilometre slower than your target.")
        XCTAssertEqual(DistanceUnit.miles.paceDifferenceText(pace: 320, target: 360),
                       "You are 64 seconds per mile faster than your target.")
        XCTAssertEqual(DistanceUnit.miles.paceDifferenceText(pace: 360, target: 360),
                       "You are at your target pace.")
        XCTAssertEqual(DistanceUnit.kilometres.paceDifferenceText(pace: nil, target: 360),
                       "No moving pace available. Start jogging to measure your pace.")
    }

    func testOnTargetPaceAndDistance() {
        var engine = PaceEngine()
        XCTAssertEqual(feed(&engine, speed: 1000 / 360), [.onTarget])
        XCTAssertEqual(engine.paceSecondsPerKilometre!, 360, accuracy: 0.001)
        XCTAssertEqual(engine.distanceMetres, 1000 / 36, accuracy: 0.001)
    }

    func testDirectionsAndCooldown() {
        var slow = PaceEngine()
        XCTAssertEqual(feed(&slow, speed: 2, through: 39), [.speedUpMore])
        XCTAssertEqual(feed(&slow, speed: 2, from: 40, through: 40), [.speedUpMore])
        var fast = PaceEngine()
        XCTAssertEqual(feed(&fast, speed: 4), [.slowDownMore])
    }

    func testWarmupAndStationary() {
        var engine = PaceEngine()
        XCTAssertTrue(feed(&engine, speed: 0, through: 9).isEmpty)
        XCTAssertNil(engine.paceSecondsPerKilometre)
        XCTAssertEqual(engine.ingest(speed: 0, at: 10, targetPace: 360), .speedUpMore)
        XCTAssertNil(engine.paceSecondsPerKilometre)
    }

    func testToleranceAvoidsNudgesNearTarget() {
        for pace in [345.0, 375.0] {
            var engine = PaceEngine()
            XCTAssertEqual(feed(&engine, speed: 1000 / pace, through: 45), [.onTarget])
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
        XCTAssertTrue(feed(&engine, speed: 3, target: 1000 / 3, coaching: false).isEmpty)
        let distance = engine.distanceMetres
        XCTAssertEqual(engine.ingest(speed: 3, at: 11, targetPace: 250), .speedUpMore)
        XCTAssertEqual(engine.distanceMetres, distance + 3, accuracy: 0.001)
        XCTAssertEqual(engine.paceSecondsPerKilometre!, 1000 / 3, accuracy: 0.001)
        // Another target change must respect the original 30-second cue cooldown.
        XCTAssertTrue(feed(&engine, speed: 3, from: 12, through: 40, target: 400).isEmpty)
        XCTAssertEqual(engine.ingest(speed: 3, at: 41, targetPace: 400), .slowDownMore)
    }

    func testBandsAndBoundaryDirections() {
        XCTAssertEqual(PaceEngine.Cue.classify(pace: 380, target: 360), .onTarget)
        XCTAssertEqual(PaceEngine.Cue.classify(pace: 340, target: 360), .onTarget)
        XCTAssertEqual(PaceEngine.Cue.classify(pace: 381, target: 360), .speedUp)
        XCTAssertEqual(PaceEngine.Cue.classify(pace: 420, target: 360), .speedUp)
        XCTAssertEqual(PaceEngine.Cue.classify(pace: 421, target: 360), .speedUpMore)
        XCTAssertEqual(PaceEngine.Cue.classify(pace: 339, target: 360), .slowDown)
        XCTAssertEqual(PaceEngine.Cue.classify(pace: 300, target: 360), .slowDown)
        XCTAssertEqual(PaceEngine.Cue.classify(pace: 299, target: 360), .slowDownMore)
    }

    func testPraiseIsSpacedTwoMinutesApart() {
        var engine = PaceEngine()
        XCTAssertEqual(feed(&engine, speed: 1000 / 360, through: 129), [.onTarget])
        XCTAssertEqual(engine.ingest(speed: 1000 / 360, at: 130, targetPace: 360), .onTarget)
    }

    func testGentleNudgesAreSpacedOneMinuteApart() {
        var engine = PaceEngine()
        XCTAssertEqual(feed(&engine, speed: 1000 / 400, through: 69), [.speedUp])
        XCTAssertEqual(engine.ingest(speed: 1000 / 400, at: 70, targetPace: 360), .speedUp)
    }

    func testWorseningPaceShortensWaitWithoutBreakingMinimum() {
        var engine = PaceEngine()
        XCTAssertEqual(feed(&engine, speed: 1000 / 360), [.onTarget])
        // Change target, so the same stable speed is now far too slow.
        XCTAssertTrue(feed(&engine, speed: 1000 / 360, from: 11, through: 39, target: 240).isEmpty)
        XCTAssertEqual(engine.ingest(speed: 1000 / 360, at: 40, targetPace: 240), .speedUpMore)
        // Returning to target should reduce chatter again.
        XCTAssertTrue(feed(&engine, speed: 1000 / 360, from: 41, through: 159).isEmpty)
        XCTAssertEqual(engine.ingest(speed: 1000 / 360, at: 160, targetPace: 360), .onTarget)
    }

    func testMutedCoachingDoesNotConsumeTheCooldown() {
        var engine = PaceEngine()
        XCTAssertTrue(feed(&engine, speed: 2, through: 30, coaching: false).isEmpty)
        XCTAssertEqual(engine.ingest(speed: 2, at: 31, targetPace: 360), .speedUpMore)
    }
}
