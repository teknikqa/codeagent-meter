import Foundation

/// A single usage window (e.g. the rolling 5-hour or 7-day limit), shared by
/// both the OAuth and cookie-session APIs — verified to have the same
/// `{ utilization, resets_at }` shape in both (cross-checked against
/// CodexBar's `ClaudeOAuthUsageFetcher` and ClaudeMeter's `UsageLimitResponse`).
/// `utilization` is already a 0-100 percentage, not a 0-1 fraction.
struct ClaudeUsageWindow: Decodable {
    let utilization: Double?
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

/// `GET api.anthropic.com/api/oauth/usage`. Verified against CodexBar's
/// `OAuthUsageResponse` — usage is nested per time window, not a flat object.
struct ClaudeOAuthUsageResponse: Decodable {
    let fiveHour: ClaudeUsageWindow?
    let sevenDay: ClaudeUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    /// The 5-hour session window is the most immediately actionable number
    /// for a menu bar badge, matching what ClaudeMeter surfaces as primary.
    var resolvedPercentUsed: Double? {
        fiveHour?.utilization ?? sevenDay?.utilization
    }

    var resolvedResetsAt: Date? {
        fiveHour?.resolvedResetsAt ?? sevenDay?.resolvedResetsAt
    }
}

/// `GET api.anthropic.com/api/oauth/profile`. Only `email_address` is
/// confirmed present (verified against CodexBar) — nested under `account`
/// or top-level depending on API version.
struct ClaudeOAuthProfileResponse: Decodable {
    let emailAddress: String?

    private enum TopLevelKeys: String, CodingKey {
        case account
        case emailAddress = "email_address"
    }

    private enum AccountKeys: String, CodingKey {
        case emailAddress = "email_address"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TopLevelKeys.self)
        if let accountContainer = try? container.nestedContainer(keyedBy: AccountKeys.self, forKey: .account),
           let nestedEmail = try? accountContainer.decodeIfPresent(String.self, forKey: .emailAddress) {
            emailAddress = nestedEmail
        } else {
            emailAddress = try container.decodeIfPresent(String.self, forKey: .emailAddress)
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
    let fiveHour: ClaudeUsageWindow
    let sevenDay: ClaudeUsageWindow
    let sevenDaySonnet: ClaudeUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}
