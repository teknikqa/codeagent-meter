import Foundation

public enum CodexError: Error {
    case noCredentials
    case requestFailed(Int)
    case decodingFailed
}

/// Fetches Codex usage via ChatGPT's undocumented `backend-api/wham/usage`
/// endpoint, authenticating with the tokens Codex CLI stores in
/// `$CODEX_HOME/auth.json`.
///
/// Never refreshes tokens itself: OpenAI rotates refresh tokens on use, so
/// refreshing here would log the CLI out. `auth.json` is re-read on every
/// fetch instead, picking up whatever the CLI last refreshed.
public struct CodexProvider: UsageProvider {
    public static let vendorID = "codex"
    public static let displayName = "Codex"
    public static let defaultHome = "~/.codex"

    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        let tokens = try Self.readTokens(codexHome: account.codexHome ?? Self.defaultHome)

        var request = URLRequest(url: Self.usageURL)
        request.timeoutInterval = 30
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(tokens.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CodexError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try Self.snapshot(from: data)
    }

    // MARK: - auth.json

    struct Tokens: Decodable {
        let accessToken: String
        let accountId: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountId = "account_id"
        }
    }

    static func readTokens(codexHome: String) throws -> Tokens {
        struct AuthFile: Decodable { let tokens: Tokens? }
        let url = URL(fileURLWithPath: (codexHome as NSString).expandingTildeInPath)
            .appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url),
              let tokens = try? JSONDecoder().decode(AuthFile.self, from: data).tokens else {
            throw CodexError.noCredentials
        }
        return tokens
    }

    // MARK: - Response

    private struct UsageResponse: Decodable {
        struct Window: Decodable {
            let usedPercent: Double?
            let limitWindowSeconds: Double?
            let resetAt: Double?

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case limitWindowSeconds = "limit_window_seconds"
                case resetAt = "reset_at"
            }
        }

        struct RateLimit: Decodable {
            let primaryWindow: Window?
            let secondaryWindow: Window?

            enum CodingKeys: String, CodingKey {
                case primaryWindow = "primary_window"
                case secondaryWindow = "secondary_window"
            }
        }

        let email: String?
        let planType: String?
        let rateLimit: RateLimit?

        enum CodingKeys: String, CodingKey {
            case email
            case planType = "plan_type"
            case rateLimit = "rate_limit"
        }
    }

    /// Primary/secondary aren't fixed to session/weekly — a Plus plan can
    /// return only a 7-day primary window — so windows are classified by
    /// their length: under a day is the session window, otherwise weekly.
    static func snapshot(from data: Data) throws -> UsageSnapshot {
        guard let usage = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
            throw CodexError.decodingFailed
        }
        let windows = [usage.rateLimit?.primaryWindow, usage.rateLimit?.secondaryWindow].compactMap { $0 }
        let session = windows.first { ($0.limitWindowSeconds ?? 0) < 86_400 }
        let weekly = windows.first { ($0.limitWindowSeconds ?? 0) >= 86_400 }
        let detail = [usage.email, usage.planType].compactMap { $0 }.joined(separator: " · ")

        return UsageSnapshot(
            percentUsed: session?.usedPercent,
            resetsAt: session?.resetAt.map { Date(timeIntervalSince1970: $0) },
            weeklyPercentUsed: weekly?.usedPercent,
            weeklyResetsAt: weekly?.resetAt.map { Date(timeIntervalSince1970: $0) },
            detailLabel: detail.isEmpty ? nil : detail
        )
    }
}
