import Foundation

public struct UsageSample: Codable, Equatable, Sendable {
    public let account: UUID
    public let key: String
    public let time: Date
    public let percent: Double
}

/// Rolling record of every window's percentage, kept so the UI can draw a
/// burndown against an even-use guide.
public struct UsageHistory: Codable, Equatable, Sendable {
    public static let retention: TimeInterval = 14 * 86400
    /// Samples closer together than this are dropped, so a 60s refresh doesn't bloat the file.
    public static let minSpacing: TimeInterval = 120

    public private(set) var samples: [UsageSample] = []

    public init() {}

    public mutating func record(account: UUID, snapshot: UsageSnapshot, now: Date = Date()) {
        for window in snapshot.windows {
            let last = samples.last { $0.account == account && $0.key == window.key }
            if let last, now.timeIntervalSince(last.time) < Self.minSpacing, last.percent == window.percent { continue }
            samples.append(UsageSample(account: account, key: window.key, time: now, percent: window.percent))
        }
        let cutoff = now.addingTimeInterval(-Self.retention)
        samples.removeAll { $0.time < cutoff }
    }

    public func samples(account: UUID, key: String, since: Date) -> [UsageSample] {
        samples.filter { $0.account == account && $0.key == key && $0.time >= since }
    }

    public mutating func remove(account: UUID) {
        samples.removeAll { $0.account == account }
    }
}

public struct UsageHistoryStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL = UsageHistoryStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        AppConfigStore.defaultFileURL.deletingLastPathComponent().appendingPathComponent("history.json")
    }

    public func load() -> UsageHistory {
        guard let data = try? Data(contentsOf: fileURL),
              let history = try? JSONDecoder().decode(UsageHistory.self, from: data) else { return UsageHistory() }
        return history
    }

    public func save(_ history: UsageHistory) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: fileURL, options: .atomic) }
    }
}

/// Compares actual usage with burning the window down evenly until it resets.
public struct Pace: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case ahead, onTrack, behind }

    /// Where an even burn would be by now, 0...100.
    public let expectedPercent: Double
    public let actualPercent: Double
    public var delta: Double { actualPercent - expectedPercent }

    /// Within this many points of the guide counts as on track.
    public static let tolerance = 5.0

    public var status: Status {
        if delta > Self.tolerance { return .ahead }
        if delta < -Self.tolerance { return .behind }
        return .onTrack
    }

    public var summary: String {
        let points = Int(abs(delta).rounded())
        switch status {
        case .ahead: return "\(points) pts ahead of even use"
        case .behind: return "\(points) pts under even use"
        case .onTrack: return "On pace"
        }
    }

    public init?(window: UsageWindow, now: Date = Date()) {
        guard let length = window.length, let resetsAt = window.resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0, remaining <= length else { return nil }
        expectedPercent = (length - remaining) / length * 100
        actualPercent = window.percent
    }
}
