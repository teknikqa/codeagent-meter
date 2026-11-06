import SwiftUI
import Charts
import CodeAgentMeterCore

/// A window's usage so far, drawn against the straight line an even burn
/// would follow from window start (0%) to reset (100%).
struct BurndownChart: View {
    let window: UsageWindow
    let samples: [UsageSample]

    var body: some View {
        if let length = window.length, let resetsAt = window.resetsAt, samples.count >= 2 {
            let start = resetsAt.addingTimeInterval(-length)
            Chart {
                ForEach([0.0, 100.0], id: \.self) { value in
                    LineMark(
                        x: .value("Time", value == 0 ? start : resetsAt),
                        y: .value("Even use", value),
                        series: .value("Series", "Even use")
                    )
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                ForEach(samples, id: \.time) { sample in
                    LineMark(
                        x: .value("Time", sample.time),
                        y: .value("Used", sample.percent),
                        series: .value("Series", "Used")
                    )
                    .foregroundStyle(.tint)
                }
            }
            .chartXScale(domain: start...resetsAt)
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) }
            .chartXAxis(.hidden)
            .frame(height: 56)
        }
    }
}

struct PaceCaption: View {
    let window: UsageWindow

    var body: some View {
        if let pace = Pace(window: window) {
            Text(pace.summary)
                .font(.caption2)
                .foregroundStyle(pace.status == .ahead ? Color.orange : Color.secondary)
        }
    }
}
