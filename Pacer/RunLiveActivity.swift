import ActivityKit
import Foundation

/// Local updates only; no push token, shared storage, or additional capability.
final class RunLiveActivity {
    private var activity: Activity<RunActivityAttributes>?
    private var pendingUpdate: Task<Void, Never>?
    private var lastUpdate = Date.distantPast

    init() {
        // A previous process cannot resume its in-memory run.
        let previous = Activity<RunActivityAttributes>.activities
        pendingUpdate = Task {
            for activity in previous { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RunActivityAttributes.ContentState(pace: nil,
            usesMiles: UserDefaults.standard.string(forKey: "distanceUnit") == "miles",
                                                       paused: false, ended: false, points: [])
        activity = try? Activity.request(attributes: RunActivityAttributes(),
            content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(10)),
            pushType: nil)
        lastUpdate = .distantPast
    }

    func update(pace: Double?, samples: [PaceSample], elapsedSeconds: Double, paused: Bool,
                force: Bool = false, ended: Bool = false) {
        guard let activity, force || Date().timeIntervalSince(lastUpdate) >= 5 else { return }
        lastUpdate = Date()
        // At most 61 points keeps ActivityKit's encoded state well below 4 KB.
        let cutoff = elapsedSeconds - 300
        var points: [RunActivityAttributes.Point] = []
        for sample in samples.reversed() {
            guard sample.elapsedSeconds >= cutoff else { break }
            let second = Int(sample.elapsedSeconds)
            if let newer = points.last, newer.second - second < 5 { continue }
            points.append(.init(second: second, pace: Int(sample.secondsPerKilometre.rounded()),
                                segment: sample.segment))
            if points.count == 61 { break }
        }
        let state = RunActivityAttributes.ContentState(pace: pace,
            usesMiles: UserDefaults.standard.string(forKey: "distanceUnit") == "miles",
            paused: paused, ended: ended, points: points.reversed())
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10))
        let previous = pendingUpdate
        pendingUpdate = Task {
            await previous?.value
            if ended { await activity.end(content, dismissalPolicy: .immediate) }
            else { await activity.update(content) }
        }
        if ended { self.activity = nil }
    }
}
