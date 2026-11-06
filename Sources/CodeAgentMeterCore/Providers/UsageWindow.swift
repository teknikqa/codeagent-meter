import Foundation

/// One quota window of a snapshot, flattened across groups so history, pace
/// and notifications can treat every vendor the same way.
public struct UsageWindow: Equatable, Sendable {
    /// Stable per account, e.g. "session" or "Gemini/weekly".
    public let key: String
    public let label: String
    public let percent: Double
    public let resetsAt: Date?
    /// Window length when it's a known rolling window (5h session, 7d week).
    public let length: TimeInterval?
}

extension UsageSnapshot {
    public static let sessionLength: TimeInterval = 5 * 3600
    public static let weeklyLength: TimeInterval = 7 * 86400

    public var windows: [UsageWindow] {
        if groups.isEmpty { return ownWindows(prefix: nil) }
        return groups.flatMap { $0.snapshot.ownWindows(prefix: $0.name) }
    }

    private func ownWindows(prefix: String?) -> [UsageWindow] {
        func key(_ k: String) -> String { prefix.map { "\($0)/\(k)" } ?? k }
        func label(_ l: String) -> String { prefix.map { "\($0) \(l.lowercased())" } ?? l }
        var result: [UsageWindow] = []
        if let percentUsed {
            result.append(UsageWindow(
                key: key("primary"), label: label(primaryLabel), percent: percentUsed, resetsAt: resetsAt,
                length: primaryLabel == "Session" ? Self.sessionLength : nil))
        }
        if let weeklyPercentUsed {
            result.append(UsageWindow(
                key: key("weekly"), label: label("Weekly"), percent: weeklyPercentUsed, resetsAt: weeklyResetsAt,
                length: Self.weeklyLength))
        }
        return result
    }
}
