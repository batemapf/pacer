import Foundation
import Combine
import CoreLocation
import AVFoundation

final class RunTracker: NSObject, ObservableObject, CLLocationManagerDelegate, AVSpeechSynthesizerDelegate {
    @Published private(set) var isRunning = false
    @Published private(set) var paceSecondsPerKilometre: Double? = nil
    @Published private(set) var elapsedText = "0:00"
    @Published private(set) var distanceMetres = 0.0
    @Published private(set) var status = ""
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
    private var startedAt: Date?
    private var lastFix: Date?
    private var timer: Timer?
    private var pendingStart = false
    private var audioActive = false

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
            engine = PaceEngine()
            lastFix = nil
            startedAt = Date()
            distanceMetres = 0
            paceSecondsPerKilometre = nil
            elapsedText = "0:00"
            isRunning = true
            status = "Acquiring GPS…"
            location.startUpdatingLocation()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
        default:
            pendingStart = false
            status = "Allow Location access for Speed Up or Slow Down in Settings before starting."
        }
    }

    func stop() {
        pendingStart = false
        location.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        isRunning = false
        speech.stopSpeaking(at: .immediate)
        releaseAudio()
        status = "Run ended."
    }

    private func tick() {
        guard isRunning, let start = startedAt else { return }
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        elapsedText = String(format: "%d:%02d", seconds / 60, seconds % 60)
        if Date().timeIntervalSince(lastFix ?? start) > 8 {
            engine.loseSignal()
            paceSecondsPerKilometre = nil
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
        guard isRunning else { return }
        // Use only the latest fix; cached background batches must not trigger old cues.
        guard let fix = locations.last,
              abs(fix.timestamp.timeIntervalSinceNow) <= 3,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 20,
              fix.speedAccuracy >= 0, fix.speedAccuracy <= 1.5,
              fix.speed >= 0, fix.speed <= 8,
              lastFix.map({ fix.timestamp.timeIntervalSince($0) >= 1 }) ?? true else { return }
        lastFix = fix.timestamp
        let cue = engine.ingest(speed: fix.speed, at: fix.timestamp.timeIntervalSinceReferenceDate,
                                targetPace: targetPaceSecondsPerKilometre,
                                coachingAvailable: coachingEnabled && !speech.isSpeaking)
        distanceMetres = engine.distanceMetres
        paceSecondsPerKilometre = engine.paceSecondsPerKilometre
        if engine.speedMetresPerSecond == nil {
            status = "GPS acquired; settling the pace estimate."
        } else if engine.paceSecondsPerKilometre == nil {
            status = "Stationary."
        } else {
            status = "Tracking your outdoor pace."
        }
        if let cue { speak(phrases.next(for: cue)) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError, error.code == .denied {
            stop()
            status = "Location unavailable. Check Location Services and Speed Up or Slow Down permissions."
        } else {
            engine.loseSignal()
            paceSecondsPerKilometre = nil
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
