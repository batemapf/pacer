import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var run = RunTracker()
    @AppStorage("distanceUnit") private var unit: DistanceUnit = .kilometres
    @State private var showingSettings = false

    private var displayedTarget: Binding<Double> {
        Binding(
            get: { unit.displayedPace(secondsPerKilometre: run.targetPaceSecondsPerKilometre) },
            set: { run.targetPaceSecondsPerKilometre = unit.secondsPerKilometre(displayedPace: $0) }
        )
    }

    private func adjustTarget(by seconds: Double) {
        let range = unit.targetRange
        displayedTarget.wrappedValue = min(range.upperBound,
                                          max(range.lowerBound, displayedTarget.wrappedValue + seconds))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(alignment: .top) {
                    Text("Speed Up or Slow Down")
                        .font(.title.bold())
                    Spacer()
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape").font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("Settings")
                }
                VStack(spacing: 8) {
                    Text(unit.paceText(secondsPerKilometre: run.paceSecondsPerKilometre))
                        .font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                        .accessibilityLabel("Current pace \(unit.paceText(secondsPerKilometre: run.paceSecondsPerKilometre)), \(unit.paceDescription)")
                    Text(unit.paceDescription).foregroundStyle(.secondary)
                }
                HStack {
                    Label(run.elapsedText, systemImage: "timer")
                    Spacer()
                    Text(unit.distanceText(metres: run.distanceMetres))
                }.font(.title3.monospacedDigit())
                VStack {
                    Text("Target: \(unit.paceText(secondsPerKilometre: run.targetPaceSecondsPerKilometre)) / \(unit.symbol)")
                        .font(.headline).monospacedDigit()
                    Slider(value: displayedTarget, in: unit.targetRange, step: 15)
                        .accessibilityLabel("Target pace, \(unit.paceDescription)")
                    HStack {
                        Button { adjustTarget(by: -15) } label: {
                            Label("Faster", systemImage: "minus")
                        }.disabled(displayedTarget.wrappedValue <= unit.targetRange.lowerBound)
                        Spacer()
                        Button { adjustTarget(by: 15) } label: {
                            Label("Slower", systemImage: "plus")
                        }.disabled(displayedTarget.wrappedValue >= unit.targetRange.upperBound)
                    }.buttonStyle(.bordered)
                }
                Text(run.status).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(minHeight: 44)
                Button {
                    if run.isRunning { run.stop() } else { run.start() }
                } label: {
                    Text(run.isRunning ? "Stop run" : "Start run")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(.borderedProminent).tint(run.isRunning ? .red : .blue)
            }.padding(24)
        }
        .sheet(isPresented: $showingSettings) {
            RunSettingsView(run: run, unit: $unit)
        }
    }
}


private struct RunSettingsView: View {
    @ObservedObject var run: RunTracker
    @Binding var unit: DistanceUnit
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var voices: [AVSpeechSynthesisVoice] = []

    private func refreshVoices() {
        voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-") }
            .sorted { voiceLabel($0).localizedStandardCompare(voiceLabel($1)) == .orderedAscending }
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let accent = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        let quality: String
        switch voice.quality {
        case .enhanced: quality = " · Enhanced"
        case .premium: quality = " · Premium"
        default: quality = ""
        }
        return "\(voice.name) · \(accent)\(quality)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Distance", selection: $unit) {
                        Text("Kilometres").tag(DistanceUnit.kilometres)
                        Text("Miles").tag(DistanceUnit.miles)
                    }.pickerStyle(.segmented)
                }
                Section("Audio") {
                    Toggle("Spoken coaching", isOn: $run.coachingEnabled)
                    Picker("Voice", selection: $run.voiceIdentifier) {
                        Text("Default (US English)").tag("")
                        if !run.voiceIdentifier.isEmpty && !voices.contains(where: { $0.identifier == run.voiceIdentifier }) {
                            Text("Unavailable — using default").tag(run.voiceIdentifier)
                        }
                        ForEach(voices, id: \.identifier) { voice in
                            Text(voiceLabel(voice)).tag(voice.identifier)
                        }
                    }.pickerStyle(.navigationLink)
                    Button("Preview voice", systemImage: "speaker.wave.2") {
                        run.previewVoice()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { refreshVoices() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshVoices() }
        }
    }
}
