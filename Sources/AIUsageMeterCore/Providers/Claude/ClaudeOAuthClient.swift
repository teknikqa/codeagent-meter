import Foundation

public enum ClaudeOAuthError: Error {
    case noCredentials
    case refreshFailed
    case requestFailed(Int)
    case decodingFailed
}

/// Fetches Claude usage via the undocumented OAuth usage/profile endpoints,
/// authenticating with the credentials Claude Code CLI already stores.
///
/// Never writes back into the CLI's own Keychain item — refreshed tokens are
/// cached separately under this app's own service so the CLI's session is
/// never touched.
public struct ClaudeOAuthClient: Sendable {
    private static let tokenCacheService = "com.nickmathew.ai-usage-meter.claude-cli-cache"
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let tokenRefreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    private let credentialReader: ClaudeCLICredentialReader
    private let tokenCache: KeychainStore
    private let urlSession: URLSession

    public init(
        credentialReader: ClaudeCLICredentialReader = ClaudeCLICredentialReader(),
        urlSession: URLSession = .shared
    ) {
        self.credentialReader = credentialReader
        self.tokenCache = KeychainStore(service: Self.tokenCacheService)
        self.urlSession = urlSession
    }

    public func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        let accessToken = try await validAccessToken(for: account)
        let usage = try await fetchJSON(ClaudeOAuthUsageResponse.self, url: Self.usageURL, accessToken: accessToken)
        let profile = try? await fetchJSON(ClaudeOAuthProfileResponse.self, url: Self.profileURL, accessToken: accessToken)

        return UsageSnapshot(
            percentUsed: usage.resolvedPercentUsed,
            resetsAt: usage.resolvedResetsAt,
            planLabel: profile?.account?.planLabel
        )
    }

    // MARK: - Token handling

    private struct CachedToken: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
    }

    private func validAccessToken(for account: ClaudeAccount) async throws -> String {
        if let cached = cachedToken(for: account), cached.expiresAt > Date() {
            return cached.accessToken
        }

        // Prefer refreshing with whatever refresh token we have cached; fall back to
        // re-reading the CLI's own credential item in case it holds a newer one.
        let refreshToken = cachedToken(for: account)?.refreshToken
            ?? (try? credentialReader.readCredentials())?.refreshToken

        if let refreshed = try? await refreshAccessToken(refreshToken: refreshToken) {
            cache(refreshed, for: account)
            return refreshed.accessToken
        }

        // Last resort: use the CLI's current access token directly, even without a
        // successful refresh — it may still be valid, or the request below will
        // surface a clear failure that becomes a "needs re-auth" state upstream.
        guard let credentials = try? credentialReader.readCredentials() else {
            throw ClaudeOAuthError.noCredentials
        }
        return credentials.accessToken
    }

    private func refreshAccessToken(refreshToken: String?) async throws -> CachedToken {
        guard let refreshToken else { throw ClaudeOAuthError.refreshFailed }

        var request = URLRequest(url: Self.tokenRefreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ])

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClaudeOAuthError.refreshFailed
        }

        struct RefreshResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: Double

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
            }
        }
        guard let decoded = try? JSONDecoder().decode(RefreshResponse.self, from: data) else {
            throw ClaudeOAuthError.decodingFailed
        }
        return CachedToken(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? refreshToken,
            expiresAt: Date().addingTimeInterval(decoded.expiresIn)
        )
    }

    private func cachedToken(for account: ClaudeAccount) -> CachedToken? {
        guard let data = try? tokenCache.readData(account: account.keychainKey) else { return nil }
        return try? JSONDecoder().decode(CachedToken.self, from: data)
    }

    private func cache(_ token: CachedToken, for account: ClaudeAccount) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        try? tokenCache.write(data: data, account: account.keychainKey)
    }

    // MARK: - HTTP

    private func fetchJSON<T: Decodable>(_ type: T.Type, url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ClaudeOAuthError.requestFailed(status)
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw ClaudeOAuthError.decodingFailed
        }
        return decoded
    }
}
