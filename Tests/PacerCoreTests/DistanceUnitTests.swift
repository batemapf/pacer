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
        let cues = (0...45).compactMap {
            engine.ingest(speed: 1609.344 / 600, at: Double($0), targetPace: target)
        }
        XCTAssertEqual(cues, [.onTarget])
        XCTAssertEqual(DistanceUnit.miles.paceText(secondsPerKilometre: engine.paceSecondsPerKilometre), "10:00")
    }

    func testPaceConversionPreservesPhysicalTarget() {
        for pace in [240.0, 360.0, 720.0] {
            for unit in DistanceUnit.allCases {
                let displayed = unit.displayedPace(secondsPerKilometre: pace)
                XCTAssertEqual(unit.secondsPerKilometre(displayedPace: displayed), pace, accuracy: 0.000001)
            }
        }
    }

    func testTargetRangesAndAllStepsAreRoundAndWithinPhysicalLimits() {
        XCTAssertEqual(DistanceUnit.kilometres.targetRange, 240...720)
        XCTAssertEqual(DistanceUnit.miles.targetRange, 390...1155)
        for unit in DistanceUnit.allCases {
            for seconds in stride(from: unit.targetRange.lowerBound,
                                  through: unit.targetRange.upperBound, by: 15) {
                let target = unit.secondsPerKilometre(displayedPace: seconds)
                XCTAssertTrue((240...720).contains(target))
                XCTAssertEqual(unit.roundedTarget(displayedPace: unit.displayedPace(secondsPerKilometre: target)),
                               seconds, accuracy: 0.000001)
            }
        }
    }

    func testConvertedTargetsSnapToNearestStepAndClampAtBounds() {
        let unit = DistanceUnit.miles
        let converted = unit.displayedPace(secondsPerKilometre: 566)
        XCTAssertEqual(unit.paceText(secondsPerKilometre: 566), "15:11")
        let rounded = unit.roundedTarget(displayedPace: converted)
        XCTAssertEqual(rounded, 915)
        XCTAssertEqual(unit.paceText(secondsPerKilometre: unit.secondsPerKilometre(displayedPace: rounded)), "15:15")
        XCTAssertEqual(unit.roundedTarget(displayedPace: unit.displayedPace(secondsPerKilometre: 360)), 585)
        XCTAssertEqual(unit.roundedTarget(displayedPace: unit.displayedPace(secondsPerKilometre: 240)), 390)
        XCTAssertEqual(unit.roundedTarget(displayedPace: unit.displayedPace(secondsPerKilometre: 720)), 1155)
        XCTAssertEqual(DistanceUnit.kilometres.roundedTarget(displayedPace: 363.5), 360)
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
