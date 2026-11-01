import SwiftUI
import Charts
import AVFoundation
import PhotosUI
import CryptoKit

struct ContentView: View {
    @StateObject private var run = RunTracker()
    @AppStorage("distanceUnit") private var unit: DistanceUnit = .kilometres
    @AppStorage("colorfulAppearance") private var colorfulAppearance = false
    @State private var showingSettings = false
    @State private var showingHistory = false

    private var displayedTarget: Binding<Double> {
        Binding(
            get: { unit.displayedPace(secondsPerKilometre: run.targetPaceSecondsPerKilometre) },
            set: { run.targetPaceSecondsPerKilometre = unit.secondsPerKilometre(
                displayedPace: unit.roundedTarget(displayedPace: $0)) }
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
                Button { showingHistory = true } label: {
                    Label("Run History", systemImage: "clock.arrow.circlepath")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        paceReading("Current pace", secondsPerKilometre: run.paceSecondsPerKilometre)
                        paceReading("Overall pace", secondsPerKilometre: run.overallPaceSecondsPerKilometre)
                    }
                    VStack(spacing: 20) {
                        paceReading("Current pace", secondsPerKilometre: run.paceSecondsPerKilometre)
                        paceReading("Overall pace", secondsPerKilometre: run.overallPaceSecondsPerKilometre)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(colorfulAppearance ? 16 : 0)
                .background {
                    if colorfulAppearance {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.teal.opacity(0.14))
                    }
                }
                HStack {
                    Label(run.elapsedText, systemImage: "timer")
                        .tint(colorfulAppearance ? .orange : .accentColor)
                    Spacer()
                    Text(unit.distanceText(metres: run.distanceMetres))
                }.font(.title3.monospacedDigit())
                .padding(colorfulAppearance ? 16 : 0)
                .background {
                    if colorfulAppearance {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.orange.opacity(0.12))
                    }
                }
                if run.isRunning || run.elapsedSeconds > 0 || !run.paceSamples.isEmpty {
                    PaceGraphView(samples: run.paceSamples, elapsedSeconds: run.elapsedSeconds,
                                  isRunning: run.isRunning, unit: unit)
                }
                VStack {
                    Text("Target: \(unit.paceText(secondsPerKilometre: run.targetPaceSecondsPerKilometre)) / \(unit.symbol)")
                        .font(.headline).monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
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
                .tint(colorfulAppearance ? .purple : .accentColor)
                .padding(colorfulAppearance ? 16 : 0)
                .background {
                    if colorfulAppearance {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.purple.opacity(0.12))
                    }
                }
                if !run.warmUpRemainingText.isEmpty {
                    Text(run.warmUpRemainingText).font(.callout).monospacedDigit()
                        .multilineTextAlignment(.center)
                }
                Text(run.status).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(minHeight: 44)
            }.padding(24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                if run.completedRunID != nil && !run.isRunning {
                    VStack(spacing: 4) {
                        Label(run.historyError == nil ? "Run saved" : "Run not saved yet",
                              systemImage: run.historyError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.headline)
                        Text(run.historyError == nil
                             ? "Ready for a new run. Your summary is above."
                             : "Open Run History and retry saving before starting again.")
                            .font(.caption).multilineTextAlignment(.center)
                        Button("View Run History") { showingHistory = true }
                    }
                    .accessibilityElement(children: .contain)
                }
                if run.isRunning {
                    Button {
                        if run.isPaused { run.resume() } else { run.pause() }
                    } label: {
                        Label(run.isPaused ? "Resume run" : "Pause run",
                              systemImage: run.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.borderedProminent)
                }
                Button {
                    if run.isRunning { run.stop() } else { run.start() }
                } label: {
                    Text(run.isRunning ? "Stop run" : (run.completedRunID != nil ? "Start new run" : "Start run"))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(.borderedProminent)
                    .tint(run.isRunning ? .red : (colorfulAppearance ? .teal : .blue))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .tint(colorfulAppearance ? .teal : .accentColor)
        .sheet(isPresented: $showingSettings) {
            RunSettingsView(run: run, unit: $unit)
        }
        .sheet(isPresented: $showingHistory) {
            RunHistoryView(run: run, unit: unit)
        }
        .onAppear { roundTarget() }
        .onChange(of: unit) { _, _ in
            roundTarget()
            run.updateLiveActivity(force: true)
        }
    }

    private func paceReading(_ title: String, secondsPerKilometre: Double?) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline).fixedSize(horizontal: true, vertical: false)
            Text(unit.paceText(secondsPerKilometre: secondsPerKilometre))
                .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("min/\(unit.symbol)")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(unit.paceText(secondsPerKilometre: secondsPerKilometre)), \(unit.paceDescription)")
    }

