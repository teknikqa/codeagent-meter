import Foundation

public struct UsageSnapshot: Equatable, Sendable {
    public let percentUsed: Double?
    public let resetsAt: Date?
    public let detailLabel: String?
    public let raw: [String: String]

    public init(
        percentUsed: Double?,
        resetsAt: Date?,
        detailLabel: String?,
        raw: [String: String] = [:]
    ) {
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
        self.detailLabel = detailLabel
        self.raw = raw
    }
}

public protocol UsageProvider: Sendable {
    static var vendorID: String { get }
    static var displayName: String { get }
    func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot
}
