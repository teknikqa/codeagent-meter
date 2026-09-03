import Foundation

public enum ClaudeProviderError: Error {
    case adminKeyNotSupported
}

/// The `UsageProvider` Claude presents to the rest of the app. Dispatches to
/// the CLI-Keychain-backed OAuth client or the cookie-based client depending
/// on how a given account authenticates.
public struct ClaudeProvider: UsageProvider {
    public static let vendorID = "claude"
    public static let displayName = "Claude Code"

    private let oauthClient: ClaudeOAuthClient
    private let cookieClient: ClaudeCookieClient

    public init(
        oauthClient: ClaudeOAuthClient = ClaudeOAuthClient(),
        cookieClient: ClaudeCookieClient = ClaudeCookieClient()
    ) {
        self.oauthClient = oauthClient
        self.cookieClient = cookieClient
    }

    public func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        switch account.authKind {
        case .cliKeychain:
            return try await oauthClient.fetchUsage(for: account)
        case .cookie:
            return try await cookieClient.fetchUsage(for: account)
        case .adminKey:
            // Org-level Admin API (cost_report / usage_report/messages) is a
            // distinct, documented endpoint pair — not built for MVP since no
            // onboarding flow creates .adminKey accounts yet.
            throw ClaudeProviderError.adminKeyNotSupported
        }
    }
}
