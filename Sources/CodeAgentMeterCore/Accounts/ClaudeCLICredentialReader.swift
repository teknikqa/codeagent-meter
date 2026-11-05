import CryptoKit
import Foundation

public enum ClaudeCLICredentialError: Error, Equatable {
    case malformedData
    /// Wraps the specific Keychain/file failure so callers (and diagnostics)
    /// can see the real cause instead of a generic "not found".
    case underlying(String)
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
    public static let defaultConfigDir = "~/.claude"
    private static let keychainServiceBase = "Claude Code-credentials"

    /// Absolute path of the `CLAUDE_CONFIG_DIR` this reader covers.
    private let configDir: String

    public init(configDir: String? = nil) {
        self.configDir = Self.absolutePath(configDir ?? Self.defaultConfigDir)
    }

    private static func absolutePath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).path
    }

    /// Where Claude Code keeps a config dir's login. The default dir (no
    /// `CLAUDE_CONFIG_DIR`) uses the bare name; any other dir gets a suffix of
    /// the first 8 hex digits of the SHA-256 of its path.
    /// shortcut: a dir set explicitly to `~/.claude` hashes in Claude Code but
    /// reads as the default here, so add a hashed lookup if anyone does that.
    /// Internal (not private) so tests can exercise it directly.
    static func keychainService(forConfigDir path: String) -> String {
        let dir = absolutePath(path)
        if dir == absolutePath(defaultConfigDir) { return keychainServiceBase }
        let hash = SHA256.hash(data: Data(dir.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(keychainServiceBase)-\(hash)"
    }

    private var fileFallbackURL: URL {
        URL(fileURLWithPath: configDir).appendingPathComponent(".credentials.json")
    }

    /// The email Claude Code recorded when this dir was signed in, to label the
    /// account. The default dir keeps it in `~/.claude.json`, others inside the dir.
    public func accountEmail() -> String? {
        let isDefault = configDir == Self.absolutePath(Self.defaultConfigDir)
        let url = isDefault
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
            : URL(fileURLWithPath: configDir).appendingPathComponent(".claude.json")
        struct ConfigFile: Decodable {
            struct Account: Decodable { let emailAddress: String? }
            let oauthAccount: Account?
        }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ConfigFile.self, from: data) else { return nil }
        return file.oauthAccount?.emailAddress
    }

    public func readCredentials() throws -> ClaudeCLICredentials {
        do {
            let data = try KeychainStore.readFirstData(service: Self.keychainService(forConfigDir: configDir))
            return try Self.decode(data)
        } catch let keychainError as KeychainError {
            guard let fileData = try? Data(contentsOf: fileFallbackURL) else {
                // Neither source worked — surface the Keychain failure, since
                // it's the primary path and the more informative of the two.
                throw ClaudeCLICredentialError.underlying(String(describing: keychainError))
            }
            return try Self.decode(fileData)
        }
    }

    /// Matches the shape of Claude Code's own credential storage:
    /// a top-level `claudeAiOauth` object with `accessToken`/`refreshToken`/`expiresAt`
    /// (epoch milliseconds), alongside unrelated `mcpOAuth` entries this app ignores.
    /// Internal (not private) so tests can exercise decoding with synthetic
    /// JSON instead of depending on real Keychain/file state.
    static func decode(_ data: Data) throws -> ClaudeCLICredentials {
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
