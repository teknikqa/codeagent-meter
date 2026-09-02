import Foundation

public enum ClaudeCookieError: Error {
    case missingCookie
    case missingOrganizationId
    case invalidSessionKey
    case requestFailed(Int)
    case decodingFailed
    case noOrganizationsFound
}

/// Fetches Claude usage via claude.ai's session-cookie-authenticated API, the
/// manual fallback for accounts without a local Claude Code CLI login.
public struct ClaudeCookieClient: Sendable {
    /// Keychain service this app's own secrets (session cookies) live under.
    static let secretsService = "com.nickmathew.codeagent-meter"
    private static let baseURL = "https://claude.ai/api"

    private let secretsStore: KeychainStore
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.secretsStore = KeychainStore(service: Self.secretsService)
        self.urlSession = urlSession
    }

    public func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        guard let orgId = account.orgId else { throw ClaudeCookieError.missingOrganizationId }
        let sessionKey = try readSessionKey(account: account)

        let usage: ClaudeUsageAPIResponse = try await request(
            "\(Self.baseURL)/organizations/\(orgId)/usage",
            sessionKey: sessionKey
        )

        var raw: [String: String] = [:]
        if let sevenDayUtilization = usage.sevenDay.utilization {
            raw["sevenDayUtilization"] = String(sevenDayUtilization)
        }
        if let sevenDayResetsAt = usage.sevenDay.resetsAt {
            raw["sevenDayResetsAt"] = sevenDayResetsAt
        }

        return UsageSnapshot(
            percentUsed: usage.fiveHour.utilization,
            resetsAt: usage.fiveHour.resolvedResetsAt,
            detailLabel: nil,
            raw: raw
        )
    }

    /// Validates a pasted session-key cookie and discovers the account's primary
    /// organization, so onboarding can fail fast on a bad cookie before ever
    /// creating an account row.
    public func validateAndDiscoverOrganization(sessionKey: String) async throws -> (orgId: String, orgName: String) {
        let organizations: [ClaudeOrganization] = try await request(
            "\(Self.baseURL)/organizations",
            sessionKey: Self.normalizeSessionKey(sessionKey)
        )
        guard let first = organizations.first else { throw ClaudeCookieError.noOrganizationsFound }
        return (first.uuid, first.name)
    }

    public func storeSessionKey(_ sessionKey: String, account: ClaudeAccount) throws {
        let normalized = Self.normalizeSessionKey(sessionKey)
        guard let data = normalized.data(using: .utf8) else { throw ClaudeCookieError.missingCookie }
        try secretsStore.write(data: data, account: account.keychainKey)
    }

    /// Users are commonly instructed to copy the cookie two different ways:
    /// just the bare `sessionKey` value (Application/Storage tab), or the
    /// full `Cookie:` request header (Network tab, which bundles every
    /// cookie together). Accept either and extract just the value we need.
    /// Internal (not private) so tests can exercise it directly.
    static func normalizeSessionKey(_ rawInput: String) -> String {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "sessionKey=") else { return trimmed }
        let afterKey = trimmed[range.upperBound...]
        let value = afterKey.split(separator: ";", maxSplits: 1)[0]
        return value.trimmingCharacters(in: .whitespaces)
    }

    private func readSessionKey(account: ClaudeAccount) throws -> String {
        guard let data = try? secretsStore.readData(account: account.keychainKey),
              let sessionKey = String(data: data, encoding: .utf8) else {
            throw ClaudeCookieError.missingCookie
        }
        return sessionKey
    }

    // MARK: - HTTP

    private func request<T: Decodable>(_ endpoint: String, sessionKey: String) async throws -> T {
        guard let url = URL(string: endpoint) else { throw ClaudeCookieError.requestFailed(-1) }

        var request = URLRequest(url: url)
        // claude.ai fronts its API with Cloudflare bot detection; a browser-shaped
        // request (cookie header, UA, fetch metadata) is required to get past it.
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeCookieError.requestFailed(-1) }
        if http.statusCode == 401 { throw ClaudeCookieError.invalidSessionKey }
        guard (200...299).contains(http.statusCode) else {
            throw ClaudeCookieError.requestFailed(http.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw ClaudeCookieError.decodingFailed
        }
        return decoded
    }
}
