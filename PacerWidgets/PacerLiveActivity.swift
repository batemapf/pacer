import ActivityKit
import WidgetKit
import SwiftUI
import Charts
import Foundation

@main
struct PacerWidgets: WidgetBundle {
    var body: some Widget { PacerLiveActivity() }
}

struct PacerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Label(indicator(context).text, systemImage: indicator(context).symbol)
                    .font(.headline)
                HStack(alignment: .firstTextBaseline) {
                    Text(context.isStale ? "—" : context.state.paceText)
                        .font(.largeTitle.bold()).monospacedDigit()
                    Text(context.state.unitText).font(.caption)
                    Spacer()
                }
                PaceHistory(state: context.state)
            }
            .padding()
            .foregroundStyle(.white)
            .activityBackgroundTint(indicator(context).color)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: indicator(context).symbol)
                        .foregroundStyle(indicator(context).tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.isStale ? "—" : context.state.paceText) \(context.state.unitText)")
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(indicator(context).text, systemImage: indicator(context).symbol)
                            .font(.headline)
                            .foregroundStyle(indicator(context).tint)
                        PaceHistory(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: indicator(context).symbol)
                    .foregroundStyle(indicator(context).tint)
                    .accessibilityLabel(indicator(context).text)
            } compactTrailing: {
                Text(context.isStale ? "—" : context.state.paceText).monospacedDigit()
            } minimal: {
                Image(systemName: indicator(context).symbol)
                    .foregroundStyle(indicator(context).tint)
                    .accessibilityLabel(indicator(context).text)
            }
        }
    }

    // Use dark, saturated backgrounds with white text on the Lock Screen.
    // Symbols and short labels convey direction independently of color.
    private func indicator(_ context: ActivityViewContext<RunActivityAttributes>)
        -> (text: String, symbol: String, color: Color, tint: Color) {
        let neutral = Color(red: 0.22, green: 0.25, blue: 0.29)
        if context.state.ended { return ("Run ended", "stop.fill", neutral, .white) }
        if context.state.paused { return ("Paused", "pause.fill", neutral, .white) }
        if context.isStale { return ("Updating…", "arrow.clockwise", neutral, .white) }
        if context.state.guidance == .warmUp { return ("Warm-up", "figure.walk", neutral, .white) }
        guard let pace = context.state.pace, pace.isFinite, pace > 0 else {
            return ("Finding pace…", "location", neutral, .white)
        }
        switch context.state.guidance {
        case .speedUp:
            return ("Speed up", "arrow.up", Color(red: 0.60, green: 0.25, blue: 0.02), .orange)
        case .slowDown:
            return ("Slow down", "arrow.down", Color(red: 0.10, green: 0.32, blue: 0.65), .cyan)
        case .onPace:
            return ("On pace", "checkmark", Color(red: 0.08, green: 0.40, blue: 0.24), .green)
        default:
            return ("Running", "figure.run", neutral, .white)
        }
    }
}

private struct PaceHistory: View {
    let state: RunActivityAttributes.ContentState

    private var unitMultiplier: Double { state.usesMiles ? 1.609344 : 1 }

    // Round outward to half-minute boundaries, leaving room around flat traces.
    private var paceBounds: ClosedRange<Double> {
        let paces = state.points.map { Double($0.pace) * unitMultiplier }
        let lower = max(0, floor((paces.min() ?? 0) / 30) * 30 - 30)
        let upper = ceil((paces.max() ?? 0) / 30) * 30 + 30
        return lower...max(lower + 60, upper)
    }

    private func clockText(_ seconds: Double) -> String {
        let rounded = Int(abs(seconds).rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent pace · min\(state.unitText) · faster ↑")
                .font(.caption2)
            if state.points.isEmpty {
                Text("Waiting for pace history")
                    .font(.caption2)
                    .frame(height: 64)
            } else {
                Chart(state.points) { point in
                    LineMark(x: .value("Run seconds", point.second),
                             y: .value("Pace", -Double(point.pace) * unitMultiplier),
                             series: .value("Segment", point.segment))
                        .foregroundStyle(.cyan)
                    PointMark(x: .value("Run seconds", point.second),
                              y: .value("Pace", -Double(point.pace) * unitMultiplier))
                        .foregroundStyle(.cyan).symbolSize(4)
                }
                .chartYScale(domain: -paceBounds.upperBound ... -paceBounds.lowerBound)
                .chartYAxis {
                    AxisMarks(position: .leading,
                              values: [-paceBounds.upperBound, -paceBounds.lowerBound]) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.25))
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(clockText(seconds)).foregroundStyle(.white)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: Array(Set([state.points.first?.second,
                                                state.points.last?.second].compactMap { $0 })).sorted()) { value in
                        AxisValueLabel {
                            if let second = value.as(Int.self) {
                                Text(clockText(Double(second))).foregroundStyle(.white)
                            }
                        }
                    }
                }
                .chartXAxisLabel("Elapsed (m:ss)")
                .frame(height: 64)
                .accessibilityLabel("Recent pace trend. Faster pace is higher. Gaps mark pauses or unavailable pace.")
            }
        }
    }
}