    private func roundTarget() {
        let current = unit.displayedPace(secondsPerKilometre: run.targetPaceSecondsPerKilometre)
        displayedTarget.wrappedValue = unit.roundedTarget(displayedPace: current)
    }
}

private struct PaceGraphView: View {
    let samples: [PaceSample]
    let elapsedSeconds: Double
    let isRunning: Bool
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isRunning ? "Live pace" : "Run pace summary").font(.headline)
            if samples.isEmpty {
                Text(isRunning ? "Your graph will appear once GPS pace settles." : "No reliable pace readings were recorded.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(samples) { sample in
                    LineMark(x: .value("Elapsed minutes", sample.elapsedSeconds / 60),
                             y: .value("Pace", unit.displayedPace(secondsPerKilometre: sample.secondsPerKilometre)),
                             series: .value("Continuous readings", sample.segment))
                        .foregroundStyle(by: .value("Run phase", sample.isWarmUp ? "Warm-up" : "After warm-up"))
                    PointMark(x: .value("Elapsed minutes", sample.elapsedSeconds / 60),
                              y: .value("Pace", unit.displayedPace(secondsPerKilometre: sample.secondsPerKilometre)))
                        .symbolSize(8)
                        .foregroundStyle(by: .value("Run phase", sample.isWarmUp ? "Warm-up" : "After warm-up"))
                }
                .chartForegroundStyleScale(domain: ["Warm-up", "After warm-up"],
                                           range: [Color.orange, Color.accentColor])
                .chartLegend(samples.contains(where: { $0.isWarmUp }) ? .visible : .hidden)
                .chartXScale(domain: 0...max(1, max(elapsedSeconds, samples.last?.elapsedSeconds ?? 0) / 60))
                .chartYScale(domain: .automatic(reversed: true))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(unit.paceText(secondsPerKilometre: unit.secondsPerKilometre(displayedPace: seconds)))
                            }
                        }
                    }
                }
                .chartXAxisLabel("Elapsed time (minutes)")
                .chartYAxisLabel("min/\(unit.symbol) · faster ↑")
                .frame(height: 200)
            }
            Text("Smoothed GPS pace. Gaps indicate unavailable pace.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}


private struct RunHistoryView: View {
    @ObservedObject var run: RunTracker
    let unit: DistanceUnit
    @Environment(\.dismiss) private var dismiss

    @State private var runToDelete: SavedRun?
    @State private var showingDeleteError = false

    private var totalSeconds: Double { run.savedRuns.reduce(0) { $0 + $1.elapsedSeconds } }
    private var totalMetres: Double { run.savedRuns.reduce(0) { $0 + $1.distanceMetres } }

    var body: some View {
        NavigationStack {
            List {
                if let error = run.historyError {
                    Section {
                        Text(error)
                        Button("Retry") { run.retryHistory() }
                    }
                }
                Section("All runs") {
                    LabeledContent("Runs", value: "\(run.savedRuns.count)")
                    historyMetrics(seconds: totalSeconds, metres: totalMetres, unit: unit)
                    Text("Totals and average pace include warm-up and exclude manual pauses. Average pace uses total time divided by total distance.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Completed runs") {
                    if run.savedRuns.isEmpty {
                        Text("Stop a run to save it here automatically. Runs are stored only on this phone.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(run.savedRuns) { saved in
                        NavigationLink {
                            List {
                                Section {
                                    Text(saved.date.formatted(date: .abbreviated, time: .standard))
                                    historyMetrics(seconds: saved.elapsedSeconds, metres: saved.distanceMetres, unit: unit)
                                    Text("Includes warm-up; excludes manual pauses.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Section {
                                    PaceGraphView(samples: saved.samples, elapsedSeconds: saved.elapsedSeconds,
                                                  isRunning: false, unit: unit)
                                }
                            }
                            .navigationTitle("Saved run")
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(saved.date.formatted(date: .abbreviated, time: .standard))
                                Text("\(unit.distanceText(metres: saved.distanceMetres)) · \(historyDuration(saved.elapsedSeconds))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { runToDelete = saved } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .disabled(run.historyError != nil)
                        }
                    }
                }
                if !run.savedRuns.isEmpty {
                    Section {
                        Text("Swipe left on a run to delete it from this phone and from your totals.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .confirmationDialog("Delete this run?", isPresented: Binding(
                get: { runToDelete != nil },
                set: { if !$0 { runToDelete = nil } }
            ), titleVisibility: .visible) {
                if let saved = runToDelete {
                    Button("Delete run", role: .destructive) {
                        do { try run.deleteRun(saved.id) }
                        catch { showingDeleteError = true }
                        runToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { runToDelete = nil }
            } message: {
                Text("This permanently removes the run and its pace graph from Run History. This cannot be undone.")
            }
            .alert("Could not delete run", isPresented: $showingDeleteError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your run is still in Run History. Try deleting it again.")
            }
            .navigationTitle("Run History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private func historyDuration(_ seconds: Double) -> String {
    let total = Int(seconds)
    return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
}

@ViewBuilder private func historyMetrics(seconds: Double, metres: Double, unit: DistanceUnit) -> some View {
    LabeledContent("Active time", value: historyDuration(seconds))
    LabeledContent("Distance", value: unit.distanceText(metres: metres))
    LabeledContent("Average pace", value: "\(unit.paceText(secondsPerKilometre: RunHistory.averagePace(seconds: seconds, metres: metres))) / \(unit.symbol)")
}

private struct RunSettingsView: View {
    @ObservedObject var run: RunTracker
    @Binding var unit: DistanceUnit
    @AppStorage("colorfulAppearance") private var colorfulAppearance = false
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
                Section {
                    Toggle("Colorful appearance", isOn: $colorfulAppearance)
                } footer: {
                    Text("Add teal, orange, and purple accents to the run screen.")
                }
                Section("Units") {
                    Picker("Distance", selection: $unit) {
                        Text("Kilometres").tag(DistanceUnit.kilometres)
                        Text("Miles").tag(DistanceUnit.miles)
                    }.pickerStyle(.segmented)
                }
                Section {
                    Stepper(run.warmUpMinutes == 0 ? "Warm-up: Off" : "Warm-up: \(run.warmUpMinutes) minutes",
                            value: $run.warmUpMinutes, in: 0...30)
                        .disabled(run.isRunning)
                } footer: {
                    Text("Track pace and distance without coaching for the first 0–30 minutes. Warm-up pace is orange on the graph. After warm-up, speak your difference from target when GPS is reliable. Set before starting a run; 0 turns warm-up off.")
                }
                Section {
                    Toggle("Include warm-up in overall pace", isOn: $run.includeWarmUpInOverallPace)
                } footer: {
                    Text("When off, overall pace uses only time and distance after warm-up. It shows a dash until then. Run time, total distance, and the graph still include warm-up. You can change this during or after a run.")
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
        .tint(colorfulAppearance ? .teal : .accentColor)
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
    @State private var screenshots: [ChangeScreenshot] = ChangeScreenshot.load()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var loadingPhotos = false
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
        screenshots = []
        ChangeScreenshot.save(screenshots)
    }

    private func comments(_ number: Int) async throws -> [ScreenshotComment] {
        var result: [ScreenshotComment] = []
        for page in 1...100 {
            let url = URL(string: "https://api.github.com/repos/batemapf/pacer/issues/\(number)/comments?per_page=100&page=\(page)")!
            let (data, response) = try await URLSession.shared.data(for: githubRequest(url))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let batch = try JSONDecoder().decode([ScreenshotComment].self, from: data)
            result += batch
            if batch.count < 100 { return result }
        }
        throw URLError(.dataLengthExceedsMaximum)
    }

    private func uploadScreenshots(to number: Int) async throws {
        guard !screenshots.isEmpty else { return }
        let existing = try await comments(number)
        for screenshot in screenshots {
            let parts = screenshot.parts
            for (index, part) in parts.enumerated() {
                let marker = "<!-- app-change-image:\(requestID):\(screenshot.id):\(index):\(parts.count) -->"
                let body = marker + "\n```base64\n" + part + "\n```"
                if existing.contains(where: { $0.body == body }) { continue }
                var post = githubRequest(URL(string: "https://api.github.com/repos/batemapf/pacer/issues/\(number)/comments")!)
                post.httpMethod = "POST"
                post.setValue("application/json", forHTTPHeaderField: "Content-Type")
                post.httpBody = try JSONEncoder().encode(ScreenshotComment(body: body))
                let (_, response) = try await URLSession.shared.data(for: post)
                guard (response as? HTTPURLResponse)?.statusCode == 201 else { throw URLError(.badServerResponse) }
            }
        }
    }

    @MainActor private func loadPhotos(_ items: [PhotosPickerItem]) async {
        loadingPhotos = true
        errorMessage = nil
        defer { loadingPhotos = false; photoItems = [] }
        do {
            var selected = screenshots
            for item in items.prefix(3 - selected.count) {
                guard let data = try await item.loadTransferable(type: Data.self),
                      data.count <= 30_000_000, let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                let scale = min(1, 1600 / max(image.size.width, image.size.height))
                let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                guard let jpeg = resized.jpegData(compressionQuality: 0.75), jpeg.count <= 600_000 else {
                    throw URLError(.dataLengthExceedsMaximum)
                }
                let screenshot = ChangeScreenshot(data: jpeg)
                if !selected.contains(where: { $0.id == screenshot.id }) { selected.append(screenshot) }
            }
            try ChangeScreenshot.persist(selected)
            screenshots = selected
            requestID = ""
        } catch {
            errorMessage = "Could not save the selected screenshots. Try a smaller image."
        }
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
                        try await uploadScreenshots(to: existing.number)
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
            var body = request + "\n\n---\nSubmitted from Speed Up or Slow Down \(version) (\(build)).\nName supplied by tester (unverified): \(author.isEmpty ? "Anonymous tester" : author)\n\nA maintainer must apply ready-for-agent before Codex runs.\n\n" + marker
            if !screenshots.isEmpty {
                let manifest = ScreenshotManifest(request: requestID, images: screenshots.map {
                    ScreenshotManifest.Image(id: $0.id, parts: $0.parts.count)
                })
                let json = String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self)
                body += "\n\nScreenshots are stored as encoded image comments for the coding agent. If delivery is interrupted, the sender must retry before agent review.\n<!-- app-change-images:" + json + " -->"
            }
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
            let receipt = try JSONDecoder().decode(ChangeReceipt.self, from: data)
            try await uploadScreenshots(to: receipt.number)
            try showReceipt(receipt)
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
            Section("Screenshots (optional)") {
                ForEach(screenshots) { screenshot in
                    HStack {
                        if let image = UIImage(data: screenshot.data) {
                            Image(uiImage: image).resizable().scaledToFit().frame(height: 150)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            var remaining = screenshots
                            remaining.removeAll { $0.id == screenshot.id }
                            do {
                                try ChangeScreenshot.persist(remaining)
                                screenshots = remaining
                                requestID = ""
                            } catch { errorMessage = "Could not save screenshot changes. Please retry." }
                        }.disabled(sending || loadingPhotos)
                    }
                }
                if screenshots.count < 3 {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 3 - screenshots.count, matching: .images) {
                        Label("Add screenshots", systemImage: "photo.badge.plus")
                    }.disabled(sending || loadingPhotos)
                }
                if loadingPhotos { ProgressView("Saving screenshots…") }
                Text("Up to 3 images. Review them before sending: screenshots are public and visible to the coding agent. Images are resized and photo metadata is removed.")
                    .font(.caption).foregroundStyle(.secondary)
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
                .disabled(sending || loadingPhotos || request.count < 5 || request.count > 4_000 || name.count > 80 || githubToken.isEmpty)
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
        .onChange(of: photoItems) { _, items in
            if !items.isEmpty { Task { await loadPhotos(items) } }
        }
        .interactiveDismissDisabled(sending || loadingPhotos)
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

private struct ScreenshotComment: Codable { let body: String }

private struct ScreenshotManifest: Encodable {
    struct Image: Encodable { let id: String; let parts: Int }
    let request: String
    let images: [Image]
}

private struct ChangeScreenshot: Codable, Identifiable {
    let data: Data
    var id: String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    var parts: [String] {
        let text = Array(data.base64EncodedString())
        return stride(from: 0, to: text.count, by: 48_000).map {
            String(text[$0..<min($0 + 48_000, text.count)])
        }
    }
    private static var file: URL {
        URL.applicationSupportDirectory.appending(path: "change-screenshots.json")
    }
    static func load() -> [Self] {
        guard let bytes = try? Data(contentsOf: file),
              let images = try? JSONDecoder().decode([Self].self, from: bytes) else { return [] }
        return Array(images.prefix(3))
    }
    static func persist(_ images: [Self]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(images).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func save(_ images: [Self]) { try? persist(images) }
}
