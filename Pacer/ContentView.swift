import SwiftUI

struct ContentView: View {
    @StateObject private var run = RunTracker()
    @State private var targetSeconds = 360.0

    var body: some View {
        VStack(spacing: 24) {
            Text("Pacer").font(.largeTitle.bold())
            Text("Outdoor jogging coach").foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text(run.paceText).font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit().accessibilityLabel("Current pace \(run.paceText)")
                Text("minutes per kilometre").foregroundStyle(.secondary)
            }
            HStack {
                Label(run.elapsedText, systemImage: "timer")
                Spacer()
                Text(String(format: "%.2f km", run.distanceMetres / 1000))
            }.font(.title3.monospacedDigit())
            VStack {
                Text("Target: \(RunTracker.formatPace(targetSeconds)) / km").font(.headline)
                Slider(value: $targetSeconds, in: 240...720, step: 15)
                    .accessibilityLabel("Target pace in seconds per kilometre")
                HStack { Text("4:00"); Spacer(); Text("12:00") }.font(.caption)
            }.disabled(run.isRunning)
            Toggle("Spoken coaching", isOn: $run.coachingEnabled)
            Text(run.status).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(minHeight: 44)
            Button {
                if run.isRunning { run.stop() } else { run.start(targetPace: targetSeconds) }
            } label: {
                Text(run.isRunning ? "Stop run" : "Start run")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }.buttonStyle(.borderedProminent).tint(run.isRunning ? .red : .blue)
            Text("Allow Precise Location. Keep your phone with you. Audio nudges start after GPS settles, at most once every 30 seconds.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(24)
    }
}
