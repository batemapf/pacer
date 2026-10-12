import Foundation
import Combine
import CoreLocation
import AVFoundation

struct PaceSample: Identifiable {
    let id: Int
    let elapsedSeconds: Double
    let secondsPerKilometre: Double
    let segment: Int
}

final class RunTracker: NSObject, ObservableObject, CLLocationManagerDelegate, AVSpeechSynthesizerDelegate {
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var paceSecondsPerKilometre: Double? = nil
    @Published private(set) var elapsedText = "0:00"
    @Published private(set) var distanceMetres = 0.0
    @Published private(set) var paceSamples: [PaceSample] = []
    @Published private(set) var elapsedSeconds = 0.0
    @Published private(set) var status = ""
    @Published private(set) var warmUpRemainingText = ""
    @Published private(set) var warmUpReport = ""
    @Published var warmUpMinutes = min(30, max(0, UserDefaults.standard.integer(forKey: "warmUpMinutes"))) {
        didSet { UserDefaults.standard.set(warmUpMinutes, forKey: "warmUpMinutes") }
    }
    @Published var targetPaceSecondsPerKilometre = 360.0 {
        didSet {
            // Cancel a nudge for the old target. The next GPS fix uses the new target
            // while retaining distance, smoothing, and the existing cue cooldown.
            if targetPaceSecondsPerKilometre != oldValue {
                speech.stopSpeaking(at: .immediate)
            }
        }
    }
    @Published var coachingEnabled = UserDefaults.standard.object(forKey: "coachingEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(coachingEnabled, forKey: "coachingEnabled")
            if !coachingEnabled { speech.stopSpeaking(at: .immediate) }
        }
    }
    @Published var voiceIdentifier = UserDefaults.standard.string(forKey: "coachingVoiceIdentifier") ?? "" {
        didSet {
            UserDefaults.standard.set(voiceIdentifier, forKey: "coachingVoiceIdentifier")
            if voiceIdentifier != oldValue { speech.stopSpeaking(at: .immediate) }
        }
    }

    func previewVoice() {
        speech.stopSpeaking(at: .immediate)
        speak("Looking good! Keep this pace. Your future self is already bragging.")
    }

    private let location = CLLocationManager()
    private let speech = AVSpeechSynthesizer()
    private var engine = PaceEngine()
    private var phrases = CoachingPhrases()
    private var warmUpEndsAt: Date?
    private var warmUpReportPending = false
    private var warmUpSpeechPending = false
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedDuration = 0.0
    private var acceptingFixesAfter: Date?
    private var lastFix: Date?
    private var timer: Timer?
    private var pendingStart = false
    private var audioActive = false
    private var paceSegment = 0
    private var lastGraphFix: Date?

    override init() {
        super.init()
        location.delegate = self
        speech.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = kCLDistanceFilterNone
        location.pausesLocationUpdatesAutomatically = false
        location.allowsBackgroundLocationUpdates = true
        location.showsBackgroundLocationIndicator = true
    }

    func start() {
        guard !isRunning else { return }
        switch location.authorizationStatus {
        case .notDetermined:
            pendingStart = true
            location.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard location.accuracyAuthorization == .fullAccuracy else {
                status = "Enable Precise Location for Speed Up or Slow Down in Settings to measure pace."
                return
            }
            pendingStart = false
            let start = Date()
            warmUpEndsAt = warmUpMinutes > 0 ? start.addingTimeInterval(Double(warmUpMinutes * 60)) : nil
            warmUpReportPending = warmUpEndsAt != nil
            warmUpSpeechPending = warmUpEndsAt != nil
            warmUpReport = ""
            engine = PaceEngine(warmUpEndsAt: warmUpEndsAt?.timeIntervalSinceReferenceDate)
            lastFix = nil
            startedAt = start
            pausedAt = nil
            pausedDuration = 0
            acceptingFixesAfter = start
            isPaused = false
            distanceMetres = 0
            paceSamples = []
            elapsedSeconds = 0
            paceSegment = 0
            lastGraphFix = nil
            paceSecondsPerKilometre = nil
            elapsedText = "0:00"
            isRunning = true
            status = "Acquiring GPS…"
            tick()
            location.startUpdatingLocation()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
        default:
            pendingStart = false
            status = "Allow Location access for Speed Up or Slow Down in Settings before starting."
        }
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        tick()
        pausedAt = Date()
        isPaused = true
        location.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        engine.loseSignal()
        paceSecondsPerKilometre = nil
        recordPace(at: Date())
        speech.stopSpeaking(at: .immediate)
        releaseAudio()
        status = "Run paused. Tap Resume run to continue."
    }

    func resume() {
        guard isRunning, isPaused, let pause = pausedAt else { return }
        guard (location.authorizationStatus == .authorizedAlways ||
               location.authorizationStatus == .authorizedWhenInUse),
              location.accuracyAuthorization == .fullAccuracy else {
            status = "Enable Precise Location and Location access in Settings to resume."
            return
        }
        let now = Date()
        let duration = max(0, now.timeIntervalSince(pause))
        // Keep the engine's clock in active run time so warm-up and cue
        // cooldowns exclude the break, just like elapsed time and the graph.
        pausedDuration += duration
        startedAt = startedAt?.addingTimeInterval(duration)
        warmUpEndsAt = warmUpEndsAt?.addingTimeInterval(duration)
        pausedAt = nil
        isPaused = false
        lastFix = now
        acceptingFixesAfter = now
        status = "Acquiring GPS…"
        location.startUpdatingLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        tick()
        pendingStart = false
        location.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
        pausedAt = nil
        warmUpRemainingText = ""
        speech.stopSpeaking(at: .immediate)
        releaseAudio()
        status = "Run ended."
    }

    private func tick() {
        guard isRunning, !isPaused, let start = startedAt else { return }
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        elapsedSeconds = Double(seconds)
        elapsedText = String(format: "%d:%02d", seconds / 60, seconds % 60)
        if let end = warmUpEndsAt {
            let remaining = max(0, Int(ceil(end.timeIntervalSinceNow)))
            warmUpRemainingText = remaining > 0
                ? String(format: "Warm-up: %d:%02d remaining", remaining / 60, remaining % 60)
                : (warmUpReportPending ? "Warm-up complete. Waiting for a reliable pace estimate." : "")
        } else { warmUpRemainingText = "" }
        if Date().timeIntervalSince(lastFix ?? start) > 8 {
            engine.loseSignal()
            paceSecondsPerKilometre = nil
            recordPace(at: Date())
            status = "Waiting for a reliable GPS signal. Coaching paused."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isRunning && (manager.accuracyAuthorization != .fullAccuracy ||
                         (manager.authorizationStatus != .authorizedAlways &&
                          manager.authorizationStatus != .authorizedWhenInUse)) {
            stop()
            status = "Location access changed. Enable Precise Location and start again."
        } else if pendingStart { start() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRunning, !isPaused else { return }
        // Use only the latest fix; cached background batches must not trigger old cues.
        guard let fix = locations.last,
              abs(fix.timestamp.timeIntervalSinceNow) <= 3,
              acceptingFixesAfter.map({ fix.timestamp >= $0 }) ?? true,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 20,
              fix.speedAccuracy >= 0, fix.speedAccuracy <= 1.5,
              fix.speed >= 0, fix.speed <= 8,
              lastFix.map({ fix.timestamp.timeIntervalSince($0) >= 1 }) ?? true else { return }
        lastFix = fix.timestamp
        let cue = engine.ingest(speed: fix.speed, at: fix.timestamp.timeIntervalSinceReferenceDate - pausedDuration,
                                targetPace: targetPaceSecondsPerKilometre,
                                coachingAvailable: coachingEnabled && !speech.isSpeaking)
        distanceMetres = engine.distanceMetres
        paceSecondsPerKilometre = engine.paceSecondsPerKilometre
        recordPace(at: fix.timestamp)
        if engine.speedMetresPerSecond == nil {
            status = "GPS acquired; settling the pace estimate."
        } else if engine.paceSecondsPerKilometre == nil {
            status = "Stationary."
        } else {
            status = "Tracking your outdoor pace."
        }
        let warmUpComplete = warmUpEndsAt.map { fix.timestamp >= $0 } ?? false
        let unit = DistanceUnit(rawValue: UserDefaults.standard.string(forKey: "distanceUnit") ?? "") ?? .kilometres
        let report = "Warm-up complete. " + unit.paceDifferenceText(
            pace: engine.paceSecondsPerKilometre, target: targetPaceSecondsPerKilometre)
        if warmUpReportPending && warmUpComplete && engine.speedMetresPerSecond != nil {
            warmUpReport = report
            warmUpReportPending = false
            warmUpRemainingText = ""
        }
        if let cue {
            if coachingEnabled && !speech.isSpeaking {
                if warmUpSpeechPending && warmUpComplete {
                    speak(report)
                    warmUpSpeechPending = false
                } else { speak(phrases.next(for: cue)) }
            }
        }
    }

    private func recordPace(at date: Date) {
        guard let start = startedAt else { return }
        guard let pace = paceSecondsPerKilometre, pace.isFinite, pace > 0 else {
            if lastGraphFix != nil { paceSegment += 1 }
            lastGraphFix = nil
            return
        }
        if let previous = lastGraphFix, date.timeIntervalSince(previous) > 8 {
            paceSegment += 1
        }
        lastGraphFix = date
        paceSamples.append(PaceSample(id: paceSamples.count,
                                     elapsedSeconds: max(0, date.timeIntervalSince(start)),
                                     secondsPerKilometre: pace, segment: paceSegment))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isRunning, !isPaused else { return }
        if let error = error as? CLError, error.code == .denied {
            stop()
            status = "Location unavailable. Check Location Services and Speed Up or Slow Down permissions."
        } else {
            engine.loseSignal()
            paceSecondsPerKilometre = nil
            recordPace(at: Date())
            status = "GPS temporarily unavailable. Coaching paused."
        }
    }

    private func speak(_ text: String) {
        guard !speech.isSpeaking else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
            audioActive = true
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
                ?? AVSpeechSynthesisVoice(language: "en-US")
            speech.speak(utterance)
        } catch {
            releaseAudio()
            status = "Audio unavailable. Pace tracking continues."
        }
    }

    private func releaseAudio() {
        guard audioActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioActive = false
        } catch { /* Retry after the next utterance or when stopping. */ }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        releaseAudio()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        releaseAudio()
    }
}
