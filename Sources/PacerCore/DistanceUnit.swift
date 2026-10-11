import Foundation

public enum DistanceUnit: String, CaseIterable, Identifiable {
    case kilometres
    case miles

    public var id: String { rawValue }
    public var symbol: String { self == .kilometres ? "km" : "mi" }
    public var paceDescription: String {
        self == .kilometres ? "minutes per kilometre" : "minutes per mile"
    }
    public var metresPerUnit: Double { self == .kilometres ? 1000 : 1609.344 }

    public func displayedPace(secondsPerKilometre: Double) -> Double {
        secondsPerKilometre * metresPerUnit / 1000
    }

    public func secondsPerKilometre(displayedPace: Double) -> Double {
        displayedPace * 1000 / metresPerUnit
    }

    /// Same physical pace limits in either unit, so toggling never changes the target.
    public var targetRange: ClosedRange<Double> {
        displayedPace(secondsPerKilometre: 240)...displayedPace(secondsPerKilometre: 720)
    }

    public func paceText(secondsPerKilometre: Double?) -> String {
        guard let seconds = secondsPerKilometre, seconds.isFinite, seconds >= 0 else {
            return "—:—"
        }
        let rounded = Int(displayedPace(secondsPerKilometre: seconds).rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }

    public func paceDifferenceText(pace: Double?, target: Double) -> String {
        guard let pace, pace.isFinite, target.isFinite else {
            return "No moving pace available. Start jogging to measure your pace."
        }
        let difference = Int(displayedPace(secondsPerKilometre: pace - target).rounded())
        if difference == 0 { return "You are at your target pace." }
        let direction = difference > 0 ? "slower" : "faster"
        let unitName = self == .kilometres ? "kilometre" : "mile"
        return "You are \(abs(difference)) seconds per \(unitName) \(direction) than your target."
    }

    public func distanceText(metres: Double) -> String {
        String(format: "%.2f %@", metres / metresPerUnit, symbol)
    }
}
