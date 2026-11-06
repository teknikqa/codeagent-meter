import Foundation

public enum RefreshMode: String, Codable, CaseIterable, Sendable {
    case adaptive, m1, m5, m15, m30

    public var label: String {
        switch self {
        case .adaptive: return "Adaptive"
        case .m1: return "Every minute"
        case .m5: return "Every 5 minutes"
        case .m15: return "Every 15 minutes"
        case .m30: return "Every 30 minutes"
        }
    }

    var fixedSeconds: TimeInterval? {
        switch self {
        case .adaptive: return nil
        case .m1: return 60
        case .m5: return 300
        case .m15: return 900
        case .m30: return 1800
        }
    }
}

/// Picks the wait before the next refresh. Most of the endpoints polled here
/// are undocumented, so failures back off in every mode, and adaptive mode
/// also slows down once usage has stopped moving.
public enum RefreshPolicy {
    public static let activeSeconds: TimeInterval = 60
    public static let idleSeconds: TimeInterval = 300
    public static let maxBackoffSeconds: TimeInterval = 900
    /// Consecutive refreshes with no percentage change before adaptive mode idles.
    public static let idleAfterUnchanged = 5

    public static func interval(mode: RefreshMode, failureStreak: Int, unchangedStreak: Int) -> TimeInterval {
        var base = mode.fixedSeconds ?? (unchangedStreak >= idleAfterUnchanged ? idleSeconds : activeSeconds)
        if failureStreak > 0 {
            let backoff = activeSeconds * pow(2, Double(min(failureStreak, 10)))
            base = max(base, min(backoff, maxBackoffSeconds))
        }
        return base
    }
}
