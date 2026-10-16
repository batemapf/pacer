import ActivityKit
import WidgetKit
import SwiftUI
import Charts

@main
struct PacerWidgets: WidgetBundle {
    var body: some Widget { PacerLiveActivity() }
}

struct PacerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Speed Up or Slow Down", systemImage: "figure.run")
                        .font(.caption)
                    Spacer()
                    Text(status(context)).font(.caption)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(context.isStale ? "—" : context.state.paceText)
                        .font(.largeTitle.bold()).monospacedDigit()
                    Text(context.state.unitText).font(.caption)
                    Spacer()
                    Text("Current pace").font(.caption)
                }
                PaceHistory(state: context.state)
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Pace", systemImage: "figure.run")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.isStale ? "—" : context.state.paceText) \(context.state.unitText)")
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status(context)).font(.caption)
                        PaceHistory(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.paused ? "pause.fill" : "figure.run")
            } compactTrailing: {
                Text(context.isStale ? "—" : context.state.paceText).monospacedDigit()
            } minimal: {
                Image(systemName: context.state.paused ? "pause.fill" : "figure.run")
            }
        }
    }

    private func status(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        if context.state.ended { return "Run ended" }
        if context.state.paused { return "Paused" }
        if context.isStale { return "Waiting for update" }
        return context.state.pace == nil ? "Waiting for pace" : "Running"
    }
}

private struct PaceHistory: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if state.points.isEmpty {
                Text("Pace graph appears after GPS settles.")
                    .font(.caption).frame(height: 50)
            } else {
                Chart(state.points) { point in
                    LineMark(x: .value("Run seconds", point.second),
                             y: .value("Pace", -Double(point.pace)),
                             series: .value("Segment", point.segment))
                        .foregroundStyle(.cyan)
                    PointMark(x: .value("Run seconds", point.second),
                              y: .value("Pace", -Double(point.pace)))
                        .foregroundStyle(.cyan).symbolSize(4)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 50)
                .accessibilityLabel("Recent pace trend. Faster pace is higher. Gaps mark pauses or unavailable pace.")
            }
            Text("Recent pace · up to 5 min · faster ↑")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
