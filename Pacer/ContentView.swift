import SwiftUI

struct ContentView: View {
    @StateObject private var run = RunTracker()
    @AppStorage("distanceUnit") private var unit: DistanceUnit = .kilometres

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
                Text("Speed Up or Slow Down")
                    .font(.title.bold()).multilineTextAlignment(.center)
                Picker("Distance units", selection: $unit) {
                    Text("Kilometres").tag(DistanceUnit.kilometres)
                    Text("Miles").tag(DistanceUnit.miles)
                }.pickerStyle(.segmented)
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
                Toggle("Spoken coaching", isOn: $run.coachingEnabled)
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
    }
}
