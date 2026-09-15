import Foundation

public enum KiroError: Error {
    /// Kiro isn't signed in, or its token expired while Kiro was closed.
    case notSignedIn
    case requestFailed(Int)
    case decodingFailed
}

/// Fetches Kiro's monthly credit usage via the control-plane API the Kiro IDE's
/// own usage dashboard calls, authenticating with the login Kiro stores on disk.
///
/// Read-only: the token is never refreshed here, since Kiro owns it and a refresh
/// could rotate the refresh token out from under the IDE. Kiro refreshes it while
/// running; a stale token surfaces as `notSignedIn`.
public struct KiroProvider: UsageProvider {
    public static let vendorID = "kiro"
    public static let displayName = "Kiro"

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var tokenURL: URL { home.appendingPathComponent(".aws/sso/cache/kiro-auth-token.json") }
    private static var profileURL: URL {
        home.appendingPathComponent("Library/Application Support/Kiro/User/globalStorage/kiro.kiroagent/profile.json")
    }

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    private struct Token: Decodable {
        let accessToken: String
        let expiresAt: String?
        let region: String?
        /// Present for Google/GitHub logins; Builder ID keeps it in `profile.json`.
        let profileArn: String?
    }

    private struct Profile: Decodable { let arn: String }

    public func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        guard let tokenData = try? Data(contentsOf: Self.tokenURL),
              let token = try? JSONDecoder().decode(Token.self, from: tokenData) else {
            throw KiroError.notSignedIn
        }
        if let expiresAt = token.expiresAt.flatMap(Self.parseDate), expiresAt < Date() {
            throw KiroError.notSignedIn
        }
        let profileArn = token.profileArn ?? (try? Data(contentsOf: Self.profileURL))
            .flatMap { try? JSONDecoder().decode(Profile.self, from: $0) }?.arn

        var components = URLComponents(string: "https://management.\(token.region ?? "us-east-1").kiro.dev/Get-Usage-Limits")!
        components.queryItems = [
            URLQueryItem(name: "origin", value: "AI_EDITOR"),
            URLQueryItem(name: "resourceType", value: "AGENTIC_REQUEST"),
        ] + (profileArn.map { [URLQueryItem(name: "profileArn", value: $0)] } ?? [])
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw status == 401 || status == 403 ? KiroError.notSignedIn : KiroError.requestFailed(status)
        }
        return try Self.snapshot(from: data)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    // MARK: - Response

    private struct UsageLimits: Decodable {
        struct Subscription: Decodable { let subscriptionTitle: String? }
        struct Breakdown: Decodable {
            let resourceType: String?
            let currentUsageWithPrecision: Double?
            let currentOveragesWithPrecision: Double?
            let usageLimitWithPrecision: Double?
        }
        /// Epoch seconds.
        let nextDateReset: Double?
        let subscriptionInfo: Subscription?
        let usageBreakdownList: [Breakdown]?
    }

    /// Kiro meters one monthly credit pool, mapped to the primary bar with a
    /// "Monthly" label. `currentUsage` includes overage spend, so plan usage is
    /// usage minus overages (as CodexBar does) to keep the bar at or under 100%.
    static func snapshot(from data: Data) throws -> UsageSnapshot {
        guard let limits = try? JSONDecoder().decode(UsageLimits.self, from: data),
              let credits = limits.usageBreakdownList?.first(where: { $0.resourceType == "CREDIT" }) ?? limits.usageBreakdownList?.first,
              let limit = credits.usageLimitWithPrecision, limit > 0 else {
            throw KiroError.decodingFailed
        }
        let used = (credits.currentUsageWithPrecision ?? 0) - (credits.currentOveragesWithPrecision ?? 0)
        let plan = limits.subscriptionInfo?.subscriptionTitle
        return UsageSnapshot(
            percentUsed: used / limit * 100,
            resetsAt: limits.nextDateReset.map(Date.init(timeIntervalSince1970:)),
            detailLabel: [plan, String(format: "%g / %g credits", used, limit)].compactMap { $0 }.joined(separator: " · "),
            primaryLabel: "Monthly"
        )
    }
}
