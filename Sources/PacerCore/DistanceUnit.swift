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

    public func distanceText(metres: Double) -> String {
        String(format: "%.2f %@", metres / metresPerUnit, symbol)
    }
}
