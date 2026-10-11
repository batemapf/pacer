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
                Section {
                    Toggle("Haptic coaching", isOn: $run.hapticCoachingEnabled)
                } footer: {
                    Text("Feel pace cues while the app is open, with or without spoken coaching. Haptics may be unavailable when the screen is locked or the app is in the background.")
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
                Section {
                    NavigationLink {
                        AppChangeView()
                    } label: {
                        Label("Change app", systemImage: "wand.and.stars")
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


private struct AppChangeView: View {
    @AppStorage("appChangeDraft") private var draft = ""
    @AppStorage("appChangeName") private var name = ""
    @AppStorage("appChangeRequestID") private var requestID = ""
    @State private var sending = false
    @State private var errorMessage: String?
    @State private var sentNumber: Int?
    @State private var sentURL: URL?

    private var request: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var githubToken: String {
        Bundle.main.object(forInfoDictionaryKey: "AppChangeGitHubToken") as? String ?? ""
    }

    private func githubRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 20
        request.setValue("Bearer " + githubToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Speed-Up-or-Slow-Down", forHTTPHeaderField: "User-Agent")
        return request
    }

    @MainActor private func showReceipt(_ result: ChangeReceipt) throws {
        guard let url = URL(string: result.html_url), url.scheme == "https", url.host == "github.com",
              url.path == "/batemapf/pacer/issues/\(result.number)" else { throw URLError(.badServerResponse) }
        sentNumber = result.number
        sentURL = url
        draft = ""
        requestID = ""
    }

    @MainActor private func submit() async {
        guard !githubToken.isEmpty, !sending else { return }
        sending = true
        errorMessage = nil
        defer { sending = false }
        let retrying = !requestID.isEmpty
        if requestID.isEmpty { requestID = UUID().uuidString }
        let marker = "<!-- app-change-request:\(requestID) -->"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        do {
            // Check recent requests after an uncertain response before posting again.
            if retrying {
                let lookup = githubRequest(URL(string: "https://api.github.com/repos/batemapf/pacer/issues?state=all&sort=created&direction=desc&per_page=100")!)
                for attempt in 0..<3 {
                    let (data, response) = try await URLSession.shared.data(for: lookup)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    let recent = try JSONDecoder().decode([ChangeReceipt].self, from: data)
                    if let existing = recent.first(where: { $0.body?.contains(marker) == true }) {
                        try showReceipt(existing)
                        return
                    }
                    if attempt < 2 { try await Task.sleep(for: .seconds(2)) }
                }
            }
            var submission = githubRequest(URL(string: "https://api.github.com/repos/batemapf/pacer/issues")!)
            submission.httpMethod = "POST"
            submission.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let author = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = "App change: " + String((request.split(separator: "\n").first.map(String.init) ?? request).prefix(100))
            let body = request + "\n\n---\nSubmitted from Speed Up or Slow Down \(version) (\(build)).\nName supplied by tester (unverified): \(author.isEmpty ? "Anonymous tester" : author)\n\nA maintainer must apply ready-for-agent before Codex runs.\n\n" + marker
            submission.httpBody = try JSONEncoder().encode(ChangeSubmission(title: title, body: body, labels: ["app-change"]))
            let (data, response) = try await URLSession.shared.data(for: submission)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 201 else {
                switch http.statusCode {
                case 401: errorMessage = "Change requests need an updated app credential. Please let the app owner know."
                case 403, 429: errorMessage = "Change requests are temporarily unavailable. Please try again later."
                default: errorMessage = "Could not send your request. Your draft is saved; please retry."
                }
                return
            }
            try showReceipt(JSONDecoder().decode(ChangeReceipt.self, from: data))
        } catch {
            errorMessage = "Could not confirm delivery. Your draft is saved; please retry."
        }
    }

    var body: some View {
        Form {
            if let sentNumber {
                Section {
                    Label("Request #\(sentNumber) sent", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("It will be reviewed before the agent starts working on it.")
                    if let sentURL { Link("View request", destination: sentURL) }
                }
            }
            Section("What would you like changed?") {
                TextEditor(text: $draft).frame(minHeight: 180)
                    .accessibilityLabel("Describe the change you want")
                    .disabled(sending)
                if request.count > 4_000 {
                    Text("Please keep the request under 4,000 characters.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                TextField("Name (optional)", text: $name)
                    .textContentType(.nickname).disabled(sending)
            } footer: {
                Text("No account needed. Requests are posted to the app’s public GitHub repository, so leave out personal details and passwords.")
            }
            Section {
                Button { Task { await submit() } } label: {
                    HStack {
                        Text(sending ? "Sending…" : "Send request")
                        if sending { Spacer(); ProgressView() }
                    }
                }
                .disabled(sending || request.count < 5 || request.count > 4_000 || name.count > 80 || githubToken.isEmpty)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                if githubToken.isEmpty {
                    Text("Change requests aren’t available in this build yet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Change app")
        .onChange(of: draft) { _, _ in if !sending { requestID = "" } }
        .onChange(of: name) { _, _ in if !sending { requestID = "" } }
        .interactiveDismissDisabled(sending)
    }
}

private struct ChangeSubmission: Encodable {
    let title: String
    let body: String
    let labels: [String]
}

private struct ChangeReceipt: Decodable {
    let number: Int
    let html_url: String
    let body: String?
}
