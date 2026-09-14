import Foundation

public enum ClaudeAuthKind: String, Codable, Sendable {
    case cliKeychain
    case cookie
    case adminKey
    case codexCLI
}

public struct ClaudeAccount: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var label: String
    public var authKind: ClaudeAuthKind
    public var keychainKey: String
    public var orgId: String?
    /// `CODEX_HOME` for `.codexCLI` accounts, e.g. `~/.codex`.
    public var codexHome: String?
    public var createdAt: Date
    public var lastRefreshedAt: Date?

    public init(
        id: UUID = UUID(),
        label: String,
        authKind: ClaudeAuthKind,
        keychainKey: String,
        orgId: String? = nil,
        codexHome: String? = nil,
        createdAt: Date = Date(),
        lastRefreshedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.authKind = authKind
        self.keychainKey = keychainKey
        self.orgId = orgId
        self.codexHome = codexHome
        self.createdAt = createdAt
        self.lastRefreshedAt = lastRefreshedAt
    }

    public var vendorID: String {
        authKind == .codexCLI ? CodexProvider.vendorID : ClaudeProvider.vendorID
    }
}
