import Foundation

public struct UsageSnapshot: Equatable, Sendable {
    /// Rolling 5-hour session window.
    public let percentUsed: Double?
    public let resetsAt: Date?
    /// Rolling 7-day weekly window.
    public let weeklyPercentUsed: Double?
    public let weeklyResetsAt: Date?
    public let detailLabel: String?
    public let raw: [String: String]

    public init(
        percentUsed: Double?,
        resetsAt: Date?,
        weeklyPercentUsed: Double? = nil,
        weeklyResetsAt: Date? = nil,
        detailLabel: String?,
        raw: [String: String] = [:]
    ) {
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
        self.weeklyPercentUsed = weeklyPercentUsed
        self.weeklyResetsAt = weeklyResetsAt
        self.detailLabel = detailLabel
        self.raw = raw
    }
}

public protocol UsageProvider: Sendable {
    static var vendorID: String { get }
    static var displayName: String { get }
    func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot
}
