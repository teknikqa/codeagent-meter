import Foundation

public enum AntigravityError: Error {
    /// No running Antigravity server, and no usable `agy` login in the Keychain.
    case notSignedIn
    case clientMetadataNotFound
    case requestFailed(Int)
    case decodingFailed
}

/// Antigravity usage from two sources, freshest first:
/// 1. The local language server of a running Antigravity app or IDE — needs no
///    stored credentials.
/// 2. `agy` CLI's Google login from the Keychain, against Google's Code Assist API.
///
/// Antigravity meters two independent quota groups (Gemini, and Claude + GPT),
/// each with a 5-hour and a weekly limit, so snapshots carry one `UsageGroup` per group.
public struct AntigravityProvider: UsageProvider {
    public static let vendorID = "antigravity"
    public static let displayName = "Antigravity"

    private let localServerClient = AntigravityLocalServerClient()
    private let oauthClient: AntigravityOAuthClient

    public init(urlSession: URLSession = .shared) {
        self.oauthClient = AntigravityOAuthClient(urlSession: urlSession)
    }

    public func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        if let snapshot = await localServerClient.fetchUsage() {
            return snapshot
        }
        return try await oauthClient.fetchUsage(for: account)
    }

    // MARK: - Quota summary parsing

    private struct Groups: Decodable {
        struct Group: Decodable {
            let displayName: String?
            let buckets: [Bucket]?
        }

        struct Bucket: Decodable {
            let bucketId: String?
            let window: String?
            let remainingFraction: Double?
            let resetTime: String?
        }

        let groups: [Group]?
    }

    /// The local server wraps the payload in `response`; the remote API doesn't.
    private struct Envelope: Decodable {
        let response: Groups?
    }

    /// Parses a `RetrieveUserQuotaSummary` payload (local or remote shape).
    static func snapshot(fromQuotaSummary data: Data, detailLabel: String?) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        guard let groups = (try? decoder.decode(Envelope.self, from: data))?.response?.groups
            ?? (try? decoder.decode(Groups.self, from: data))?.groups,
            !groups.isEmpty else {
            throw AntigravityError.decodingFailed
        }

        let usageGroups = groups.map { group -> UsageGroup in
            let buckets = group.buckets ?? []
            let session = buckets.first { $0.window == "5h" || $0.bucketId?.hasSuffix("-5h") == true }
            let weekly = buckets.first { $0.window == "weekly" || $0.bucketId?.hasSuffix("-weekly") == true }
            return UsageGroup(
                name: shortName(group.displayName ?? "Quota"),
                snapshot: UsageSnapshot(
                    percentUsed: session?.remainingFraction.map { (1 - $0) * 100 },
                    resetsAt: session?.resetTime.flatMap(parseDate),
                    weeklyPercentUsed: weekly?.remainingFraction.map { (1 - $0) * 100 },
                    weeklyResetsAt: weekly?.resetTime.flatMap(parseDate),
                    detailLabel: nil
                )
            )
        }

        // Top-level numbers track the most-used group, for the menu bar headline.
        let busiestSession = usageGroups.max { ($0.snapshot.percentUsed ?? -1) < ($1.snapshot.percentUsed ?? -1) }?.snapshot
        let busiestWeekly = usageGroups.max { ($0.snapshot.weeklyPercentUsed ?? -1) < ($1.snapshot.weeklyPercentUsed ?? -1) }?.snapshot
        return UsageSnapshot(
            percentUsed: busiestSession?.percentUsed,
            resetsAt: busiestSession?.resetsAt,
            weeklyPercentUsed: busiestWeekly?.weeklyPercentUsed,
            weeklyResetsAt: busiestWeekly?.weeklyResetsAt,
            detailLabel: detailLabel,
            groups: usageGroups
        )
    }

    private static func shortName(_ displayName: String) -> String {
        switch displayName {
        case "Gemini Models": return "Gemini"
        case "Claude and GPT models": return "Claude + GPT"
        default: return displayName
        }
    }

    /// RFC 3339 with any fractional precision (Go writes nanoseconds, which
    /// `ISO8601DateFormatter` rejects), so fractions are dropped before parsing.
    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
