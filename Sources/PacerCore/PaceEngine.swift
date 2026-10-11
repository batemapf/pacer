import Foundation

/// Metres, seconds and seconds/km throughout. No location or audio dependencies.
public struct PaceEngine {
    public enum Cue: CaseIterable, Hashable {
        case onTarget, speedUp, slowDown, speedUpMore, slowDownMore

        public var interval: TimeInterval {
            switch self {
            case .onTarget: return 120
            case .speedUp, .slowDown: return 60
            case .speedUpMore, .slowDownMore: return 30
            }
        }

        public static func classify(pace: Double?, target: Double) -> Cue {
            guard let pace else { return .speedUpMore }
            let difference = pace - target
            if difference > 60 { return .speedUpMore }
            if difference > 20 { return .speedUp }
            if difference < -60 { return .slowDownMore }
            if difference < -20 { return .slowDown }
            return .onTarget
        }
    }
    private struct Sample { let time: TimeInterval; let speed: Double }
    private var samples: [Sample] = []
    private var lastCueTime: TimeInterval?
    public private(set) var distanceMetres = 0.0
    public private(set) var speedMetresPerSecond: Double?

    private let warmUpEndsAt: TimeInterval?

    public init(warmUpEndsAt: TimeInterval? = nil) {
        self.warmUpEndsAt = warmUpEndsAt
    }

    public var paceSecondsPerKilometre: Double? {
        guard let speed = speedMetresPerSecond, speed >= 0.5 else { return nil }
        return 1000 / speed
    }

    /// Call only with GPS samples that have usable accuracy.
    @discardableResult
    public mutating func ingest(speed: Double, at time: TimeInterval,
                                targetPace: Double, coachingAvailable: Bool = true) -> Cue? {
        guard speed.isFinite, time.isFinite, targetPace.isFinite,
              speed >= 0, speed <= 8, targetPace > 0 else { return nil }
        if let previous = samples.last {
            let delta = time - previous.time
            guard delta >= 1 else { return nil }
            if delta <= 8 {
                distanceMetres += (previous.speed + speed) / 2 * delta
            } else {
                // Reacquire a stable estimate after an outage; never integrate the gap.
                samples.removeAll()
                speedMetresPerSecond = nil
            }
        }
        samples.append(Sample(time: time, speed: speed))
        samples.removeAll { time - $0.time > 15 }
        guard samples.count >= 3, let first = samples.first,
              time - first.time >= 10 else {
            speedMetresPerSecond = nil
            return nil
        }
        // Time-weighted mean avoids giving callback bursts extra influence.
        var distance = 0.0
        for i in 1..<samples.count {
            let a = samples[i - 1], b = samples[i]
            distance += (a.speed + b.speed) / 2 * (b.time - a.time)
        }
        let mean = distance / (time - first.time)
        speedMetresPerSecond = mean
        guard warmUpEndsAt.map({ time >= $0 }) ?? true, coachingAvailable else { return nil }
        let cue = Cue.classify(pace: paceSecondsPerKilometre, target: targetPace)
        // A worsening pace can shorten the wait, but no transition bypasses 30 seconds.
        guard lastCueTime.map({ time - $0 >= cue.interval }) ?? true else { return nil }
        lastCueTime = time
        return cue
    }

    /// Discard a stale pace without losing accumulated distance or cue cooldown.
    public mutating func loseSignal() {
        samples.removeAll()
        speedMetresPerSecond = nil
    }
}
