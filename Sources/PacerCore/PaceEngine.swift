import Foundation

/// Metres, seconds and seconds/km throughout. No location or audio dependencies.
public struct PaceEngine {
    public enum Cue: Equatable { case speedUp, slowDown }
    private struct Sample { let time: TimeInterval; let speed: Double }
    private var samples: [Sample] = []
    private var lastCueTime: TimeInterval?
    public private(set) var distanceMetres = 0.0
    public private(set) var speedMetresPerSecond: Double?

    public init() {}

    public var paceSecondsPerKilometre: Double? {
        guard let speed = speedMetresPerSecond, speed >= 0.5 else { return nil }
        return 1000 / speed
    }

    /// Call only with GPS samples that have usable accuracy.
    @discardableResult
    public mutating func ingest(speed: Double, at time: TimeInterval,
                                targetPace: Double) -> Cue? {
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
        guard lastCueTime.map({ time - $0 >= 30 }) ?? true else { return nil }
        let cue: Cue?
        if mean < 0.5 {
            cue = .speedUp
        } else {
            let pace = 1000 / mean
            cue = pace > targetPace + 20 ? .speedUp
                : pace < targetPace - 20 ? .slowDown : nil
        }
        if cue != nil { lastCueTime = time }
        return cue
    }

    /// Discard a stale pace without losing accumulated distance or cue cooldown.
    public mutating func loseSignal() {
        samples.removeAll()
        speedMetresPerSecond = nil
    }
}
