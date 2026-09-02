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

// MARK: - claude.ai cookie-session API (verified against ClaudeMeter's implementation)

/// `GET /api/organizations` — one entry per org the session belongs to.
struct ClaudeOrganization: Decodable {
    let id: Int
    let uuid: String
    let name: String
}

/// `GET /api/organizations/{uuid}/usage`.
struct ClaudeUsageAPIResponse: Decodable {
    let fiveHour: ClaudeUsageLimitResponse
    let sevenDay: ClaudeUsageLimitResponse
    let sevenDaySonnet: ClaudeUsageLimitResponse?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

struct ClaudeUsageLimitResponse: Decodable {
    /// Percentage, 0-100.
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resolvedResetsAt: Date? {
        guard let resetsAt else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: resetsAt) ?? ISO8601DateFormatter().date(from: resetsAt)
    }
}
