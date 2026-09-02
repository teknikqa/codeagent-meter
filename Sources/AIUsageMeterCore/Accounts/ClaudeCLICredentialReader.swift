import Foundation

public enum ClaudeCLICredentialError: Error {
    case notFound
    case malformedData
}

public struct ClaudeCLICredentials: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
}

/// Reads the OAuth credentials Claude Code CLI stores for itself, so this app can
/// borrow them read-only. Never writes back to the CLI's own storage — see
/// `ClaudeOAuthClient` for how refreshed tokens are cached separately.
public struct ClaudeCLICredentialReader: Sendable {
    /// The Keychain service name Claude Code CLI writes its own credentials under.
    static let keychainService = "Claude Code-credentials"

    private static var fileFallbackURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    public init() {}

    public func readCredentials() throws -> ClaudeCLICredentials {
        if let data = try? KeychainStore.readFirstData(service: Self.keychainService) {
            return try Self.decode(data)
        }
        guard let fileData = try? Data(contentsOf: Self.fileFallbackURL) else {
            throw ClaudeCLICredentialError.notFound
        }
        return try Self.decode(fileData)
    }

    /// Matches the shape of Claude Code's own credential storage:
    /// a top-level `claudeAiOauth` object with `accessToken`/`refreshToken`/`expiresAt`
    /// (epoch milliseconds), alongside unrelated `mcpOAuth` entries this app ignores.
    private static func decode(_ data: Data) throws -> ClaudeCLICredentials {
        struct CredentialsFile: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                let refreshToken: String?
                let expiresAt: Double
            }
            let claudeAiOauth: OAuth
        }
        guard let file = try? JSONDecoder().decode(CredentialsFile.self, from: data) else {
            throw ClaudeCLICredentialError.malformedData
        }
        let oauth = file.claudeAiOauth
        return ClaudeCLICredentials(
            accessToken: oauth.accessToken,
            refreshToken: oauth.refreshToken,
            expiresAt: Date(timeIntervalSince1970: oauth.expiresAt / 1000)
        )
    }
}
