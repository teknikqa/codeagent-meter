import Foundation

public struct ThresholdAlert: Equatable, Sendable {
    public let account: UUID
    public let windowLabel: String
    public let threshold: Int
    public let percent: Double
}

/// Decides when a window has crossed a usage threshold since the last look.
/// Each threshold fires once per window; it re-arms when usage drops back
/// below it (the window reset). The first reading of a window only seeds the
/// state, so launching the app while already at 90% doesn't notify.
public struct ThresholdTracker: Sendable {
    public static let defaultThresholds = [80, 100]

    private let thresholds: [Int]
    private var levels: [String: Int] = [:]

    public init(thresholds: [Int] = ThresholdTracker.defaultThresholds) {
        self.thresholds = thresholds.sorted()
    }

    public mutating func evaluate(account: UUID, windows: [UsageWindow]) -> [ThresholdAlert] {
        var alerts: [ThresholdAlert] = []
        for window in windows {
            let id = "\(account.uuidString)|\(window.key)"
            let level = thresholds.last { Double($0) <= window.percent } ?? 0
            if let previous = levels[id], level > previous {
                alerts.append(ThresholdAlert(account: account, windowLabel: window.label, threshold: level, percent: window.percent))
            }
            levels[id] = level
        }
        return alerts
    }
}
