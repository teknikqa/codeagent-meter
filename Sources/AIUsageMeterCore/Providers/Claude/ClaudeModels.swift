import Foundation

/// DTOs for `api.anthropic.com/api/oauth/usage` and `/api/oauth/profile`.
/// Anthropic doesn't publish a schema for these endpoints, so decoding is
/// deliberately tolerant: every field is optional at the wire level and
/// `UsageSnapshot.raw` retains anything we don't have a typed field for,
/// so a shape change degrades gracefully instead of crashing the refresh.
struct ClaudeOAuthUsageResponse: Decodable {
    let percentUsed: Double?
    let utilization: Double?
    let resetsAt: String?
    let resetTime: String?

    enum CodingKeys: String, CodingKey {
        case percentUsed = "percent_used"
        case utilization
        case resetsAt = "resets_at"
        case resetTime = "reset_time"
    }

    /// Prefers `percentUsed`, falls back to `utilization` (0...1 scaled to a percent).
    var resolvedPercentUsed: Double? {
        if let percentUsed { return percentUsed }
        if let utilization { return utilization * 100 }
        return nil
    }

    var resolvedResetsAt: Date? {
        let isoString = resetsAt ?? resetTime
        guard let isoString else { return nil }
        return ISO8601DateFormatter().date(from: isoString)
    }
}

struct ClaudeOAuthProfileResponse: Decodable {
    let account: Account?

    struct Account: Decodable {
        let emailAddress: String?
        let organizationName: String?
        let planLabel: String?

        enum CodingKeys: String, CodingKey {
            case emailAddress = "email_address"
            case organizationName = "organization_name"
            case planLabel = "plan_label"
        }
    }
}
