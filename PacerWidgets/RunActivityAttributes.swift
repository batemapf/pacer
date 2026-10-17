import ActivityKit
import Foundation

struct RunActivityAttributes: ActivityAttributes {
    struct Point: Codable, Hashable, Identifiable {
        var second: Int
        var pace: Int
        var segment: Int
        var id: Int { second }
    }

    struct ContentState: Codable, Hashable {
        var pace: Double?
        var usesMiles: Bool
        var paused: Bool
        var ended: Bool
        var points: [Point]

        var paceText: String {
            guard !paused, !ended, let pace, pace.isFinite, pace > 0 else { return "—" }
            let seconds = Int((pace * (usesMiles ? 1.609344 : 1)).rounded())
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        var unitText: String { usesMiles ? "/mile" : "/km" }
    }
}
