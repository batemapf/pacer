import XCTest
@testable import PacerCore

final class DistanceUnitTests: XCTestCase {
    func testPaceAndDistanceUseTheSameMileConversion() {
        XCTAssertEqual(DistanceUnit.miles.displayedPace(secondsPerKilometre: 360),
                       579.36384, accuracy: 0.000001)
        XCTAssertEqual(DistanceUnit.miles.paceText(secondsPerKilometre: 360), "9:39")
        XCTAssertEqual(DistanceUnit.kilometres.paceText(secondsPerKilometre: 360), "6:00")
        XCTAssertEqual(DistanceUnit.miles.distanceText(metres: 1609.344), "1.00 mi")
        XCTAssertEqual(DistanceUnit.kilometres.distanceText(metres: 1609.344), "1.61 km")
    }

    func testAnEnteredMileTargetBecomesTheCorrectCoachingPace() {
        let target = DistanceUnit.miles.secondsPerKilometre(displayedPace: 600)
        XCTAssertEqual(target, 372.82271534, accuracy: 0.000001)
        var engine = PaceEngine()
        for time in 0...45 {
            XCTAssertNil(engine.ingest(speed: 1609.344 / 600, at: Double(time), targetPace: target))
        }
        XCTAssertEqual(DistanceUnit.miles.paceText(secondsPerKilometre: engine.paceSecondsPerKilometre), "10:00")
    }

    func testSwitchingUnitsPreservesPhysicalTargetAndBounds() {
        for pace in [240.0, 360.0, 720.0] {
            for unit in DistanceUnit.allCases {
                let displayed = unit.displayedPace(secondsPerKilometre: pace)
                XCTAssertEqual(unit.secondsPerKilometre(displayedPace: displayed), pace, accuracy: 0.000001)
                XCTAssertTrue(unit.targetRange.contains(displayed))
            }
        }
    }

    func testFifteenSecondMileAdjustmentUsesMileUnits() {
        let oldTarget = 360.0
        let displayed = DistanceUnit.miles.displayedPace(secondsPerKilometre: oldTarget)
        let newTarget = DistanceUnit.miles.secondsPerKilometre(displayedPace: displayed + 15)
        XCTAssertEqual(newTarget - oldTarget, 15 / 1.609344, accuracy: 0.000001)
    }

    func testUnknownPaceAndMinuteRounding() {
        XCTAssertEqual(DistanceUnit.miles.paceText(secondsPerKilometre: nil), "—:—")
        XCTAssertEqual(DistanceUnit.kilometres.paceText(secondsPerKilometre: .nan), "—:—")
        XCTAssertEqual(DistanceUnit.kilometres.paceText(secondsPerKilometre: 359.6), "6:00")
    }
}
